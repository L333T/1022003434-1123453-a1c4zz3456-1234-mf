-- ============================================================================
-- Master Farmer - Grindbot
-- movement/sentinel.lua - actuator: Sentinel navmesh fallback (out of combat)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Optional. Used for long legs, blocked straight lines and stuck recovery.
-- When the client is absent every caller silently degrades to walker steering,
-- so nothing in the plugin may treat Sentinel as required.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type vec3
local vec3 = require("common/geometry/vector_3")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local Z = require("movement/zones")
local W = require("movement/walker")

local OWNER             = K.OWNER
local SN_NEED           = K.SN_NEED
local INFLIGHT_TIMEOUT  = K.INFLIGHT_TIMEOUT
local STUCK_ZONE_RADIUS = K.STUCK_ZONE_RADIUS

local pt, to_vec3 = R.pt, R.to_vec3
local xyz, dlog = U.xyz, U.dlog

local P_DEST, P_TMP = R.P_DEST, R.P_TMP

local N = {}

local function read_client(t) return t.client end

-- ============================================================================
-- STOP
-- ============================================================================
function N.stop()
    if not R.sn_active then return false end
    local c = R.sn_client
    if type(c) == "table" then pcall(c.stop, c) end
    R.sn_active, R.sn_reason = false, nil
    R.sn_leash_hold = false
    R.sn_watch_t = 0
    return true
end

-- ============================================================================
-- CALLBACKS
-- ============================================================================
function N.on_nav_done(ok, reason)
    if not R.sn_active then return end           -- stale: we already stopped/switched
    local r = tostring(reason or "")
    if ok == true then
        R.sn_active, R.sn_reason = false, r
        R.sn_leash_hold = false
        W.clear_dest()
        W.halt()
        return
    end
    if r == "server_timeout" then
        R.sn_ok = false
        R.sn_active, R.sn_reason = false, r
        R.sn_leash_hold = false
        if R.has_dest then
            W.move(pt(P_DEST, R.dest_x, R.dest_y, R.dest_z), "sn_timeout")
        else
            W.clear_dest()
        end
        return
    end
    if r == "unreachable" or r == "navmesh" or r == "blocked" then
        W.mark_fail("unreachable")
    elseif r == "max_stuck_exceeded" then
        W.mark_fail("max_stuck_exceeded")
        if R.has_dest then
            Z.blacklist_area(pt(P_TMP, R.dest_x, R.dest_y, R.dest_z),
                STUCK_ZONE_RADIUS, "max_stuck_exceeded")
        end
    else
        W.mark_fail(r ~= "" and r or "failed")
    end
    R.sn_active, R.sn_reason = false, r
    R.sn_leash_hold = false
    W.clear_dest()
    W.halt()
end

local on_nav_done = N.on_nav_done

local function on_sn_stuck()
    on_nav_done(false, "max_stuck_exceeded")
end

local function on_sn_failed(reason)
    on_nav_done(false, reason or "failed")
end

local function on_plan_done(ok, data)
    R.sn_plan_pending = false
    if ok == true and type(data) == "table" and type(data.visit_order) == "table" then
        R.sn_plan_order = data.visit_order
    end
end

local function on_reach_done(reachable, reason, _distance)
    R.sn_reach_pending = false
    R.sn_reach_ok = reachable == true
    if not R.sn_reach_ok then
        W.mark_fail(tostring(reason or "unreachable"))
    end
end

local function bind_sn_events(c)
    if R.sn_events or type(c) ~= "table" then return end
    if type(c.on) == "function" then
        local ok1 = pcall(c.on, c, "stuck", on_sn_stuck)
        local ok2 = pcall(c.on, c, "failed", on_sn_failed)
        R.sn_events = ok1 == true or ok2 == true
        return
    end
    if type(c.get_event_bus) ~= "function" then return end
    local okB, bus = pcall(c.get_event_bus, c)
    if not okB or type(bus) ~= "table" or type(bus.on) ~= "function" then return end
    local opts = { owner = N }
    local ok1 = pcall(bus.on, bus, "stuck", on_sn_stuck, opts)
    local ok2 = pcall(bus.on, bus, "failed", on_sn_failed, opts)
    R.sn_events = ok1 == true or ok2 == true
end

-- ============================================================================
-- CLIENT
-- ============================================================================
--- Resolve the Sentinel client, re-probed at most every 5s. nil = unavailable,
--- in which case every caller silently falls back to walker steering.
function N.client()
    local t = izi.now()
    if (t - R.sn_checked_t) < 5 then return R.sn_ok and R.sn_client or nil end
    R.sn_checked_t = t
    R.sn_ok, R.sn_client = false, nil
    local S = rawget(_G, "SentinelNavClient")
    if type(S) ~= "table" then return nil end
    local ok, c = pcall(read_client, S)
    if not ok or type(c) ~= "table" then return nil end
    for i = 1, #SN_NEED do
        if type(c[SN_NEED[i]]) ~= "function" then return nil end
    end
    local okA, avail = pcall(c.is_server_available, c)
    if not okA or avail ~= true then return nil end
    bind_sn_events(c)
    R.sn_ok, R.sn_client = true, c
    return c
end

local client = N.client

-- ============================================================================
-- COMMAND
-- ============================================================================
--- Issue a Sentinel move_to. Combat never goes here. Fresh vec3 per move.
function N.move(p, why)
    if R.cur_owner == OWNER.COMBAT then return false end
    local c = client()
    if not c or type(p) ~= "table" then return false end
    W.halt()
    W.begin_issue(p.x, p.y, p.z)
    R.sn_active, R.sn_reason = true, nil
    R.sn_leash_hold = true
    R.sn_watch_t = izi.now()
    local ok = pcall(c.move_to, c, to_vec3(p), on_nav_done)
    if not ok then
        R.sn_active, R.sn_reason = false, nil
        R.sn_leash_hold = false
        W.clear_dest()
        return false
    end
    dlog("issue", string.format("sentinel %s -> (%.1f, %.1f, %.1f)",
        tostring(why or ""), p.x, p.y, p.z))
    return true
end

-- ============================================================================
-- WATCHDOG  (called from pulse while Sentinel is driving)
-- ============================================================================
function N.watch(t)
    if (t - R.sn_watch_t) < 1.0 then return end
    R.sn_watch_t = t
    local c = R.sn_client
    if type(c) == "table" then
        local ok, st = pcall(c.get_state, c)
        if ok then
            if st == "arrived" then
                on_nav_done(true, "arrived")
            elseif st == "failed" then
                on_nav_done(false, "failed")
            elseif st == "idle" and (t - R.last_move_t) >= INFLIGHT_TIMEOUT then
                on_nav_done(false, "server_timeout")
            end
        elseif (t - R.last_move_t) >= INFLIGHT_TIMEOUT then
            on_nav_done(false, "server_timeout")
        end
    elseif (t - R.last_move_t) >= INFLIGHT_TIMEOUT then
        on_nav_done(false, "server_timeout")
    end
end

-- ============================================================================
-- HELPERS  (grind node order / reachability; one shot, not per frame)
-- ============================================================================
function N.plan_grind_route(coords)
    if type(coords) ~= "table" or #coords < 2 then return nil end
    if R.sn_plan_key == coords then return R.sn_plan_order end
    local c = client()
    if not c or type(c.plan_route) ~= "function" then return nil end
    R.sn_plan_key, R.sn_plan_order, R.sn_plan_pending = coords, nil, true
    local nodes = {}
    for i = 1, #coords do
        local x, y, z = xyz(coords[i])
        if x then nodes[#nodes + 1] = vec3.new(x, y, z) end
    end
    if #nodes < 2 then
        R.sn_plan_pending = false
        return nil
    end
    local ok = pcall(c.plan_route, c, nodes, on_plan_done)
    if not ok then R.sn_plan_pending = false end
    return R.sn_plan_order
end

function N.grind_visit_order()
    return R.sn_plan_order
end

--- Cached validate_destination for a grind node index. Returns false only after
--- Sentinel has reported the node unreachable. Pending / no client = true.
function N.node_reachable(pos, index)
    if type(index) ~= "number" then return true end
    if R.sn_reach_index == index then
        if R.sn_reach_pending then return true end
        return R.sn_reach_ok ~= false
    end
    R.sn_reach_index, R.sn_reach_ok, R.sn_reach_pending = index, true, true
    local c = client()
    if not c then
        R.sn_reach_pending, R.sn_reach_ok = false, true
        return true
    end
    local x, y, z = xyz(pos)
    if not x then
        R.sn_reach_pending, R.sn_reach_ok = false, true
        return true
    end
    local ok = pcall(c.validate_destination, c, vec3.new(x, y, z), on_reach_done)
    if not ok then
        R.sn_reach_pending, R.sn_reach_ok = false, true
    end
    return true
end

return N

-- ============================================================================
-- Master Farmer - Grindbot
-- movement/walker.lua - actuator: simple_movement
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- The only thing that actually moves the player, plus the bookkeeping that
-- wraps every issued move (destination latch, quiet windows, failure marking)
-- and the reference-counted pause.
--
-- This module deliberately knows nothing about Sentinel. `halt_all`, which has
-- to stop both actuators, lives in movement/own.lua so that walker and sentinel
-- stay on the same layer instead of requiring each other.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type simple_movement
local walker = require("common/utility/simple_movement")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local Z = require("movement/zones")

local TAG            = K.TAG
local OWNER          = K.OWNER
local SAME_DEST      = K.SAME_DEST
local QUIET_STOP     = K.QUIET_STOP
local QUIET_OFFMESH  = K.QUIET_OFFMESH
local FAIL_COOLDOWN  = K.FAIL_COOLDOWN
local ZONE_RADIUS    = K.ZONE_RADIUS
local OFFMESH_WORDS  = K.OFFMESH_WORDS

local pt, to_vec3 = R.pt, R.to_vec3
local xyz, here_xyz, dist2, dlog = U.xyz, U.here_xyz, U.dist2, U.dlog

local P_TMP = R.P_TMP

local W = {}

-- ============================================================================
-- LIFECYCLE
-- ============================================================================
function W.ensure()
    if R.walker_ready then return walker ~= nil end
    if not walker then return false end
    pcall(walker.set_use_look_at, walker, true)
    pcall(walker.set_smoothing_enabled, walker, false)
    pcall(walker.set_threshold, walker, 2.0)
    pcall(walker.set_final_threshold, walker, 1.0)
    pcall(walker.set_look_distance, walker, 8)
    pcall(walker.set_debug, walker, false)
    R.walker_ready = true
    return true
end

W.ensure()

function W.halt()
    pcall(walker.stop, walker)
    pcall(walker.clear_navigation, walker)
    pcall(walker.strafe, walker, nil)
    R.walker_moving = false
end

--- Sample walker:is_moving() (once per pulse; callers between pulses reuse it).
function W.sample()
    local ok, m = pcall(walker.is_moving, walker)
    R.walker_moving = ok and m == true
    return R.walker_moving
end

--- walker:get_state().state, or nil. Debug/diagnostics only - never a gate.
function W.state_name()
    local ok, st = pcall(walker.get_state, walker)
    if ok and type(st) == "table" and type(st.state) == "string" then return st.state end
    return nil
end

-- ============================================================================
-- PAUSE REFERENCE COUNTING
-- ============================================================================
local function pause_wanted()
    local pr = R.pause_reason
    return pr.cast or pr.restrict or pr.rest or pr.loot or pr.nav
end

--- Apply the pause state implied by pause_reason. Only edges issue a command,
--- so a caller that sets the same reason every frame costs nothing.
local function sync_pause()
    local want = pause_wanted()
    if want == R.walker_paused then return end
    R.walker_paused = want
    if want then
        pcall(walker.pause, walker)
        dlog("pause", "walker paused")
    else
        pcall(walker.resume, walker)
        dlog("pause", "walker resumed")
    end
end

function W.set_pause(reason, on)
    if R.pause_reason[reason] == (on == true) then return end
    R.pause_reason[reason] = on == true
    sync_pause()
end

-- ============================================================================
-- DESTINATION / FAILURE BOOKKEEPING
-- ============================================================================
function W.clear_dest()
    R.pending, R.has_dest = false, false
end

function W.set_quiet(seconds)
    local until_t = izi.now() + (seconds or QUIET_STOP)
    if until_t > R.quiet_until then R.quiet_until = until_t end
end

local function reason_offmesh(reason)
    if type(reason) ~= "string" then return false end
    local r = reason:lower()
    for i = 1, #OFFMESH_WORDS do
        if r:find(OFFMESH_WORDS[i], 1, true) then return true end
    end
    return false
end

function W.mark_fail(reason, at)
    local t = izi.now()
    local lf = R.last_fail
    lf.reason, lf.t, lf.valid = tostring(reason), t, true
    lf.offmesh = reason_offmesh(lf.reason)
    if lf.offmesh then
        R.fail_cooldown_until = t + FAIL_COOLDOWN
        if R.cur_owner ~= OWNER.COMBAT then W.set_quiet(QUIET_OFFMESH) end
        local x, y, z
        if at then x, y, z = xyz(at) end
        if not x and R.has_dest then x, y, z = R.dest_x, R.dest_y, R.dest_z end
        if not x then x, y, z = here_xyz() end
        if x then Z.blacklist_area(pt(P_TMP, x, y, z), ZONE_RADIUS, lf.reason) end
    end
end

function W.same_dest(x, y)
    return R.has_dest and dist2(R.dest_x, R.dest_y, x, y) < SAME_DEST
end

function W.begin_issue(x, y, z)
    if not W.same_dest(x, y) then R.detour_side, R.block_streak = 0, 0 end
    R.pending, R.has_dest = true, true
    R.dest_x, R.dest_y, R.dest_z = x, y, z
    R.last_move_t = izi.now()
    R.last_fail.valid = false
    R.stuck_x, R.stuck_y = here_xyz()
    R.stuck_since = R.last_move_t
end

-- ============================================================================
-- COMMANDS
-- ============================================================================
--- Issue a single-point walker move. Allocates the one vec3 the walker keeps.
function W.move(p, why)
    W.begin_issue(p.x, p.y, p.z)
    local ok, issued = pcall(walker.move_to_position, walker, to_vec3(p))
    if not ok or issued ~= true then
        W.clear_dest()
        W.mark_fail("blocked", p)
        core.log_warning(TAG .. " " .. why .. " failed: blocked")
        return false
    end
    R.walker_moving = true
    dlog("issue", string.format("%s -> (%.1f, %.1f, %.1f)", why, p.x, p.y, p.z))
    return true
end

--- Drive a snapped, pre-filtered point list. Used by nav_path only.
function W.navigate_path(pts)
    local last = pts[#pts]
    W.begin_issue(last.x, last.y, last.z)
    local ok, issued = pcall(walker.navigate, walker, pts, false, true)
    if not ok or issued ~= true then
        W.clear_dest()
        W.mark_fail("blocked", last)
        core.log_warning(TAG .. " nav_path failed: blocked")
        return false
    end
    R.walker_moving = true
    dlog("issue", string.format("nav_path %d pts", #pts))
    return true
end

--- walker:process() is the driver, not a command: it runs for whoever owns
--- movement, and does nothing when the walker has no destination.
function W.process()
    local ok, reached = pcall(walker.process, walker)
    return ok and reached == true
end

return W

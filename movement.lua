-- ============================================================================
-- Master Farmer - Grindbot
-- Single-owner movement: only one subsystem steers on a tick.
--   * NONE / RESTRICTED: invalid, dead, CC, eating/drinking (pause, no new commands)
--   * SIMPLE_MOVEMENT: out-of-combat travel — walker:move_to_position / :navigate / :process
--   * COMBAT_MOVEMENT: in-range fighting — movement_handler pause + look_at (not A-to-B)
-- Chase that is still out of fight range is SIMPLE navigation toward the target.
-- Saved paths pause on combat and resume after combat fully ends.
-- No Sentinel. No NavLib. No FB_Nexus.
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.5.0
-- Folder: Master_Farmer_Grindbot_v1.3.39
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type vec3
local vec3 = require("common/geometry/vector_3")

---@type enums
local enums = require("common/enums")

---@type movement_handler
local movement_handler = require("common/utility/movement_handler")

---@type simple_movement
local walker = require("common/utility/simple_movement")

local state = require("state")

local movement = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local TAG             = "[Master Farmer - Grindbot]"
local MIN_NAV         = 2.0      -- never issue a move shorter than this
local ARRIVE          = 2.0
local SAME_DEST       = 6.0      -- destinations closer than this are "the same"
local MOVE_GAP        = 0.85     -- seconds between patrol moves
local CHASE_GAP       = 0.5      -- seconds between combat moves
local INFLIGHT_TIMEOUT = 8.0     -- an issued move counts as moving for this long
local FAIL_COOLDOWN   = 6.0
local QUIET_STOP      = 1.25
local QUIET_422       = 5.0
local ZONE_RADIUS     = 12.0
local ZONE_MERGE      = 10.0
local ZONE_TTL        = 900.0
local ZONE_PRUNE_EVERY = 5.0
local MAX_ZONES       = 24
local STUCK_ZONE_RADIUS = 14.0
local STUCK_GRACE     = 4.0
local STUCK_MOVE      = 1.5      -- yards of progress that resets the stuck timer
local EYE_Z           = 1.6
local STEER_HOP       = 5.0      -- combat / avoidance hop length
local PATROL_HOP      = 40.0     -- patrol hop length when the direct line is clear
local CHASE_GIVE_UP   = 10.0
local TRACE_BUDGET    = 10       -- trace lines per pulse
local STEER_BACKOFF   = 0.5      -- seconds before retrying a steer that found nothing
local PATH_LEASH      = 10.0
local SIDESTEP_YARDS  = { 4, 8 }
local OFFSET_DEGREES  = { 35, -35, 70, -70 }
-- after repeated blocked passes the search widens: walk along, then back around
local ESCALATE = {
    { angles = OFFSET_DEGREES,           hop = nil },   -- streak 0-1
    { angles = { 70, -70, 110, -110 },   hop = 8.0 },   -- streak 2
    { angles = { 110, -110, 150, -150 }, hop = 12.0 },  -- streak 3+
}
local ORBIT_DEGREES   = { 45, -45, 90, -90 }
local COMBAT_OFFSET   = { 45, -45, 90, -90 }
local OFFMESH_WORDS   = { "navmesh", "unreachable", "blocked", "blacklisted", "422", "max_stuck" }
local OWNER_NONE       = 0
local OWNER_SIMPLE     = 1
local OWNER_COMBAT     = 2
local OWNER_RESTRICTED = 3
local KITE_ENTER       = 8.0
local KITE_EXIT        = 10.0

local FLAG_COLLISION, FLAG_LOS
do
    local cf = type(enums) == "table" and enums.collision_flags
    if type(cf) == "table" then
        if type(cf.Collision) == "number" then FLAG_COLLISION = cf.Collision end
        if type(cf.LineOfSight) == "number" then FLAG_LOS = cf.LineOfSight end
    end
end

local sqrt, abs, sin, cos, rad = math.sqrt, math.abs, math.sin, math.cos, math.rad

-- ============================================================================
-- RUNTIME STATE  (numbers and flags only - no tables are rebuilt per frame)
-- ============================================================================
local pending        = false     -- a move was issued and has not been reported done
local walker_moving  = false     -- walker:is_moving() sampled once per pulse
local has_dest       = false
local dest_x, dest_y, dest_z = 0, 0, 0
local last_move_t    = 0
local last_stop_t    = 0
local quiet_until    = 0
local fail_cooldown_until = 0
local steer_backoff_until = 0
local stuck_grace_until   = 0
local last_face_t    = 0
local engage         = false
local rest_lock      = false
local fight_stopped  = false
local walker_ready   = false
local traces_used    = 0
local stuck_x, stuck_y, stuck_since = nil, nil, 0
local chase_fail_key, chase_fail_t = nil, 0
local detour_side    = 0         -- +1 left / -1 right: side that last got us round an obstacle
local block_streak   = 0         -- consecutive steering passes whose straight hop was blocked
local lock_gen       = 0
local pulse_tick     = 0
local debug_on       = false
local owner          = OWNER_NONE
local owner_why      = "init"
local cc_lock        = false
local combat_event   = false
local kite_active    = false
local last_owner_log_t = 0

-- last failure: one table, fields overwritten
local last_fail = { reason = nil, offmesh = false, t = 0, valid = false }

-- blacklist zones: array of { x, y, z, r, t, hits, why } pruned in place
local zones = {}
local zones_pruned_t = 0

-- path leash: flat number array { x1, y1, z1, x2, y2, z2, ... }
local leash        = nil
local leash_n      = 0          -- number of points
local leash_armed  = false
local leash_src    = nil        -- caller's waypoint table (identity check)
-- per-pulse cache of the player's projection onto the leash
local lc_tick, lc_x, lc_y, lc_z, lc_d, lc_i = -1, 0, 0, 0, nil, 1

-- follow_path cache: the caller's point list and the snapped copy given to the walker
local path_src = nil
local path_pts = nil

-- preallocated vec3s for natives that want a vec3 argument
local TRACE_A = vec3.new(0, 0, 0)
local TRACE_B = vec3.new(0, 0, 0)
local HEIGHT_Q = vec3.new(0, 0, 0)

-- candidate point pool: plain { x, y, z } tables reused every steering pass.
-- A pool point is only valid until the next steering call - copy it (to_vec3)
-- before handing it to anything that keeps it.
local POOL = {}
for i = 1, 12 do POOL[i] = { x = 0, y = 0, z = 0 } end
local P_HERE, P_DEST, P_PRIMARY, P_ALT, P_ON, P_SEED, P_MID, P_STEP, P_ORBIT, P_TMP = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10

local function pt(i, x, y, z)
    local p = POOL[i]
    p.x, p.y, p.z = x, y, z
    return p
end

local function to_vec3(p)
    return vec3.new(p.x, p.y, p.z)
end

local function log(msg)
    core.log(TAG .. " " .. msg)
end

local function dlog(msg)
    if debug_on then core.log(TAG .. " [move] " .. msg) end
end

local function set_owner(next_owner, why)
    if owner == next_owner then
        return
    end
    owner = next_owner
    owner_why = why or ""
    local t = izi.now()
    if debug_on and (t - last_owner_log_t) >= 0.25 then
        last_owner_log_t = t
        local name = "none"
        if next_owner == OWNER_SIMPLE then
            name = "simple"
        elseif next_owner == OWNER_COMBAT then
            name = "combat"
        elseif next_owner == OWNER_RESTRICTED then
            name = "restricted"
        end
        dlog("owner=" .. name .. " (" .. tostring(why or "") .. ")")
    end
end

local function flag_true(unit, method)
    if not unit or type(method) ~= "function" then
        return false
    end
    local ok, v = pcall(method, unit)
    return ok == true and v == true
end

-- Stun/fear/incap/disorient: do not issue movement. Root: cannot walk, MH face still ok.
local function movement_restricted(me)
    if not me then
        return true, "no_player"
    end
    if not flag_true(me, me.is_valid) then
        return true, "invalid"
    end
    if flag_true(me, me.is_dead) then
        return true, "dead"
    end
    if rest_lock then
        return true, "rest"
    end
    if flag_true(me, me.is_stunned) then
        return true, "stun"
    end
    if flag_true(me, me.is_feared) then
        return true, "fear"
    end
    if flag_true(me, me.is_incapacitated) then
        return true, "incap"
    end
    if flag_true(me, me.is_disoriented) then
        return true, "disorient"
    end
    if flag_true(me, me.is_rooted) then
        return true, "root"
    end
    return false, nil
end

-- ============================================================================
-- POSITION INPUT
-- ============================================================================
--- Read x, y, z from any position-like value without allocating:
---   vec3 / { x=, y=, z= } / { map_id=, x=, y=, z= } / array { x, y, z }.
--- Returns nil when the value is not a finite 3D position.
local function xyz(p)
    if type(p) ~= "table" then return nil end
    local x, y, z = p.x, p.y, p.z
    if type(x) ~= "number" then
        x, y, z = p[1], p[2], p[3]
    end
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    if x ~= x or y ~= y or z ~= z then return nil end   -- NaN
    return x, y, z
end

--- Public: normalise any accepted position shape to a fresh vec3 (or nil).
function movement.to_pos(p)
    local x, y, z = xyz(p)
    if not x then return nil end
    return vec3.new(x, y, z)
end

local function here_xyz()
    return xyz(state.cached_pos)
end

local function dist3(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return sqrt(dx * dx + dy * dy + dz * dz)
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- ============================================================================
-- GROUND / TRACE
-- ============================================================================
--- Ground height under (x, y); falls back to hint_z when the lookup fails or
--- the terrain is more than 80 yards away from the hint (wrong floor).
local function ground_z(x, y, hint_z)
    HEIGHT_Q.x, HEIGHT_Q.y, HEIGHT_Q.z = x, y, hint_z
    local ok, hz = pcall(core.get_height_for_position, HEIGHT_Q)
    if not ok or type(hz) ~= "number" or hz ~= hz then
        ok, hz = pcall(izi.get_terrain_height, x, y)
    end
    if ok and type(hz) == "number" and hz == hz and abs(hint_z - hz) < 80 then
        return hz
    end
    return hint_z
end

--- Trace at eye height between two points. true = clear, false = hit,
--- nil = no budget left / no flag.
local function trace(a, b, flags)
    if type(flags) ~= "number" or traces_used >= TRACE_BUDGET then return nil end
    traces_used = traces_used + 1
    TRACE_A.x, TRACE_A.y, TRACE_A.z = a.x, a.y, a.z + EYE_Z
    TRACE_B.x, TRACE_B.y, TRACE_B.z = b.x, b.y, b.z + EYE_Z
    local ok, clear = pcall(core.graphics.trace_line, TRACE_A, TRACE_B, flags)
    return ok and clear == true
end

local function walk_open(a, b)
    if FLAG_COLLISION == nil then return true end
    return trace(a, b, FLAG_COLLISION) == true
end

local function los_open(a, b)
    if FLAG_LOS == nil then return true end
    return trace(a, b, FLAG_LOS) == true
end

-- ============================================================================
-- BLACKLIST ZONES
-- ============================================================================
local function prune_zones(t, force)
    if not force and (t - zones_pruned_t) < ZONE_PRUNE_EVERY then return end
    zones_pruned_t = t
    local n, w = #zones, 0
    for i = 1, n do
        local z = zones[i]
        if (t - z.t) < ZONE_TTL then
            w = w + 1
            zones[w] = z
        end
    end
    for i = w + 1, n do zones[i] = nil end
end

--- Is (x, y) inside any blacklist zone? Squared distances, no allocation.
local function blocked_xy(x, y)
    for i = 1, #zones do
        local z = zones[i]
        local dx, dy = z.x - x, z.y - y
        if dx * dx + dy * dy <= z.r * z.r then return true end
    end
    return false
end

function movement.blacklist_area(pos, radius, why)
    local x, y, z = xyz(pos)
    if not x then return false end
    radius = tonumber(radius) or ZONE_RADIUS
    if radius < 6 then radius = 6 elseif radius > 30 then radius = 30 end
    local t = izi.now()
    prune_zones(t, true)
    for i = 1, #zones do
        local zn = zones[i]
        if dist2(zn.x, zn.y, x, y) < ZONE_MERGE then
            zn.x, zn.y, zn.z, zn.t = x, y, z, t
            if radius > zn.r then zn.r = radius end
            zn.hits = zn.hits + 1
            return true
        end
    end
    if #zones >= MAX_ZONES then table.remove(zones, 1) end
    zones[#zones + 1] = { x = x, y = y, z = z, r = radius, t = t, hits = 1, why = why }
    log(string.format("Blacklist area (%.1f, %.1f, %.1f) r=%.0f%s", x, y, z, radius,
        why and (" - " .. tostring(why)) or ""))
    return true
end

function movement.is_blocked(pos)
    local x, y = xyz(pos)
    if not x then return false end
    prune_zones(izi.now())
    return blocked_xy(x, y)
end

function movement.zone_count()
    prune_zones(izi.now(), true)
    return #zones
end

-- ============================================================================
-- NUMBER-ONLY GEOMETRY   (results go into pool slots)
-- ============================================================================
--- Point `travel` yards from f toward g (or g itself when closer), ground-snapped.
local function extend(slot, f, g, travel)
    local dx, dy = g.x - f.x, g.y - f.y
    local d = sqrt(dx * dx + dy * dy)
    if d <= travel or d < 0.001 then
        return pt(slot, g.x, g.y, g.z)
    end
    local k = travel / d
    local x, y = f.x + dx * k, f.y + dy * k
    return pt(slot, x, y, ground_z(x, y, f.z + (g.z - f.z) * k))
end

--- p rotated `degrees` around o, ground-snapped.
local function rotate(slot, p, o, degrees)
    local a = rad(degrees)
    local c, s = cos(a), sin(a)
    local dx, dy = p.x - o.x, p.y - o.y
    local x, y = o.x + dx * c - dy * s, o.y + dx * s + dy * c
    return pt(slot, x, y, ground_z(x, y, p.z))
end

--- Point `yards` to the left/right of d, perpendicular to the f->d direction.
local function sidestep(slot, f, d, left, yards)
    local dx, dy = d.x - f.x, d.y - f.y
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    local nx, ny = -dy / len, dx / len          -- left normal
    if not left then nx, ny = -nx, -ny end
    local x, y = d.x + nx * yards, d.y + ny * yards
    return pt(slot, x, y, ground_z(x, y, d.z))
end

-- ============================================================================
-- PATH LEASH
-- ============================================================================
--- Closest point on the leash polyline to (x, y).
--- Returns px, py, pz, dist_xy, segment_index  (or nil when there is no leash).
local function project_on_leash(x, y)
    if not leash then return nil end
    if leash_n == 1 then
        return leash[1], leash[2], leash[3], dist2(x, y, leash[1], leash[2]), 1
    end
    local best_d2, bx, by, bz, bi = 1e18, 0, 0, 0, 1
    for i = 1, leash_n - 1 do
        local o = (i - 1) * 3
        local ax, ay, az = leash[o + 1], leash[o + 2], leash[o + 3]
        local cx, cy, cz = leash[o + 4], leash[o + 5], leash[o + 6]
        local vx, vy = cx - ax, cy - ay
        local l2 = vx * vx + vy * vy
        local t = 0
        if l2 > 0.0001 then
            t = ((x - ax) * vx + (y - ay) * vy) / l2
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        local px, py = ax + vx * t, ay + vy * t
        local dx, dy = x - px, y - py
        local d2 = dx * dx + dy * dy
        if d2 < best_d2 then
            best_d2, bx, by, bz, bi = d2, px, py, az + (cz - az) * t, i
        end
    end
    return bx, by, bz, sqrt(best_d2), bi
end

--- Player's projection onto the leash, computed at most once per pulse.
local function here_on_leash()
    if lc_tick == pulse_tick then
        if lc_d == nil then return nil end
        return lc_x, lc_y, lc_z, lc_d, lc_i
    end
    lc_tick = pulse_tick
    local x, y = here_xyz()
    if not x or not leash then
        lc_d = nil
        return nil
    end
    lc_x, lc_y, lc_z, lc_d, lc_i = project_on_leash(x, y)
    return lc_x, lc_y, lc_z, lc_d, lc_i
end

local function path_offset_xy(x, y)
    if not leash or not x then return nil end
    local _, _, _, d = project_on_leash(x, y)
    return d
end

--- May we move from `from` to `dest` under the leash? Inside the leash is
--- always fine; outside is fine only when the move brings us closer to it.
local function leash_allows(from, dest)
    if not leash_armed or not leash then return true end
    local _, _, _, dd = project_on_leash(dest.x, dest.y)
    if dd <= PATH_LEASH then return true end
    local _, _, _, fd = project_on_leash(from.x, from.y)
    return dd < (fd - 0.15)
end

local function path_needs_rejoin()
    if not leash_armed or not leash or rest_lock then return false end
    local _, _, _, d = here_on_leash()
    return d ~= nil and d > PATH_LEASH
end

-- ============================================================================
-- CANDIDATE STEERING
-- ============================================================================
--- Is `c` an acceptable hop from `from` (optionally with LoS to `goal`)?
local function cand_ok(from, c, goal, need_los)
    if blocked_xy(c.x, c.y) then return false end
    if not leash_allows(from, c) then return false end
    if not walk_open(from, c) then return false end
    if need_los and goal and not los_open(c, goal) then return false end
    return true
end

--- Find a clear hop of up to `travel` yards from `from` toward `goal`.
--- Returns a pool point (P_PRIMARY / P_ALT / P_STEP / P_MID) or nil.
--- Obstacle memory: the side that last worked is tried first, and each
--- blocked pass escalates the search (wider angles, longer hops - see
--- ESCALATE) so the player walks along and then around the obstacle
--- instead of nibbling at it. The blocked straight hop is returned only when
--- no alternative could be evaluated at all and require_clear is false.
local function pick_steer(from, goal, travel, need_los, require_clear)
    local primary = extend(P_PRIMARY, from, goal, travel)
    if cand_ok(from, primary, goal, need_los) then
        detour_side, block_streak = 0, 0
        return primary
    end

    -- a long hop that failed: try shorter straight hops before turning
    if travel > STEER_HOP then
        local shorter = extend(P_MID, from, goal, travel * 0.5)
        if cand_ok(from, shorter, goal, need_los) then
            detour_side, block_streak = 0, 0
            return shorter
        end
        primary = extend(P_PRIMARY, from, goal, STEER_HOP)
        if cand_ok(from, primary, goal, need_los) then
            detour_side, block_streak = 0, 0
            return primary
        end
        travel = STEER_HOP
    end

    local evaluated = 0
    if traces_used < TRACE_BUDGET then
        local level = ESCALATE[block_streak >= 3 and 3 or (block_streak >= 2 and 2 or 1)]
        local angles, seed = level.angles, primary
        if level.hop and travel < level.hop then
            seed = extend(P_MID, from, goal, level.hop)
        end
        -- two passes: the remembered side first, then the other side
        for pass = 1, 2 do
            for i = 1, #angles do
                local deg = angles[i]
                local side = deg > 0 and 1 or -1
                local first = (detour_side == 0) or (side == detour_side)
                if (pass == 1) == first then
                    local alt = rotate(P_ALT, seed, from, deg)
                    evaluated = evaluated + 1
                    if cand_ok(from, alt, goal, need_los) then
                        detour_side = side
                        return alt
                    end
                end
            end
        end
        for i = 1, #SIDESTEP_YARDS do
            local yards = SIDESTEP_YARDS[i]
            local left_first = detour_side >= 0
            for k = 1, 2 do
                local left = (k == 1) == left_first
                local c = sidestep(P_STEP, from, primary, left, yards)
                evaluated = evaluated + 1
                if c and cand_ok(from, c, goal, need_los) then
                    detour_side = left and 1 or -1
                    return c
                end
            end
        end
        local hop = travel * 0.55
        if hop >= MIN_NAV then
            local mid = extend(P_MID, from, goal, hop)
            evaluated = evaluated + 1
            if cand_ok(from, mid, goal, need_los) then return mid end
        end
    end
    block_streak = block_streak + 1
    if require_clear then return nil end
    if evaluated == 0 then
        return primary                         -- nothing could be evaluated: let the walker try
    end
    return nil                                 -- evaluated and blocked: caller backs off
end

--- Hop that brings the player back inside the leash, or nil.
local function rejoin_hop(from)
    local ox, oy, oz, d = here_on_leash()
    if not ox or d <= (PATH_LEASH - 0.5) then return nil end
    local on = pt(P_ON, ox, oy, oz)
    local travel = d
    if travel > STEER_HOP then travel = STEER_HOP end
    if travel < MIN_NAV then travel = MIN_NAV end
    local hop = pick_steer(from, on, travel, false, true)
    if hop then return hop end
    if d <= (PATH_LEASH + STEER_HOP) and walk_open(from, on) then return on end
    hop = pick_steer(from, on, travel, false, false)
    if hop and leash_allows(from, hop) then return hop end
    return nil
end

--- A point `hold` yards from goal with LoS to it (orbit search), or nil.
local function orbit_for_los(from, goal, hold)
    local d = dist2(from.x, from.y, goal.x, goal.y)
    if d < 1 then return nil end
    hold = tonumber(hold) or 8
    if hold < 5 then hold = 5 end
    local travel = d - hold
    if travel < MIN_NAV then
        travel = d * 0.35
        if travel < MIN_NAV then travel = MIN_NAV end
    end
    local seed = extend(P_SEED, from, goal, travel)
    if cand_ok(from, seed, goal, true) then return seed end
    for i = 1, #ORBIT_DEGREES do
        local alt = rotate(P_ORBIT, seed, goal, ORBIT_DEGREES[i])
        if cand_ok(from, alt, goal, true) then return alt end
    end
    return nil
end

--- Patrol steering toward dest. Returns a pool point or nil.
local function steer(from, dest, max_hop, hold, need_los, require_clear)
    local remain = dist2(from.x, from.y, dest.x, dest.y)
    hold = hold or 0
    if remain <= hold + 0.5 then
        if need_los and not los_open(from, dest) then
            local orbit = orbit_for_los(from, dest, hold > 0 and hold or 8)
            if orbit then return orbit end
            if require_clear then return nil end
            return dest
        end
        if require_clear and not walk_open(from, dest) then return nil end
        return dest
    end
    local travel = remain - hold
    if travel < MIN_NAV then travel = remain end
    if travel > max_hop then travel = max_hop end
    local picked = pick_steer(from, dest, travel, need_los, require_clear)
    if picked then return picked end
    if need_los then return orbit_for_los(from, dest, hold > 0 and hold or 8) end
    return nil        -- every hop evaluated was blocked: caller backs off and escalates
end

--- Combat approach: get within `hold` yards of goal with LoS. Pool point or nil.
local function approach_unit(from, goal, hold)
    local remain = dist2(from.x, from.y, goal.x, goal.y)
    hold = tonumber(hold) or 20
    if hold < 5 then hold = 5 end
    local closing = remain <= (hold + STEER_HOP + 4)
    if remain <= hold then
        if los_open(from, goal) then return nil end
        return orbit_for_los(from, goal, hold)
    end
    local travel = remain - hold
    if travel < MIN_NAV then
        travel = remain * 0.4
        if travel < MIN_NAV then travel = MIN_NAV end
    end
    if travel > STEER_HOP then travel = STEER_HOP end
    local picked = pick_steer(from, goal, travel, closing, true)
    if picked then return picked end
    picked = orbit_for_los(from, goal, hold)
    if picked then return picked end
    local seed = extend(P_SEED, from, goal, travel)
    for i = 1, #COMBAT_OFFSET do
        local c = rotate(P_ALT, seed, from, COMBAT_OFFSET[i])
        if cand_ok(from, c, goal, closing) then return c end
        c = rotate(P_ALT, seed, goal, COMBAT_OFFSET[i])
        if cand_ok(from, c, goal, closing) then return c end
    end
    for i = 1, #SIDESTEP_YARDS do
        local c = sidestep(P_STEP, from, seed, true, SIDESTEP_YARDS[i])
        if c and cand_ok(from, c, goal, closing) then return c end
        c = sidestep(P_STEP, from, seed, false, SIDESTEP_YARDS[i])
        if c and cand_ok(from, c, goal, closing) then return c end
    end
    return nil
end

-- ============================================================================
-- WALKER
-- ============================================================================
local function ensure_walker()
    if walker_ready then return walker ~= nil end
    if not walker then return false end
    pcall(walker.set_use_look_at, walker, true)
    pcall(walker.set_smoothing_enabled, walker, false)
    pcall(walker.set_threshold, walker, 2.0)
    pcall(walker.set_final_threshold, walker, 1.0)
    pcall(walker.set_look_distance, walker, 8)
    pcall(walker.set_turn_speed, walker, 0.18)
    pcall(walker.set_debug, walker, false)
    walker_ready = true
    return true
end

ensure_walker()

local function walker_halt()
    pcall(walker.stop, walker)
    pcall(walker.clear_navigation, walker)
    walker_moving = false
    path_src, path_pts = nil, nil
end

local function walker_pause()
    pcall(walker.pause, walker)
end

--- Sample walker:is_moving() (once per pulse; callers between pulses reuse it).
local function sample_walker()
    local ok, m = pcall(walker.is_moving, walker)
    walker_moving = ok and m == true
    return walker_moving
end

local function nav_gap_ok()
    local t = izi.now()
    local last = last_move_t
    if last_stop_t > last then last = last_stop_t end
    return (t - last) >= (engage and CHASE_GAP or MOVE_GAP)
end

local function set_quiet(seconds)
    local until_t = izi.now() + (seconds or QUIET_STOP)
    if until_t > quiet_until then quiet_until = until_t end
end

local function clear_dest()
    pending, has_dest = false, false
end

--- Stop Simple Movement. Returns false when nothing was moving
--- (so callers that call stop() every frame do not spam or extend quiet).
local function native_stop()
    local was_active = pending or has_dest or walker_moving
    clear_dest()
    if not was_active then return false end
    local t = izi.now()
    last_stop_t, last_move_t = t, t
    walker_halt()
    kite_active = false
    if not rest_lock and not cc_lock then
        set_owner(OWNER_NONE, "stop")
    end
    return true
end

local function reason_offmesh(reason)
    if type(reason) ~= "string" then return false end
    local r = reason:lower()
    for i = 1, #OFFMESH_WORDS do
        if r:find(OFFMESH_WORDS[i], 1, true) then return true end
    end
    return false
end

local function mark_fail(reason, at)
    local t = izi.now()
    last_fail.reason, last_fail.t, last_fail.valid = tostring(reason), t, true
    last_fail.offmesh = reason_offmesh(last_fail.reason)
    if last_fail.offmesh then
        fail_cooldown_until = t + FAIL_COOLDOWN
        if not engage then set_quiet(QUIET_422) end
        local x, y, z
        if at then x, y, z = xyz(at) end
        if not x and has_dest then x, y, z = dest_x, dest_y, dest_z end
        if not x then x, y, z = here_xyz() end
        if x then movement.blacklist_area(pt(P_TMP, x, y, z), ZONE_RADIUS, last_fail.reason) end
    end
end

local function same_dest(x, y)
    return has_dest and dist2(dest_x, dest_y, x, y) < SAME_DEST
end

local function begin_issue(x, y, z)
    if not same_dest(x, y) then detour_side, block_streak = 0, 0 end
    pending, has_dest = true, true
    dest_x, dest_y, dest_z = x, y, z
    last_move_t = izi.now()
    last_fail.valid = false
    stuck_x, stuck_y = here_xyz()
    stuck_since = last_move_t
end

--- Issue a single-point move. Allocates the one vec3 the walker keeps.
local function issue_move(p, why)
    if cc_lock or rest_lock then
        return false
    end
    begin_issue(p.x, p.y, p.z)
    local ok, issued = pcall(walker.move_to_position, walker, to_vec3(p))
    if not ok or issued ~= true then
        clear_dest()
        mark_fail("blocked", p)
        core.log_warning(TAG .. " " .. why .. " failed: blocked")
        return false
    end
    walker_moving = true
    set_owner(OWNER_SIMPLE, why or "move")
    if debug_on then dlog(string.format("%s -> (%.1f, %.1f, %.1f)", why, p.x, p.y, p.z)) end
    return true
end

-- ============================================================================
-- STUCK WATCH
-- ============================================================================
local function watch_stuck(t)
    local x, y = here_xyz()
    if not pending or rest_lock or not x then
        stuck_x, stuck_y, stuck_since = x, y, t
        return
    end
    if not stuck_x or dist2(x, y, stuck_x, stuck_y) >= STUCK_MOVE then
        stuck_x, stuck_y, stuck_since = x, y, t
        return
    end
    if (t - stuck_since) < STUCK_GRACE then return end
    stuck_grace_until = t + STUCK_GRACE
    set_quiet(1.5)
    local had, dx, dy, dz = has_dest, dest_x, dest_y, dest_z
    clear_dest()
    walker_halt()
    if had and dist2(x, y, dx, dy) > 16 then
        movement.blacklist_area(pt(P_TMP, dx, dy, dz), STUCK_ZONE_RADIUS, "stuck")
    end
    dlog("stuck - move cancelled")
    stuck_x, stuck_y, stuck_since = x, y, t
end

-- ============================================================================
-- PER-FRAME
-- ============================================================================
function movement.pulse()
    pulse_tick = pulse_tick + 1
    traces_used = 0
    ensure_walker()
    local t = izi.now()
    local me = izi.me()
    local locked, why = movement_restricted(me)
    if locked then
        if not cc_lock then
            cc_lock = true
            walker_pause()
            set_owner(OWNER_RESTRICTED, why)
        end
    elseif cc_lock then
        cc_lock = false
        if rest_lock then
            set_owner(OWNER_RESTRICTED, "rest")
        elseif engage then
            set_owner(OWNER_COMBAT, "cc_end")
        else
            pcall(walker.resume, walker)
            set_owner(OWNER_SIMPLE, "cc_end")
        end
    end

    -- process() must run every frame while Simple Movement has a path, including pause.
    local ok, reached = pcall(walker.process, walker)
    if ok and reached == true then
        clear_dest()
        kite_active = false
    end
    sample_walker()
    if pending and not walker_moving and (t - last_move_t) >= 0.3 then
        clear_dest()
    end
    watch_stuck(t)
    if leash and not leash_armed and not rest_lock then
        local _, _, _, d = here_on_leash()
        if d and d <= PATH_LEASH then leash_armed = true end
    end
    prune_zones(t)
end

function movement.on_render()
    pcall(movement_handler.on_render, movement_handler)
end

function movement.set_debug(on)
    debug_on = on == true
end

-- ============================================================================
-- PATH LEASH API
-- ============================================================================
function movement.set_path_leash(waypoints)
    if type(waypoints) ~= "table" or #waypoints < 1 then
        leash, leash_n, leash_src, leash_armed = nil, 0, nil, false
        return
    end
    if waypoints ~= leash_src then                     -- flatten once per new list
        local flat, n = {}, 0
        for i = 1, #waypoints do
            local x, y, z = xyz(waypoints[i])
            if x then
                flat[n * 3 + 1], flat[n * 3 + 2], flat[n * 3 + 3] = x, y, z
                n = n + 1
            end
        end
        if n == 0 then
            leash, leash_n, leash_src, leash_armed = nil, 0, nil, false
            return
        end
        leash, leash_n, leash_src = flat, n, waypoints
    end
    lc_tick = -1
    local _, _, _, d = here_on_leash()
    leash_armed = d ~= nil and d <= PATH_LEASH
end

function movement.clear_path_leash()
    leash, leash_n, leash_src, leash_armed = nil, 0, nil, false
end

function movement.path_offset(pos)
    if pos then return path_offset_xy(xyz(pos)) end
    local _, _, _, d = here_on_leash()
    return d
end

function movement.needs_rejoin()
    if izi.now() < stuck_grace_until then return false end
    return path_needs_rejoin()
end

function movement.path_anchor_index(pos)
    if pos then
        local x, y = xyz(pos)
        if not x or not leash then return nil end
        local _, _, _, _, i = project_on_leash(x, y)
        return i
    end
    local _, _, _, _, i = here_on_leash()
    return i
end

-- ============================================================================
-- MODE / STATE API
-- ============================================================================
function movement.set_resting(on)
    if on == true then
        if not rest_lock then
            rest_lock, fight_stopped = true, false
            kite_active = false
            set_quiet(QUIET_STOP)
            walker_pause()
            set_owner(OWNER_RESTRICTED, "rest")
        end
        return
    end
    rest_lock = false
    if not cc_lock then
        if engage then
            set_owner(OWNER_COMBAT, "rest_end")
        else
            pcall(walker.resume, walker)
            set_owner(OWNER_SIMPLE, "rest_end")
        end
    end
end

function movement.is_resting() return rest_lock end

function movement.last_fail_offmesh()
    return last_fail.valid and last_fail.offmesh
end

function movement.last_fail_reason()
    if last_fail.valid then return last_fail.reason end
    return nil
end

function movement.clear_fail() last_fail.valid = false end

function movement.is_quiet()
    local t = izi.now()
    return t < quiet_until or t < stuck_grace_until
end

function movement.in_engage() return engage end

function movement.patrol_blocked() return engage end

function movement.patrol_ready()
    return not engage and not movement.is_quiet()
end

function movement.begin_engage()
    if engage then return end
    engage = true
    last_fail.valid = false
    kite_active = false
    set_owner(OWNER_COMBAT, "engage")
end

function movement.end_engage()
    if not engage then return end
    engage, fight_stopped = false, false
    kite_active = false
    if not rest_lock and not cc_lock then
        local ok, st = pcall(walker.get_state, walker)
        if ok and type(st) == "table" and st.state == "paused" then
            pcall(walker.resume, walker)
            set_owner(OWNER_SIMPLE, "end_engage")
        else
            walker_halt()
            clear_dest()
            set_owner(OWNER_NONE, "end_engage")
        end
    end
    set_quiet(QUIET_STOP)
end

function movement.stop()
    if native_stop() then set_quiet(QUIET_STOP) end
end

function movement.stop_if_moving()
    if movement.is_moving() then
        movement.stop()
        return true
    end
    return false
end

function movement.is_moving()
    if rest_lock then return false end
    if walker_moving then return true end
    return pending and (izi.now() - last_move_t) < INFLIGHT_TIMEOUT
end

-- Kept so older callers do not error. Sentinel is no longer used.
function movement.sentinel_active()
    return false
end

-- ============================================================================
-- PATROL MOVES
-- ============================================================================
--- Cheap gates shared by every patrol move. Returns true when a new move may
--- be issued now, or false plus the value the caller should return instead.
local function may_issue(x, y, z)
    if rest_lock or engage or cc_lock then return false, false end
    if movement.is_moving() then return false, true end          -- already going
    local t = izi.now()
    if t < quiet_until or t < stuck_grace_until or t < steer_backoff_until then
        return false, same_dest(x, y)
    end
    if not nav_gap_ok() then return false, same_dest(x, y) end
    local hx, hy, hz = here_xyz()
    if not hx then return false, false end
    if dist3(hx, hy, hz, x, y, z) < MIN_NAV then return false, false end
    if last_fail.valid and last_fail.offmesh and t < fail_cooldown_until and same_dest(x, y) then
        return false, false
    end
    if not ensure_walker() then return false, false end
    return true
end

local function navigate(dest, prefer_direct)
    local x, y, z = xyz(dest)
    if not x then return false end
    local go, ret = may_issue(x, y, z)
    if not go then return ret end
    if blocked_xy(x, y) then
        mark_fail("blacklisted", dest)
        return false
    end

    local hx, hy, hz = here_xyz()
    local here = pt(P_HERE, hx, hy, hz)
    z = ground_z(x, y, z)
    local goal = pt(P_DEST, x, y, z)

    local target
    if path_needs_rejoin() then
        target = rejoin_hop(here)
    else
        target = steer(here, goal, PATROL_HOP)
        if target and not leash_allows(here, target) then
            target = rejoin_hop(here)
        end
    end
    if not target then
        steer_backoff_until = izi.now() + STEER_BACKOFF
        dlog("no clear hop - backing off")
        return false
    end
    if blocked_xy(target.x, target.y) then
        mark_fail("blacklisted", target)
        return false
    end
    if not prefer_direct and target ~= here and not walk_open(here, target) and path_needs_rejoin() then
        return false
    end
    return issue_move(target, "move_to")
end

function movement.move_to(dest)
    return navigate(dest, false)
end

function movement.move_direct(dest)
    return navigate(dest, true)
end

--- Follow a caller-owned list of points (vec3s or { x, y, z } arrays).
--- The list is snapped and copied once per distinct table; passing the same
--- table every frame while the walker is busy costs nothing.
function movement.follow_path(points)
    if rest_lock or cc_lock then return false end
    if type(points) ~= "table" or #points == 0 then return false end
    local lx, ly, lz = xyz(points[#points])
    if not lx then return false end
    if points == path_src and movement.is_moving() then return true end

    local go, ret = may_issue(lx, ly, lz)
    if not go then return ret end

    local hx, hy, hz = here_xyz()
    local here = pt(P_HERE, hx, hy, hz)
    if path_needs_rejoin() then
        local hop = rejoin_hop(here)
        if not hop then
            steer_backoff_until = izi.now() + STEER_BACKOFF
            return false
        end
        return issue_move(hop, "rejoin")
    end

    -- snap + filter once per list
    if points ~= path_src or not path_pts then
        local pts = {}
        for i = 1, #points do
            local x, y, z = xyz(points[i])
            if x and not blocked_xy(x, y) then
                pts[#pts + 1] = vec3.new(x, y, ground_z(x, y, z))
            end
        end
        path_src, path_pts = points, pts
    end
    local pts = path_pts
    if #pts == 0 then return false end
    if #pts == 1 then return navigate(pts[1], true) end
    if not walk_open(here, pts[1]) then
        return navigate(pts[1], false)              -- steer to the first point
    end
    local last = pts[#pts]
    begin_issue(last.x, last.y, last.z)
    local ok, issued = pcall(walker.navigate, walker, pts, false, true)
    if not ok or issued ~= true then
        clear_dest()
        mark_fail("blocked", last)
        core.log_warning(TAG .. " follow_path failed: blocked")
        return false
    end
    walker_moving = true
    set_owner(OWNER_SIMPLE, "follow_path")
    return true
end

function movement.rejoin_path()
    if rest_lock or izi.now() < stuck_grace_until then return false end
    local hx, hy, hz = here_xyz()
    if not hx then return false end
    local hop = rejoin_hop(pt(P_HERE, hx, hy, hz))
    if not hop then return false end
    return navigate(hop, walk_open(POOL[P_HERE], hop))
end

function movement.arrived(dest, yards)
    local hx, hy, hz = here_xyz()
    local x, y, z = xyz(dest)
    if not hx or not x then return false end
    return dist3(hx, hy, hz, x, y, z) <= (yards or ARRIVE)
end

function movement.line_blocked(from, dest)
    local fx, fy, fz = xyz(from)
    local tx, ty, tz = xyz(dest)
    if not fx or not tx then return false end
    return not walk_open(pt(P_HERE, fx, fy, fz), pt(P_DEST, tx, ty, tz))
end

function movement.can_reach(from, dest)
    local fx, fy, fz = xyz(from)
    local tx, ty, tz = xyz(dest)
    if not fx or not tx then return false end
    if blocked_xy(tx, ty) then return false end
    local f, d = pt(P_HERE, fx, fy, fz), pt(P_DEST, tx, ty, tz)
    if walk_open(f, d) then return true end
    local hop = dist2(fx, fy, tx, ty)
    if hop > STEER_HOP then hop = STEER_HOP end
    if hop < MIN_NAV then hop = MIN_NAV end
    if pick_steer(f, d, hop, false, true) then return true end
    return orbit_for_los(f, d, 8) ~= nil
end

-- ============================================================================
-- COMBAT
-- ============================================================================
function movement.in_fight_range(player, unit, yards)
    yards = tonumber(yards) or 20
    if yards < 5 then yards = 5 end
    if not player or not unit then return false, 99, false end
    local ok, range = pcall(player.distance_to, player, unit)
    if not ok or type(range) ~= "number" then return false, 99, false end

    local has_los
    ok, has_los = pcall(player.los_to, player, unit)
    has_los = ok and has_los == true
    if not has_los and type(izi.is_los) == "function" then
        ok, has_los = pcall(izi.is_los, player, unit)
        has_los = ok and has_los == true
    end
    if not has_los then
        ok, has_los = pcall(core.graphics.is_line_of_sight, player, unit)
        has_los = ok and has_los == true
    end
    if not has_los and FLAG_LOS then
        local fx, fy, fz = here_xyz()
        if not fx then
            local okp, p = pcall(player.get_position, player)
            if okp then fx, fy, fz = xyz(p) end
        end
        local okp, up = pcall(unit.get_position, unit)
        local ux, uy, uz
        if okp then ux, uy, uz = xyz(up) end
        if fx and ux then
            local okh, ph = pcall(player.get_height, player)
            local okh2, uh = pcall(unit.get_height, unit)
            ph = (okh and type(ph) == "number" and ph > 0) and ph * 0.8 or EYE_Z
            uh = (okh2 and type(uh) == "number" and uh > 0) and uh * 0.8 or EYE_Z
            -- trace() adds EYE_Z itself, so hand it the height minus that
            has_los = trace(pt(P_HERE, fx, fy, fz + ph - EYE_Z), pt(P_DEST, ux, uy, uz + uh - EYE_Z), FLAG_LOS) == true
        end
    end
    if range <= 3 then has_los = true end
    return (range <= yards and has_los), range, has_los
end

--- Issue a combat hop. Returns true when moving (now or already), false when
--- no hop could be issued.
local function chase_issue(p)
    if rest_lock or cc_lock then return false end
    if not nav_gap_ok() then return true end
    local hx, hy, hz = here_xyz()
    if not hx then return false end
    local here = pt(P_HERE, hx, hy, hz)
    local target = pt(P_TMP, p.x, p.y, p.z)
    if path_needs_rejoin() or not leash_allows(here, target) then
        target = rejoin_hop(here)
        if not target then return false end
    end
    if not walk_open(here, target) then
        local hop = dist2(hx, hy, target.x, target.y)
        if hop > STEER_HOP then hop = STEER_HOP end
        target = pick_steer(here, target, hop, false, true)
        if not target or not walk_open(here, target) then return false end
    end
    if not ensure_walker() then return false end
    if dist3(hx, hy, hz, target.x, target.y, target.z) < MIN_NAV then return false end
    if same_dest(target.x, target.y) and (pending or walker_moving) then
        return true
    end
    return issue_move(target, "chase")
end

local function hold_in_range(player, unit)
    movement.begin_engage()
    chase_fail_key, chase_fail_t = nil, 0
    if not fight_stopped then
        fight_stopped = true
        walker_pause()
        clear_dest()
        pending, walker_moving = false, false
        set_owner(OWNER_COMBAT, "in_range")
    end
    movement.face_combat(unit)
end

local function should_kite(player, unit, range)
    if not player or not unit then
        return false
    end
    local rooted = flag_true(unit, unit.is_rooted) or flag_true(unit, unit.is_stunned)
    if not rooted then
        kite_active = false
        return false
    end
    local melee = false
    local okm, in_melee = pcall(unit.is_in_melee_range, unit, KITE_ENTER)
    if okm and in_melee == true then
        melee = true
    elseif type(range) == "number" and range <= KITE_ENTER then
        melee = true
    else
        local okp, pred = pcall(unit.predict_distance, unit, 0.5, player)
        if okp and type(pred) == "number" and pred <= KITE_ENTER then
            melee = true
        end
    end
    if kite_active then
        if type(range) == "number" and range >= KITE_EXIT then
            kite_active = false
            return false
        end
        return true
    end
    if melee then
        kite_active = true
        return true
    end
    return false
end

local function kite_away(player, unit, here, goal)
    local dest = extend(P_TMP, goal, here, KITE_EXIT + 2.0)
    if not dest or blocked_xy(dest.x, dest.y) then
        return false
    end
    if FLAG_COLLISION ~= nil and walk_open(here, dest) ~= true then
        return false
    end
    fight_stopped = false
    return issue_move(dest, "kite")
end

function movement.chase_unit(player, unit, yards)
    if not player or not unit or rest_lock or cc_lock then return false end
    local ok, valid = pcall(unit.is_valid, unit)
    if not ok or valid ~= true then return false end
    if flag_true(unit, unit.is_dead) then return false end
    yards = tonumber(yards) or 20
    if yards < 5 then yards = 5 end

    local ready, range, has_los = movement.in_fight_range(player, unit, yards)
    if ready then
        if should_kite(player, unit, range) then
            movement.begin_engage()
            local okp, upos = pcall(unit.get_position, unit)
            local ux, uy, uz
            if okp then ux, uy, uz = xyz(upos) end
            local hx, hy, hz = here_xyz()
            if not hx then
                local okh, hp = pcall(player.get_position, player)
                if okh then hx, hy, hz = xyz(hp) end
            end
            if ux and hx then
                local here = pt(P_HERE, hx, hy, hz)
                local goal = pt(P_DEST, ux, uy, ground_z(ux, uy, uz))
                if kite_away(player, unit, here, goal) then
                    chase_fail_key, chase_fail_t = nil, 0
                    return false
                end
            end
        end
        hold_in_range(player, unit)
        return true
    end
    fight_stopped = false
    kite_active = false

    local in_combat = combat_event
    local okc, cbt = pcall(player.is_in_combat, player)
    if okc and cbt == true then
        in_combat = true
    end

    -- Far OOC pull: Simple Movement walk toward a stand-off point, not combat micro-move.
    if not engage and not in_combat and type(range) == "number" and range > 30 then
        local okp, upos = pcall(unit.get_position, unit)
        local ux, uy, uz
        if okp then ux, uy, uz = xyz(upos) end
        local hx, hy, hz = here_xyz()
        if ux and hx then
            local here, goal = pt(P_HERE, hx, hy, hz), pt(P_DEST, ux, uy, ground_z(ux, uy, uz))
            local pull = yards - 5
            if pull < MIN_NAV then pull = yards end
            local dx, dy = hx - ux, hy - uy
            local len = sqrt(dx * dx + dy * dy)
            if len > pull then
                local s = pull / len
                local dest = pt(P_TMP, ux + dx * s, uy + dy * s, ground_z(ux + dx * s, uy + dy * s, uz))
                if navigate(dest, walk_open(here, dest)) then
                    chase_fail_key, chase_fail_t = nil, 0
                    return false
                end
            end
        end
    end

    movement.begin_engage()
    local okp, upos = pcall(unit.get_position, unit)
    local ux, uy, uz
    if okp then ux, uy, uz = xyz(upos) end
    if not ux then return false end
    local hx, hy, hz = here_xyz()
    if not hx then
        local okh, hp = pcall(player.get_position, player)
        if okh then hx, hy, hz = xyz(hp) end
    end
    if not hx then return false end
    local here, goal = pt(P_HERE, hx, hy, hz), pt(P_DEST, ux, uy, ground_z(ux, uy, uz))

    local t = izi.now()
    local dest
    if nav_gap_ok() and t >= steer_backoff_until then
        dest = approach_unit(here, goal, yards)
        if not dest and not has_los then dest = orbit_for_los(here, goal, yards) end
        if not dest then steer_backoff_until = t + STEER_BACKOFF end
    end
    local issued = dest ~= nil and chase_issue(dest)
    if issued or not nav_gap_ok() then
        chase_fail_key, chase_fail_t = nil, 0
        return false
    end

    local okg, guid = pcall(unit.get_guid, unit)
    local key = (okg and guid ~= nil) and guid or "?"
    if chase_fail_key ~= key then
        chase_fail_key, chase_fail_t = key, t
    elseif (t - chase_fail_t) >= CHASE_GIVE_UP then
        if type(state.mark_unreachable) == "function" then state.mark_unreachable(guid) end
        chase_fail_key, chase_fail_t = nil, 0
        log("Blacklist unreachable mob after 10s")
    end
    return false
end

function movement.face_combat(target)
    if not target then return end
    local ok, valid = pcall(target.is_valid, target)
    if not ok or valid ~= true then return end
    local t = izi.now()
    if t - last_face_t < 0.35 then return end
    last_face_t = t
    pcall(movement_handler.look_at_target, movement_handler, 0.8, 0, target)
    local okp, pos = pcall(target.get_position, target)
    if okp and pos then pcall(core.input.look_at, pos) end
end

-- ============================================================================
-- CAST / CHANNEL LOCKS
-- ============================================================================
local function clamp_sec(value, fallback)
    local n = tonumber(value)
    if type(n) ~= "number" or n ~= n or n <= 0 then return fallback end
    if n > 20 then n = n / 1000 end            -- milliseconds were passed
    if n < 0.15 then n = 0.15 elseif n > 12 then n = 12 end
    return n
end

local function on_unlock_timer(gen)
    if gen == lock_gen then movement.release() end
end

local function arm_unlock(seconds)
    lock_gen = lock_gen + 1
    local gen = lock_gen
    -- one small closure per cast lock (not per frame); it captures only `gen`
    pcall(izi.after, seconds, function() on_unlock_timer(gen) end)
end

function movement.release()
    lock_gen = lock_gen + 1
    pcall(movement_handler.resume_movement, movement_handler)
    pcall(movement_handler.unlock_look_at, movement_handler)
    if not rest_lock then pcall(walker.resume, walker) end
end

local function begin_lock(sec, light, target, pos)
    walker_pause()
    if engage then
        set_owner(OWNER_COMBAT, "cast_lock")
    end
    if light then
        pcall(movement_handler.pause_movement_light, movement_handler, sec)
    else
        pcall(movement_handler.pause_movement, movement_handler, sec + 0.5)
    end
    if target then
        pcall(movement_handler.look_at_target, movement_handler, sec, 0, target)
    elseif pos then
        pcall(movement_handler.look_at_position, movement_handler, sec, 0, pos)
    end
    arm_unlock(light and sec or (sec + 0.5))
end

function movement.prepare_cast(target, duration)
    begin_lock(clamp_sec(duration, 0.5), true, target, nil)
end

function movement.prepare_channel(target, duration)
    begin_lock(clamp_sec(duration, 3.0), false, target, nil)
end

function movement.prepare_ground(pos, duration, channel)
    begin_lock(clamp_sec(duration, channel and 3.0 or 0.5), not channel, nil, pos)
end

function movement.pause_for_loot(duration)
    native_stop()
    begin_lock(clamp_sec(duration, 0.5), true, nil, nil)
end

-- ============================================================================
-- GRIND ROUTE HELPERS  (visit order is sequential; no navmesh planner)
-- ============================================================================
function movement.plan_grind_route(coords)
    return nil
end

function movement.grind_visit_order()
    return nil
end

function movement.node_reachable(pos, index)
    return true
end

pcall(izi.on_combat_start, function(ev)
    combat_event = true
end)

pcall(izi.on_combat_finish, function(ev)
    combat_event = false
end)

return movement

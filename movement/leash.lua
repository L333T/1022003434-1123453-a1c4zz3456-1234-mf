-- ============================================================================
-- Master Farmer - Grindbot
-- movement/leash.lua - path leash (corridor around a saved route)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- The leash is a flat number array { x1, y1, z1, x2, ... } flattened once per
-- distinct waypoint list. Moving outside the corridor is only allowed when the
-- move brings the player closer to it.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")

local PATH_LEASH = K.PATH_LEASH

local xyz, dist2, here_xyz = U.xyz, U.dist2, U.here_xyz

local sqrt = math.sqrt

local L = {}

-- ============================================================================
-- INTERNALS
-- ============================================================================
--- Closest point on the leash polyline to (x, y).
--- Returns px, py, pz, dist_xy, segment_index  (or nil when there is no leash).
function L.project(x, y)
    local leash = R.leash
    if not leash then return nil end
    if R.leash_n == 1 then
        return leash[1], leash[2], leash[3], dist2(x, y, leash[1], leash[2]), 1
    end
    local best_d2, bx, by, bz, bi = 1e18, 0, 0, 0, 1
    for i = 1, R.leash_n - 1 do
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
function L.here_on_leash()
    if R.lc_tick == R.pulse_tick then
        if R.lc_d == nil then return nil end
        return R.lc_x, R.lc_y, R.lc_z, R.lc_d, R.lc_i
    end
    R.lc_tick = R.pulse_tick
    local x, y = here_xyz()
    if not x or not R.leash then
        R.lc_d = nil
        return nil
    end
    R.lc_x, R.lc_y, R.lc_z, R.lc_d, R.lc_i = L.project(x, y)
    return R.lc_x, R.lc_y, R.lc_z, R.lc_d, R.lc_i
end

function L.offset_xy(x, y)
    if not R.leash or not x then return nil end
    local _, _, _, d = L.project(x, y)
    return d
end

--- May we move from `from` to `dest` under the leash? Inside the leash is
--- always fine; outside is fine only when the move brings us closer to it.
function L.allows(from, dest)
    if not R.leash_armed or not R.leash then return true end
    local _, _, _, dd = L.project(dest.x, dest.y)
    if dd <= PATH_LEASH then return true end
    local _, _, _, fd = L.project(from.x, from.y)
    return dd < (fd - 0.15)
end

function L.needs_rejoin()
    if R.sn_active or R.sn_leash_hold then return false end   -- Sentinel may leave the polyline
    if not R.leash_armed or not R.leash or R.rest_lock then return false end
    local _, _, _, d = L.here_on_leash()
    return d ~= nil and d > PATH_LEASH
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
function L.set_path_leash(waypoints)
    if type(waypoints) ~= "table" or #waypoints < 1 then
        R.leash, R.leash_n, R.leash_src, R.leash_armed = nil, 0, nil, false
        return
    end
    if waypoints ~= R.leash_src then                   -- flatten once per new list
        local flat, n = {}, 0
        for i = 1, #waypoints do
            local x, y, z = xyz(waypoints[i])
            if x then
                flat[n * 3 + 1], flat[n * 3 + 2], flat[n * 3 + 3] = x, y, z
                n = n + 1
            end
        end
        if n == 0 then
            R.leash, R.leash_n, R.leash_src, R.leash_armed = nil, 0, nil, false
            return
        end
        R.leash, R.leash_n, R.leash_src = flat, n, waypoints
    end
    R.lc_tick = -1
    local _, _, _, d = L.here_on_leash()
    R.leash_armed = d ~= nil and d <= PATH_LEASH
end

function L.clear_path_leash()
    R.leash, R.leash_n, R.leash_src, R.leash_armed = nil, 0, nil, false
end

function L.path_offset(pos)
    if pos then return L.offset_xy(xyz(pos)) end
    local _, _, _, d = L.here_on_leash()
    return d
end

function L.public_needs_rejoin()
    if izi.now() < R.stuck_grace_until then return false end
    return L.needs_rejoin()
end

function L.path_anchor_index(pos)
    if pos then
        local x, y = xyz(pos)
        if not x or not R.leash then return nil end
        local _, _, _, _, i = L.project(x, y)
        return i
    end
    local _, _, _, _, i = L.here_on_leash()
    return i
end

return L

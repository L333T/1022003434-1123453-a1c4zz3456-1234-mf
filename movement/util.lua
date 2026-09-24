-- ============================================================================
-- Master Farmer - Grindbot
-- movement/util.lua - logging, position input, distance, ground and traces
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- The bottom layer. Depends only on const + rt, so every other movement module
-- may require it without creating a cycle.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type vec3
local vec3 = require("common/geometry/vector_3")

local state = require("state")
local K     = require("movement/const")
local R     = require("movement/rt")

local TAG            = K.TAG
local LOG_REPEAT     = K.LOG_REPEAT
local EYE_Z          = K.EYE_Z
local TRACE_BUDGET   = K.TRACE_BUDGET
local FLAG_COLLISION = K.FLAG_COLLISION
local FLAG_LOS       = K.FLAG_LOS

local sqrt, abs = math.sqrt, math.abs

local U = {}

-- ============================================================================
-- LOGGING
-- ============================================================================
function U.log(msg)
    core.log(TAG .. " " .. msg)
end

--- Debug line, de-duplicated per key: the same text for the same key is not
--- reprinted inside LOG_REPEAT seconds, so a per-frame call cannot spam.
function U.dlog(key, msg)
    if not R.debug_on then return end
    local t = izi.now()
    local prev = R.log_last[key]
    if prev and prev.msg == msg and (t - prev.t) < LOG_REPEAT then return end
    R.log_last[key] = { msg = msg, t = t }
    core.log(TAG .. " [move/" .. key .. "] " .. msg)
end

-- ============================================================================
-- POSITION INPUT
-- ============================================================================
--- Read x, y, z from any position-like value without allocating:
---   vec3 / { x=, y=, z= } / { map_id=, x=, y=, z= } / array { x, y, z }.
--- Returns nil when the value is not a finite 3D position.
function U.xyz(p)
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
function U.to_pos(p)
    local x, y, z = U.xyz(p)
    if not x then return nil end
    return vec3.new(x, y, z)
end

function U.here_xyz()
    return U.xyz(state.cached_pos)
end

function U.dist3(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return sqrt(dx * dx + dy * dy + dz * dz)
end

function U.dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

function U.unit_xyz(unit)
    if not unit then return nil end
    local ok, p = pcall(unit.get_position, unit)
    if not ok then return nil end
    return U.xyz(p)
end

function U.unit_valid(unit)
    if not unit then return false end
    local ok, v = pcall(unit.is_valid, unit)
    return ok and v == true
end

function U.unit_alive(unit)
    if not unit then return false end
    local ok, d = pcall(unit.is_dead_or_ghost, unit)
    if ok and d == true then return false end
    ok, d = pcall(unit.is_dead, unit)
    if ok and d == true then return false end
    return true
end

-- ============================================================================
-- GROUND / TRACE
-- ============================================================================
--- Ground height under (x, y); falls back to hint_z when the lookup fails or
--- the terrain is more than 80 yards from the hint (wrong floor).
function U.ground_z(x, y, hint_z)
    local q = R.HEIGHT_Q
    q.x, q.y, q.z = x, y, hint_z
    local ok, hz = pcall(core.get_height_for_position, q)
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
function U.trace(a, b, flags)
    if type(flags) ~= "number" or R.traces_used >= TRACE_BUDGET then return nil end
    R.traces_used = R.traces_used + 1
    local A, B = R.TRACE_A, R.TRACE_B
    A.x, A.y, A.z = a.x, a.y, a.z + EYE_Z
    B.x, B.y, B.z = b.x, b.y, b.z + EYE_Z
    local ok, clear = pcall(core.graphics.trace_line, A, B, flags)
    return ok and clear == true
end

function U.walk_open(a, b)
    if FLAG_COLLISION == nil then return true end
    return U.trace(a, b, FLAG_COLLISION) == true
end

function U.los_open(a, b)
    if FLAG_LOS == nil then return true end
    return U.trace(a, b, FLAG_LOS) == true
end

return U

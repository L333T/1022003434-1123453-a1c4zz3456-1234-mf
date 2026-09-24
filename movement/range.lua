-- ============================================================================
-- Master Farmer - Grindbot
-- movement/range.lua - facing, range, line of sight, reachability
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Read-only questions about the world plus the one fire-and-forget command
-- (facing). Split out from combat so navigation callers can ask "can I reach
-- this?" without pulling the combat controller in.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type movement_handler
local handler = require("common/utility/movement_handler")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local Z = require("movement/zones")
local S = require("movement/steer")
local O = require("movement/own")

local EYE_Z      = K.EYE_Z
local ARRIVE     = K.ARRIVE
local MIN_NAV    = K.MIN_NAV
local STEER_HOP  = K.STEER_HOP
local FACE_GAP   = K.FACE_GAP
local FACE_LOCK  = K.FACE_LOCK
local FLAG_LOS   = K.FLAG_LOS

local pt = R.pt
local xyz, here_xyz, dist2, dist3 = U.xyz, U.here_xyz, U.dist2, U.dist3
local unit_xyz, unit_valid, trace, walk_open = U.unit_xyz, U.unit_valid, U.trace, U.walk_open

local P_HERE, P_DEST = R.P_HERE, R.P_DEST

local Rg = {}

-- ============================================================================
-- FACING
-- ============================================================================
--- Command the player to face `target`. There is no facing read-back anywhere
--- in the API, so this is fire-and-forget and throttled to FACE_GAP.
function Rg.face(target)
    if not unit_valid(target) then return false end
    if not O.can_act() then return false end
    local t = izi.now()
    if (t - R.last_face_t) < FACE_GAP then return false end
    R.last_face_t = t
    pcall(handler.look_at_target, handler, FACE_LOCK, 0, target)
    local ok, pos = pcall(target.get_position, target)
    if ok and pos then pcall(core.input.look_at, pos) end
    return true
end

-- ============================================================================
-- RANGE / LOS
-- ============================================================================
--- Distance + LoS to a unit, with every verified LoS path tried in turn.
--- Returns in_range, distance, has_los.
function Rg.in_fight_range(player, unit, yards)
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
    if not has_los and FLAG_LOS then
        local fx, fy, fz = here_xyz()
        if not fx then fx, fy, fz = unit_xyz(player) end
        local ux, uy, uz = unit_xyz(unit)
        if fx and ux then
            local okh, ph = pcall(player.get_height, player)
            local okh2, uh = pcall(unit.get_height, unit)
            ph = (okh and type(ph) == "number" and ph > 0) and ph * 0.8 or EYE_Z
            uh = (okh2 and type(uh) == "number" and uh > 0) and uh * 0.8 or EYE_Z
            -- trace() adds EYE_Z itself, so hand it the height minus that
            has_los = trace(pt(P_HERE, fx, fy, fz + ph - EYE_Z),
                            pt(P_DEST, ux, uy, uz + uh - EYE_Z), FLAG_LOS) == true
        end
    end
    if range <= 3 then has_los = true end
    return (range <= yards and has_los), range, has_los
end

function Rg.arrived(dest, yards)
    local hx, hy, hz = here_xyz()
    local x, y, z = xyz(dest)
    if not hx or not x then return false end
    return dist3(hx, hy, hz, x, y, z) <= (yards or ARRIVE)
end

function Rg.line_blocked(from, dest)
    local fx, fy, fz = xyz(from)
    local tx, ty, tz = xyz(dest)
    if not fx or not tx then return false end
    return not walk_open(pt(P_HERE, fx, fy, fz), pt(P_DEST, tx, ty, tz))
end

function Rg.can_reach(from, dest)
    local fx, fy, fz = xyz(from)
    local tx, ty, tz = xyz(dest)
    if not fx or not tx then return false end
    if Z.blocked_xy(tx, ty) then return false end
    local f, d = pt(P_HERE, fx, fy, fz), pt(P_DEST, tx, ty, tz)
    if walk_open(f, d) then return true end
    local hop = dist2(fx, fy, tx, ty)
    if hop > STEER_HOP then hop = STEER_HOP end
    if hop < MIN_NAV then hop = MIN_NAV end
    if S.pick_steer(f, d, hop, false, true) then return true end
    return S.orbit_for_los(f, d, 8) ~= nil
end

return Rg

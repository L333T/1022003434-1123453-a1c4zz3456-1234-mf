-- ============================================================================
-- Master Farmer - Grindbot
-- movement/steer.lua - candidate steering
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Everything that decides WHERE to hop next. Nothing in this file issues a
-- command - it only returns pool points for an actuator module to act on.
-- ============================================================================

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local G = require("movement/geom")
local Z = require("movement/zones")
local L = require("movement/leash")

local MIN_NAV        = K.MIN_NAV
local STEER_HOP      = K.STEER_HOP
local PATH_LEASH     = K.PATH_LEASH
local TRACE_BUDGET   = K.TRACE_BUDGET
local SIDESTEP_YARDS = K.SIDESTEP_YARDS
local ORBIT_DEGREES  = K.ORBIT_DEGREES
local COMBAT_OFFSET  = K.COMBAT_OFFSET
local ESCALATE       = K.ESCALATE

local pt = R.pt
local dist2, walk_open, los_open = U.dist2, U.walk_open, U.los_open
local extend, rotate, sidestep = G.extend, G.rotate, G.sidestep
local blocked_xy = Z.blocked_xy

local P_PRIMARY, P_ALT, P_ON = R.P_PRIMARY, R.P_ALT, R.P_ON
local P_SEED, P_MID, P_STEP, P_ORBIT = R.P_SEED, R.P_MID, R.P_STEP, R.P_ORBIT

local S = {}

--- Is `c` an acceptable hop from `from` (optionally with LoS to `goal`)?
function S.cand_ok(from, c, goal, need_los)
    if blocked_xy(c.x, c.y) then return false end
    if not L.allows(from, c) then return false end
    if not walk_open(from, c) then return false end
    if need_los and goal and not los_open(c, goal) then return false end
    return true
end

local cand_ok = S.cand_ok

--- Find a clear hop of up to `travel` yards from `from` toward `goal`.
--- Returns a pool point (P_PRIMARY / P_ALT / P_STEP / P_MID) or nil.
--- Obstacle memory: the side that last worked is tried first, and each blocked
--- pass escalates the search (wider angles, longer hops - see ESCALATE) so the
--- player walks along and then around the obstacle instead of nibbling at it.
--- The blocked straight hop is returned only when no alternative could be
--- evaluated at all and require_clear is false.
function S.pick_steer(from, goal, travel, need_los, require_clear)
    local primary = extend(P_PRIMARY, from, goal, travel)
    if cand_ok(from, primary, goal, need_los) then
        R.detour_side, R.block_streak = 0, 0
        return primary
    end

    -- a long hop that failed: try shorter straight hops before turning
    if travel > STEER_HOP then
        local shorter = extend(P_MID, from, goal, travel * 0.5)
        if cand_ok(from, shorter, goal, need_los) then
            R.detour_side, R.block_streak = 0, 0
            return shorter
        end
        primary = extend(P_PRIMARY, from, goal, STEER_HOP)
        if cand_ok(from, primary, goal, need_los) then
            R.detour_side, R.block_streak = 0, 0
            return primary
        end
        travel = STEER_HOP
    end

    local evaluated = 0
    if R.traces_used < TRACE_BUDGET then
        local streak = R.block_streak
        local level = ESCALATE[streak >= 3 and 3 or (streak >= 2 and 2 or 1)]
        local angles, seed = level.angles, primary
        if level.hop and travel < level.hop then
            seed = extend(P_MID, from, goal, level.hop)
        end
        -- two passes: the remembered side first, then the other side
        for pass = 1, 2 do
            for i = 1, #angles do
                local deg = angles[i]
                local side = deg > 0 and 1 or -1
                local first = (R.detour_side == 0) or (side == R.detour_side)
                if (pass == 1) == first then
                    local alt = rotate(P_ALT, seed, from, deg)
                    evaluated = evaluated + 1
                    if cand_ok(from, alt, goal, need_los) then
                        R.detour_side = side
                        return alt
                    end
                end
            end
        end
        for i = 1, #SIDESTEP_YARDS do
            local yards = SIDESTEP_YARDS[i]
            local left_first = R.detour_side >= 0
            for k = 1, 2 do
                local left = (k == 1) == left_first
                local c = sidestep(P_STEP, from, primary, left, yards)
                evaluated = evaluated + 1
                if c and cand_ok(from, c, goal, need_los) then
                    R.detour_side = left and 1 or -1
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
    R.block_streak = R.block_streak + 1
    if require_clear then return nil end
    if evaluated == 0 then
        return primary                         -- nothing could be evaluated: let the walker try
    end
    return nil                                 -- evaluated and blocked: caller backs off
end

local pick_steer = S.pick_steer

--- Hop that brings the player back inside the leash, or nil.
function S.rejoin_hop(from)
    local ox, oy, oz, d = L.here_on_leash()
    if not ox or d <= (PATH_LEASH - 0.5) then return nil end
    local on = pt(P_ON, ox, oy, oz)
    local travel = d
    if travel > STEER_HOP then travel = STEER_HOP end
    if travel < MIN_NAV then travel = MIN_NAV end
    local hop = pick_steer(from, on, travel, false, true)
    if hop then return hop end
    if d <= (PATH_LEASH + STEER_HOP) and walk_open(from, on) then return on end
    hop = pick_steer(from, on, travel, false, false)
    if hop and L.allows(from, hop) then return hop end
    return nil
end

--- A point `hold` yards from goal with LoS to it (orbit search), or nil.
function S.orbit_for_los(from, goal, hold)
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

local orbit_for_los = S.orbit_for_los

--- Navigation steering toward dest. Returns a pool point or nil.
function S.steer(from, dest, max_hop, hold, need_los, require_clear)
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
function S.approach_unit(from, goal, hold)
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

return S

-- ============================================================================
-- Master Farmer - Grindbot
-- movement/locks.lua - rest lock and cast / channel / loot locks
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Locks pause the walker by reason, so a cast finishing can never un-pause a
-- stun or a food break. Releasing a cast lock touches only the cast and loot
-- reasons; rest and restrict are owned by their own callers.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type movement_handler
local handler = require("common/utility/movement_handler")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local W = require("movement/walker")
local O = require("movement/own")

local OWNER      = K.OWNER
local QUIET_STOP = K.QUIET_STOP

local dlog = U.dlog

local Lk = {}

-- ============================================================================
-- REST LOCK
-- ============================================================================
function Lk.set_resting(on)
    if on == true then
        if not R.rest_lock then
            R.rest_lock = true
            W.set_pause("rest", true)
            W.set_quiet(QUIET_STOP)
            O.halt_all()
            R.cur_owner = OWNER.NONE
            dlog("rest", "resting - movement released")
        end
        return
    end
    if R.rest_lock then
        R.rest_lock = false
        W.set_pause("rest", false)
        dlog("rest", "resting cleared")
    end
end

function Lk.is_resting() return R.rest_lock end

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
    if gen == R.lock_gen then Lk.release() end
end

local function arm_unlock(seconds)
    R.lock_gen = R.lock_gen + 1
    local gen = R.lock_gen
    -- one small closure per cast lock (not per frame); it captures only `gen`
    pcall(izi.after, seconds, function() on_unlock_timer(gen) end)
end

--- Release a cast / channel / loot lock. Does not touch the rest or restriction
--- pauses, so finishing a cast cannot un-pause a stun or a food break.
function Lk.release()
    R.lock_gen = R.lock_gen + 1
    pcall(handler.resume_movement, handler)
    pcall(handler.unlock_look_at, handler)
    W.set_pause("cast", false)
    W.set_pause("loot", false)
end

local function begin_lock(sec, light, target, pos)
    W.set_pause("cast", true)
    if light then
        pcall(handler.pause_movement_light, handler, sec)
    else
        pcall(handler.pause_movement, handler, sec + 0.5)
    end
    if target then
        pcall(handler.look_at_target, handler, sec, 0, target)
    elseif pos then
        pcall(handler.look_at_position, handler, sec, 0, pos)
    end
    arm_unlock(light and sec or (sec + 0.5))
end

function Lk.prepare_cast(target, duration)
    begin_lock(clamp_sec(duration, 0.5), true, target, nil)
end

function Lk.prepare_channel(target, duration)
    begin_lock(clamp_sec(duration, 3.0), false, target, nil)
end

function Lk.prepare_ground(pos, duration, channel)
    begin_lock(clamp_sec(duration, channel and 3.0 or 0.5), not channel, nil, pos)
end

function Lk.pause_for_loot(duration)
    O.halt_all()
    W.set_pause("loot", true)
    begin_lock(clamp_sec(duration, 0.5), true, nil, nil)
end

-- ============================================================================
-- FAILURE REPORTING
-- ============================================================================
function Lk.last_fail_offmesh()
    return R.last_fail.valid and R.last_fail.offmesh
end

function Lk.last_fail_reason()
    if R.last_fail.valid then return R.last_fail.reason end
    return nil
end

function Lk.clear_fail() R.last_fail.valid = false end

return Lk

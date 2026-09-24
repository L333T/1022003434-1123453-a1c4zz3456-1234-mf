-- ============================================================================
-- Master Farmer - Grindbot
-- movement/fsm.lua - stuck watch, arbitration, per-frame pulse, events
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- The top of the movement stack. Nothing requires this module except the
-- facade, so it is free to depend on every layer below it.
--
-- State transitions are debounced: escalations (restriction, combat entry) are
-- immediate; releases must hold for a settle window. Nothing toggles per frame.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type movement_handler
local handler = require("common/utility/movement_handler")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local Z = require("movement/zones")
local L = require("movement/leash")
local W = require("movement/walker")
local N = require("movement/sentinel")
local O = require("movement/own")
local C = require("movement/combat")

local STATE             = K.STATE
local OWNER             = K.OWNER
local SETTLE            = K.SETTLE
local COMBAT_EXIT_HOLD  = K.COMBAT_EXIT_HOLD
local PATH_LEASH        = K.PATH_LEASH
local STUCK_GRACE       = K.STUCK_GRACE
local STUCK_MOVE        = K.STUCK_MOVE
local STUCK_ZONE_RADIUS = K.STUCK_ZONE_RADIUS

local pt = R.pt
local here_xyz, dist2, dlog = U.here_xyz, U.dist2, U.dlog

local P_TMP = R.P_TMP

local F = {}

-- ============================================================================
-- STUCK WATCH
-- ============================================================================
local function watch_stuck(t)
    local x, y = here_xyz()
    if not R.pending or R.rest_lock or not x then
        R.stuck_x, R.stuck_y, R.stuck_since = x, y, t
        return
    end
    if not R.stuck_x or dist2(x, y, R.stuck_x, R.stuck_y) >= STUCK_MOVE then
        R.stuck_x, R.stuck_y, R.stuck_since = x, y, t
        return
    end
    if (t - R.stuck_since) < STUCK_GRACE then return end
    R.stuck_grace_until = t + STUCK_GRACE
    W.set_quiet(1.5)
    local had, dx, dy, dz = R.has_dest, R.dest_x, R.dest_y, R.dest_z
    W.clear_dest()
    W.halt()
    if had and dist2(x, y, dx, dy) > 16 then
        Z.blacklist_area(pt(P_TMP, dx, dy, dz), STUCK_ZONE_RADIUS, "stuck")
    end
    dlog("stuck", "move cancelled")
    R.stuck_x, R.stuck_y, R.stuck_since = x, y, t
end

-- ============================================================================
-- ARBITRATION
-- ============================================================================
--- Resolve state and ownership for this tick, in strict priority order.
local function arbitrate(player, t)
    -- 1 + 2. invalid / dead / crowd control / resting
    local why = O.restriction_of(player)
    if why then
        R.restrict_why = why
        if R.restrict_since == 0 then R.restrict_since = t end
        R.clear_since = 0
        W.set_pause("restrict", true)
        if R.cur_state ~= STATE.RESTRICTED then
            O.halt_all()
            R.cur_owner = OWNER.NONE
            O.set_state(STATE.RESTRICTED, why)
        end
        return
    end

    -- restrictions must stay clear for SETTLE before we steer again
    if R.clear_since == 0 then R.clear_since = t end
    if (t - R.clear_since) < SETTLE then
        R.restrict_why = nil
        return
    end
    R.restrict_why, R.restrict_since = nil, 0
    W.set_pause("restrict", false)

    -- 3. combat movement
    if R.combat_req and (t - R.combat_req_t) <= 1.0 then
        R.combat_ok_since = 0
        if R.cur_state ~= STATE.COMBAT then O.set_state(STATE.COMBAT, "engaged") end
        return
    end

    -- combat was requested recently but the caller has stopped asking: hold the
    -- player until every end condition has been true for COMBAT_EXIT_HOLD
    if R.cur_state == STATE.COMBAT or O.owns(OWNER.COMBAT) then
        local may, blocker = C.may_release(player)
        if not may then
            R.combat_ok_since = 0
            dlog("combat_end", "holding: " .. tostring(blocker))
            return
        end
        if R.combat_ok_since == 0 then
            R.combat_ok_since = t
            dlog("combat_end", "all clear - settling")
            return
        end
        if (t - R.combat_ok_since) < COMBAT_EXIT_HOLD then return end
        C.combat_release()
        O.set_state(STATE.IDLE, "combat complete")
        return
    end

    -- 4. navigation / idle
    if O.owns(OWNER.NAV) and O.is_moving() then
        if R.cur_state ~= STATE.NAVIGATION then O.set_state(STATE.NAVIGATION, "moving") end
    elseif R.cur_state ~= STATE.IDLE then
        O.set_state(STATE.IDLE, "nothing to do")
    end
end

-- ============================================================================
-- PER-FRAME
-- ============================================================================
function F.pulse()
    R.pulse_tick = R.pulse_tick + 1
    R.traces_used = 0
    W.ensure()
    local t = izi.now()

    local player = nil
    local okp, me = pcall(izi.me)
    if okp then player = me end

    -- Sentinel owns the tick while it is driving: the walker must stay silent.
    if R.sn_active then
        R.walker_moving = false
        N.watch(t)
        arbitrate(player, t)
        R.combat_req = false
        Z.prune(t)
        return
    end

    if W.process() then W.clear_dest() end
    W.sample()
    if R.pending and not R.walker_moving and (t - R.last_move_t) >= 0.3 then
        W.clear_dest()        -- walker has no destination: it finished or gave up
    end

    watch_stuck(t)
    if R.leash and not R.leash_armed and not R.rest_lock then
        local _, _, _, d = L.here_on_leash()
        if d and d <= PATH_LEASH then R.leash_armed = true end
    end

    arbitrate(player, t)
    R.combat_req = false      -- callers must re-assert every tick
    Z.prune(t)
end

function F.on_render()
    pcall(handler.on_render, handler)
end

function F.set_debug(on)
    R.debug_on = on == true
end

-- ============================================================================
-- EVENTS  (events update state, they never issue movement)
-- ============================================================================
do
    --- True when the event describes the local player. The payload is
    --- { unit = game_object }; anything else is somebody else's fight.
    local function is_me(ev)
        if type(ev) ~= "table" then return false end
        local unit = ev.unit
        if unit == nil then return true end        -- no unit field: player event
        local ok, me = pcall(izi.me)
        return ok and me ~= nil and unit == me
    end

    if type(izi.on_combat_start) == "function" then
        pcall(izi.on_combat_start, function(ev)
            if is_me(ev) then R.in_combat_flag = true end
        end)
    end
    if type(izi.on_combat_finish) == "function" then
        pcall(izi.on_combat_finish, function(ev)
            if is_me(ev) then R.in_combat_flag = false end
        end)
    end
    -- the class profile reads these to decide whether a retreat is warranted
    if type(izi.on_spell_success) == "function" then
        pcall(izi.on_spell_success, function(ev)
            if type(ev) ~= "table" then return end
            local caster = ev.caster
            local okp, me = pcall(izi.me)
            if not okp or not me or caster ~= me then return end
            R.last_spell_id = ev.spell_id
            R.last_spell_target = ev.target
            R.last_spell_t = izi.now()
        end)
    end
end

function F.last_player_spell()
    return R.last_spell_id, R.last_spell_target, R.last_spell_t
end

return F

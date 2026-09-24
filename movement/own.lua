-- ============================================================================
-- Master Farmer - Grindbot
-- movement/own.lua - ownership, state transitions, restrictions, shared gates
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- The arbiter primitives every higher module shares:
--
--   take(who)     transfer ownership, halting the outgoing actuator first
--   halt_all()    stop whichever actuator owns input (this is why the module
--                 sits above both walker.lua and sentinel.lua)
--   may_issue()   the cheap gates that run before any navigation move
--
-- Keeping these here is what lets walker.lua and sentinel.lua stay independent
-- of each other instead of forming a require cycle.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")
local W = require("movement/walker")
local N = require("movement/sentinel")

local STATE            = K.STATE
local OWNER            = K.OWNER
local RESTRICT         = K.RESTRICT
local MIN_NAV          = K.MIN_NAV
local MOVE_GAP         = K.MOVE_GAP
local COMBAT_GAP       = K.COMBAT_GAP
local INFLIGHT_TIMEOUT = K.INFLIGHT_TIMEOUT

local here_xyz, dist3, dlog = U.here_xyz, U.dist3, U.dlog
local unit_valid, unit_alive = U.unit_valid, U.unit_alive

local O = {}

-- ============================================================================
-- STATE TRANSITIONS
-- ============================================================================
function O.set_state(next_state, why)
    if R.cur_state == next_state then return end
    dlog("state", R.cur_state .. " -> " .. next_state .. (why and (" (" .. why .. ")") or ""))
    R.cur_state = next_state
    R.state_since = izi.now()
end

function O.state() return R.cur_state end
function O.owner() return R.cur_owner end

-- ============================================================================
-- HALT
-- ============================================================================
--- Stop whichever actuator owns input. Returns false when nothing was moving
--- (so a caller that stops every frame does not spam or extend quiet).
function O.halt_all()
    local was_active = R.pending or R.has_dest or R.walker_moving or R.sn_active
    N.stop()
    W.clear_dest()
    R.retreat_until = 0
    if not was_active then return false end
    local t = izi.now()
    R.last_stop_t, R.last_move_t = t, t
    W.halt()
    return true
end

-- ============================================================================
-- OWNERSHIP
-- ============================================================================
--- Transfer movement ownership. The outgoing actuator is always halted before
--- the incoming owner is allowed to issue anything, so two subsystems can never
--- steer on the same tick. Returns true when `who` now owns movement.
function O.take(who)
    if R.cur_owner == who then return true end
    local from = R.cur_owner
    O.halt_all()
    R.cur_owner = who
    dlog("owner", from .. " -> " .. who)
    return true
end

--- Guard every command: only the current owner may actuate.
function O.owns(who)
    return R.cur_owner == who
end

local owns = O.owns

-- ============================================================================
-- MOVEMENT RESTRICTIONS
-- ============================================================================
local function cc_check(unit, method)
    local fn = unit[method]
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, unit)
    return ok and v == true
end

--- Highest-priority reason the player cannot be steered right now, or nil.
--- Ordering matters: invalid/dead first, then hard control loss, then root
--- (cannot move but may act), then resting, then an active cast lock.
function O.restriction_of(player)
    if not player or not unit_valid(player) then return RESTRICT.INVALID end
    -- A ghost walks - that is the corpse run, and death.lua drives it through
    -- normal navigation. Only an unreleased corpse is a movement restriction.
    local okg, ghost = pcall(player.is_ghost, player)
    if not (okg and ghost == true) and not unit_alive(player) then
        return RESTRICT.DEAD
    end
    if cc_check(player, "is_stunned") then return RESTRICT.STUN end
    if cc_check(player, "is_feared") then return RESTRICT.FEAR end
    if cc_check(player, "is_incapacitated") then return RESTRICT.INCAP end
    if cc_check(player, "is_disoriented") then return RESTRICT.DISORI end
    if cc_check(player, "is_rooted") then return RESTRICT.ROOT end
    if R.rest_lock then return RESTRICT.REST end
    return nil
end

function O.is_restricted() return R.cur_state == STATE.RESTRICTED end
function O.restriction() return R.restrict_why end

--- Root stops movement but not casting or facing, so the combat controller may
--- still turn and fire while rooted. Every other restriction is a hard stop.
function O.can_act()
    return R.restrict_why == nil or R.restrict_why == RESTRICT.ROOT
end

-- ============================================================================
-- SHARED GATES
-- ============================================================================
function O.nav_gap_ok()
    local t = izi.now()
    local last = R.last_move_t
    if R.last_stop_t > last then last = R.last_stop_t end
    return (t - last) >= (owns(OWNER.COMBAT) and COMBAT_GAP or MOVE_GAP)
end

function O.is_quiet()
    local t = izi.now()
    return t < R.quiet_until or t < R.stuck_grace_until
end

function O.is_moving()
    if R.rest_lock then return false end
    if R.sn_active then return true end
    if R.walker_moving then return true end
    return R.pending and (izi.now() - R.last_move_t) < INFLIGHT_TIMEOUT
end

local is_moving = O.is_moving

function O.sentinel_active() return R.sn_active end

--- Cheap gates shared by every navigation move. Returns true when a new move
--- may be issued now, or false plus the value the caller should return instead.
function O.may_issue(x, y, z)
    if not owns(OWNER.NAV) then return false, false end
    if R.rest_lock then return false, false end
    if is_moving() then return false, true end                   -- already going
    local t = izi.now()
    if t < R.quiet_until or t < R.stuck_grace_until or t < R.steer_backoff_until then
        return false, W.same_dest(x, y)
    end
    if not O.nav_gap_ok() then return false, W.same_dest(x, y) end
    local hx, hy, hz = here_xyz()
    if not hx then return false, false end
    if dist3(hx, hy, hz, x, y, z) < MIN_NAV then return false, false end
    local lf = R.last_fail
    if lf.valid and lf.offmesh and t < R.fail_cooldown_until and W.same_dest(x, y) then
        return false, false
    end
    if not W.ensure() then return false, false end
    return true
end

return O

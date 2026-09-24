-- ============================================================================
-- Master Farmer - Grindbot
-- Intelligent Movement & Navigation System - public facade
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- SINGLE-OWNER MOVEMENT STATE MACHINE
--
--   STATE      IDLE -> NAVIGATION -> COMBAT, plus RESTRICTED above all.
--   OWNER      NONE | NAV | COMBAT.  Exactly one may issue a command.
--
-- Handing movement over always goes through own.take(owner): it halts the
-- outgoing actuator before the incoming one is allowed to speak, so two
-- subsystems can never steer on the same tick.
--
-- ACTUATORS
--   simple_movement ("walker")  the only thing that moves the player.
--                               NAV drives it for travel and saved paths.
--                               COMBAT drives it for approach / retreat hops.
--   SentinelNavClient           optional navmesh fallback, OOC only. Used for
--                               long legs, blocked lines and stuck recovery.
--                               Absent = we degrade to walker steering.
--   movement_handler            facing and cast/channel pauses only. It has no
--                               move method, so it never repositions anything.
--
-- PAUSE MODEL
--   walker:pause()/resume() is reference counted by reason (cast, restrict,
--   rest, loot, nav). Resume only fires when every reason has cleared, so a
--   cast finishing cannot un-pause a stun.
--
-- STATE TRANSITIONS are debounced. Escalations (restriction, combat entry) are
-- immediate; releases must hold for a settle window. Nothing toggles per frame.
--
-- MEMORY MODEL
--   * no closures on the per-frame path: guarded calls are pcall(fn, args...)
--   * steering math is plain numbers; candidates live in a fixed pool of tables
--   * one vec3 is allocated per ISSUED move, never per candidate
--   * cheap gates run before any trace line
--   * blacklist zones are pruned in place; the leash is flattened once
--
-- ----------------------------------------------------------------------------
-- WHY THIS FILE IS A FACADE
-- ----------------------------------------------------------------------------
-- Lua allows at most 200 local variables in any one function, and a file IS a
-- function (its main chunk). The previous single-file movement.lua declared 235
-- top-level locals, so the Sylvanas loader could not compile it at all:
--
--     movement.lua: main function has more than 200 local variables
--
-- The logic now lives in movement/*.lua. Each module declares its own handful
-- of locals and is nowhere near the limit. Shared MUTABLE state lives in
-- movement/rt.lua, because upvalues cannot cross a chunk boundary; shared
-- CONSTANTS live in movement/const.lua and are pulled into module locals at
-- load time, so the hot path still reads an upvalue and not a table field.
--
-- LAYERS (each may only require the ones above it)
--   const   enums, tunables, engine flags          (no deps)
--   rt      mutable state, point pool, scratch     (const)
--   util    logging, position, distance, traces    (const, rt)
--   zones   blacklist areas                        (util)
--   geom    number-only geometry                   (util)
--   leash   path corridor                          (util)
--   steer   candidate search                       (geom, zones, leash)
--   walker  simple_movement actuator               (zones, util)
--   sentinel navmesh fallback actuator             (walker, zones)
--   own     ownership, restrictions, gates, halt   (walker, sentinel)
--   locks   rest / cast / channel / loot locks     (own, walker)
--   range   facing, range, LoS, reachability       (steer, own)
--   nav     navigation                             (own, steer, actuators)
--   combat  combat movement                        (own, steer, range)
--   fsm     stuck watch, arbitration, pulse        (combat, nav layers)
--   diag    snapshot / dump                        (own, walker, leash)
--
-- The public surface below is unchanged: every call site that did
-- `require("movement")` keeps working exactly as before.
-- ============================================================================

local K  = require("movement/const")
local U  = require("movement/util")
local Z  = require("movement/zones")
local L  = require("movement/leash")
local W  = require("movement/walker")
local N  = require("movement/sentinel")
local O  = require("movement/own")
local Lk = require("movement/locks")
local Rg = require("movement/range")
local Nv = require("movement/nav")
local C  = require("movement/combat")
local F  = require("movement/fsm")
local D  = require("movement/diag")

local movement = {}

-- ============================================================================
-- ENUMS
-- ============================================================================
movement.STATE    = K.STATE
movement.OWNER    = K.OWNER
movement.RESTRICT = K.RESTRICT

-- ============================================================================
-- POSITION
-- ============================================================================
movement.to_pos = U.to_pos

--- Ground height under (x, y), falling back to hint_z when the lookup fails or
--- lands on the wrong floor. Exported because callers that build their own
--- candidate points - death.lua's safe-spot offsets, for one - otherwise place
--- them at the source point's z and can end up inside terrain on a slope.
movement.ground_z = U.ground_z

-- ============================================================================
-- BLACKLIST ZONES
-- ============================================================================
movement.blacklist_area = Z.blacklist_area
movement.is_blocked     = Z.is_blocked
movement.zone_count     = Z.count

-- ============================================================================
-- STATE / OWNERSHIP / RESTRICTIONS
-- ============================================================================
movement.owner         = O.owner
movement.state         = O.state
movement.is_restricted = O.is_restricted
movement.restriction   = O.restriction
movement.can_act       = O.can_act

-- ============================================================================
-- COMBAT PROFILE
-- ============================================================================
movement.set_combat_profile   = C.set_combat_profile
movement.clear_combat_profile = C.clear_combat_profile

-- ============================================================================
-- FACING / RANGE / LOS
-- ============================================================================
movement.face           = Rg.face
movement.in_fight_range = Rg.in_fight_range
movement.arrived        = Rg.arrived
movement.line_blocked   = Rg.line_blocked
movement.can_reach      = Rg.can_reach

-- ============================================================================
-- MOVEMENT GATES
-- ============================================================================
movement.is_quiet        = O.is_quiet
movement.is_moving       = O.is_moving
movement.sentinel_active = O.sentinel_active

-- ============================================================================
-- NAVIGATION
-- ============================================================================
movement.nav_to        = Nv.nav_to
movement.nav_path      = Nv.nav_path
movement.nav_stop      = Nv.nav_stop
movement.halt          = Nv.halt
movement.nav_pause     = Nv.nav_pause
movement.nav_resume    = Nv.nav_resume
movement.is_navigating = Nv.is_navigating
movement.can_navigate  = Nv.can_navigate
movement.rejoin_path   = Nv.rejoin_path

-- ============================================================================
-- PATH LEASH
-- ============================================================================
movement.set_path_leash    = L.set_path_leash
movement.clear_path_leash  = L.clear_path_leash
movement.path_offset       = L.path_offset
movement.needs_rejoin      = L.public_needs_rejoin
movement.path_anchor_index = L.path_anchor_index

-- ============================================================================
-- FAILURE REPORTING
-- ============================================================================
movement.last_fail_offmesh = Lk.last_fail_offmesh
movement.last_fail_reason  = Lk.last_fail_reason
movement.clear_fail        = Lk.clear_fail

-- ============================================================================
-- REST / CAST / CHANNEL LOCKS
-- ============================================================================
movement.set_resting     = Lk.set_resting
movement.is_resting      = Lk.is_resting
movement.release         = Lk.release
movement.prepare_cast    = Lk.prepare_cast
movement.prepare_channel = Lk.prepare_channel
movement.prepare_ground  = Lk.prepare_ground
movement.pause_for_loot  = Lk.pause_for_loot

-- ============================================================================
-- COMBAT MOVEMENT
-- ============================================================================
movement.combat_engage      = C.combat_engage
movement.in_combat_movement = C.in_combat_movement
movement.combat_unit        = C.combat_unit
movement.combat_release     = C.combat_release

-- ============================================================================
-- PER-FRAME / EVENTS
-- ============================================================================
movement.pulse             = F.pulse
movement.on_render         = F.on_render
movement.set_debug         = F.set_debug
movement.last_player_spell = F.last_player_spell

-- ============================================================================
-- SENTINEL HELPERS
-- ============================================================================
movement.plan_grind_route = N.plan_grind_route
movement.grind_visit_order = N.grind_visit_order
movement.node_reachable   = N.node_reachable

-- ============================================================================
-- DIAGNOSTICS
-- ============================================================================
movement.debug_snapshot = D.debug_snapshot
movement.dump           = D.dump

-- ============================================================================
-- STRICT SURFACE
-- ============================================================================
-- Reading a field that does not exist is a bug in a caller, not a no-op. Log it
-- loudly (once per key) and return nil so the plugin degrades instead of dying.
local missing_reported = {}
setmetatable(movement, {
    __index = function(_, key)
        if type(key) == "string" and not missing_reported[key] then
            missing_reported[key] = true
            core.log_error(K.TAG .. " movement." .. key .. " does not exist (stale call site)")
        end
        return nil
    end,
})

return movement

-- ============================================================================
-- Master Farmer - Grindbot
-- movement/rt.lua - shared mutable runtime state
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Upvalues cannot cross a chunk boundary, so every piece of state that more
-- than one movement module touches lives here as a field of R. Values that only
-- one module uses stay a local in that module.
--
-- The point pool and the scratch vec3s live here too: they are shared buffers,
-- and duplicating them per module would defeat the whole allocation model.
-- ============================================================================

---@type vec3
local vec3 = require("common/geometry/vector_3")

local K = require("movement/const")

local R = {}

-- ----------------------------------------------------------------------------
-- STATE MACHINE
-- ----------------------------------------------------------------------------
R.cur_state      = K.STATE.IDLE
R.cur_owner      = K.OWNER.NONE
R.restrict_why   = nil
R.restrict_since = 0
R.clear_since    = 0        -- when every restriction last went away
R.state_since    = 0

-- ----------------------------------------------------------------------------
-- ACTUATOR BOOKKEEPING
-- ----------------------------------------------------------------------------
R.pending        = false    -- a move was issued and has not been reported done
R.walker_moving  = false    -- walker:is_moving() sampled once per pulse
R.has_dest       = false
R.dest_x, R.dest_y, R.dest_z = 0, 0, 0
R.last_move_t    = 0
R.last_stop_t    = 0
R.quiet_until    = 0
R.fail_cooldown_until = 0
R.steer_backoff_until = 0
R.stuck_grace_until   = 0
R.walker_ready   = false
R.traces_used    = 0
R.stuck_x, R.stuck_y, R.stuck_since = nil, nil, 0
R.detour_side    = 0        -- +1 left / -1 right: side that last cleared an obstacle
R.block_streak   = 0        -- consecutive steering passes whose straight hop was blocked
R.pulse_tick     = 0
R.debug_on       = false

-- ----------------------------------------------------------------------------
-- PAUSE REFERENCE COUNTING
-- ----------------------------------------------------------------------------
R.pause_reason   = { cast = false, restrict = false, rest = false, loot = false, nav = false }
R.walker_paused  = false
R.rest_lock      = false
R.lock_gen       = 0

-- ----------------------------------------------------------------------------
-- COMBAT
-- ----------------------------------------------------------------------------
R.combat_req     = false    -- a caller asked for combat movement this tick
R.combat_req_t   = 0
R.combat_target  = nil
R.combat_yards   = 20
R.combat_ok_since = 0       -- when every combat-end condition started holding
R.combat_stopped = false    -- we are in position and have halted
R.retreat_until  = 0
R.retreat_x, R.retreat_y, R.retreat_z = 0, 0, 0
R.last_face_t    = 0
R.chase_fail_key, R.chase_fail_t = nil, 0
R.in_combat_flag = false    -- maintained by izi.on_combat_start / on_combat_finish
R.profile        = nil      -- class combat profile (see set_combat_profile)
R.last_spell_id, R.last_spell_target, R.last_spell_t = nil, nil, 0

-- ----------------------------------------------------------------------------
-- FAILURE / ZONES / LEASH / PATH
-- ----------------------------------------------------------------------------
-- last failure: one table, fields overwritten
R.last_fail = { reason = nil, offmesh = false, t = 0, valid = false }

-- blacklist zones: array of { x, y, z, r, t, hits, why } pruned in place
R.zones = {}
R.zones_pruned_t = 0

-- path leash: flat number array { x1, y1, z1, x2, y2, z2, ... }
R.leash        = nil
R.leash_n      = 0
R.leash_armed  = false
R.leash_src    = nil
R.lc_tick, R.lc_x, R.lc_y, R.lc_z, R.lc_d, R.lc_i = -1, 0, 0, 0, nil, 1

-- follow_path cache: the caller's point list and the snapped copy given to the walker
R.path_src = nil
R.path_pts = nil

-- ----------------------------------------------------------------------------
-- SENTINEL FALLBACK
-- ----------------------------------------------------------------------------
R.sn_client, R.sn_checked_t, R.sn_ok = nil, -1e9, false
R.sn_active = false
R.sn_reason = nil
R.sn_events = false
R.sn_watch_t = 0
R.sn_leash_hold = false
R.sn_plan_key, R.sn_plan_order, R.sn_plan_pending = nil, nil, false
R.sn_reach_index, R.sn_reach_ok, R.sn_reach_pending = nil, nil, false

-- ----------------------------------------------------------------------------
-- DEBUG DE-DUPLICATION
-- ----------------------------------------------------------------------------
R.log_last = {}

-- ----------------------------------------------------------------------------
-- SCRATCH BUFFERS
-- ----------------------------------------------------------------------------
-- preallocated vec3s for natives that want a vec3 argument
R.TRACE_A  = vec3.new(0, 0, 0)
R.TRACE_B  = vec3.new(0, 0, 0)
R.HEIGHT_Q = vec3.new(0, 0, 0)

-- candidate point pool: plain { x, y, z } tables reused every steering pass.
-- A pool point is only valid until the next steering call - copy it (to_vec3)
-- before handing it to anything that keeps it.
R.POOL = {}
for i = 1, 12 do R.POOL[i] = { x = 0, y = 0, z = 0 } end

R.P_HERE, R.P_DEST, R.P_PRIMARY, R.P_ALT, R.P_ON = 1, 2, 3, 4, 5
R.P_SEED, R.P_MID, R.P_STEP, R.P_ORBIT, R.P_TMP  = 6, 7, 8, 9, 10

local POOL = R.POOL

--- Write x, y, z into pool slot `i` and return the slot.
function R.pt(i, x, y, z)
    local p = POOL[i]
    p.x, p.y, p.z = x, y, z
    return p
end

--- Copy a pool point into a fresh vec3 (the only per-move allocation).
function R.to_vec3(p)
    return vec3.new(p.x, p.y, p.z)
end

return R

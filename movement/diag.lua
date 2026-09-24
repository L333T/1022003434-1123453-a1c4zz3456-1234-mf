-- ============================================================================
-- Master Farmer - Grindbot
-- movement/diag.lua - diagnostics
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local R = require("movement/rt")
local U = require("movement/util")
local L = require("movement/leash")
local W = require("movement/walker")
local O = require("movement/own")

local here_xyz, dist3, log = U.here_xyz, U.dist3, U.log
local unit_xyz, unit_valid = U.unit_xyz, U.unit_valid

local D = {}

--- One table describing why movement is doing what it is doing. Cheap enough
--- for a GUI panel; it allocates one table per call, so do not poll it per frame.
function D.debug_snapshot()
    local t = izi.now()
    local tx, ty, tz
    if R.combat_target and unit_valid(R.combat_target) then
        tx, ty, tz = unit_xyz(R.combat_target)
    end
    local hx, hy, hz = here_xyz()
    local target_dist
    if tx and hx then target_dist = dist3(hx, hy, hz, tx, ty, tz) end
    local pr = R.pause_reason
    local lf = R.last_fail
    return {
        state          = R.cur_state,
        owner          = R.cur_owner,
        state_age      = t - R.state_since,
        restriction    = R.restrict_why,
        resting        = R.rest_lock,
        paused         = R.walker_paused,
        pause_cast     = pr.cast,
        pause_restrict = pr.restrict,
        pause_rest     = pr.rest,
        pause_loot     = pr.loot,
        pause_nav      = pr.nav,
        moving         = O.is_moving(),
        walker_state   = W.state_name(),
        sentinel       = R.sn_active,
        sentinel_ready = R.sn_ok,
        quiet          = O.is_quiet(),
        has_dest       = R.has_dest,
        dest_x         = R.has_dest and R.dest_x or nil,
        dest_y         = R.has_dest and R.dest_y or nil,
        dest_z         = R.has_dest and R.dest_z or nil,
        in_combat      = R.in_combat_flag,
        combat_target  = R.combat_target,
        combat_yards   = R.combat_yards,
        target_dist    = target_dist,
        retreating     = t < R.retreat_until,
        combat_settle  = R.combat_ok_since > 0 and (t - R.combat_ok_since) or nil,
        leash_armed    = R.leash_armed,
        leash_offset   = select(4, L.here_on_leash()),
        waypoint_index = L.path_anchor_index(),
        fail_reason    = lf.valid and lf.reason or nil,
        fail_offmesh   = lf.valid and lf.offmesh or false,
        zones          = #R.zones,
        profile        = R.profile and R.profile.name or nil,
    }
end

--- Print the snapshot. Manual / keybind use only.
function D.dump()
    local s = D.debug_snapshot()
    log(string.format("state=%s owner=%s restrict=%s moving=%s walker=%s sn=%s quiet=%s",
        s.state, s.owner, tostring(s.restriction), tostring(s.moving),
        tostring(s.walker_state), tostring(s.sentinel), tostring(s.quiet)))
    log(string.format("  target=%s dist=%s yards=%s retreat=%s settle=%s",
        s.combat_target and "yes" or "no",
        s.target_dist and string.format("%.1f", s.target_dist) or "-",
        tostring(s.combat_yards), tostring(s.retreating),
        s.combat_settle and string.format("%.1f", s.combat_settle) or "-"))
    log(string.format("  leash=%s offset=%s wp=%s fail=%s zones=%d profile=%s",
        tostring(s.leash_armed),
        s.leash_offset and string.format("%.1f", s.leash_offset) or "-",
        tostring(s.waypoint_index), tostring(s.fail_reason), s.zones, tostring(s.profile)))
end

return D

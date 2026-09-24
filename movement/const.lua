-- ============================================================================
-- Master Farmer - Grindbot
-- movement/const.lua - enums, tunables and engine flags
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Immutable. Every value here was a top-level `local` in the old movement.lua.
-- Modules pull the handful they need into their own locals at load time, so the
-- hot path still reads an upvalue and not a table field.
-- ============================================================================

---@type enums
local enums = require("common/enums")

local K = {}

-- ----------------------------------------------------------------------------
-- ENUMS
-- ----------------------------------------------------------------------------
K.STATE = {
    IDLE       = "IDLE",
    NAVIGATION = "NAVIGATION",
    COMBAT     = "COMBAT",
    RESTRICTED = "RESTRICTED",
}

K.OWNER = {
    NONE   = "NONE",
    NAV    = "NAV",
    COMBAT = "COMBAT",
}

-- why movement is currently impossible / unsafe (highest priority first)
K.RESTRICT = {
    INVALID = "invalid",
    DEAD    = "dead",
    STUN    = "stunned",
    FEAR    = "feared",
    INCAP   = "incapacitated",
    DISORI  = "disoriented",
    ROOT    = "rooted",
    REST    = "resting",
    CAST    = "casting",
}

-- ----------------------------------------------------------------------------
-- TUNABLES
-- ----------------------------------------------------------------------------
K.TAG              = "[Master Farmer - Grindbot]"

-- navigation
K.MIN_NAV          = 2.0    -- never issue a move shorter than this
K.ARRIVE           = 2.0
K.SAME_DEST        = 6.0    -- destinations closer than this are "the same"
K.MOVE_GAP         = 0.85   -- seconds between navigation moves
K.COMBAT_GAP       = 0.5    -- seconds between combat moves
K.INFLIGHT_TIMEOUT = 8.0    -- an issued move counts as moving for this long
K.FAIL_COOLDOWN    = 6.0
K.QUIET_STOP       = 1.25
K.QUIET_OFFMESH    = 5.0
K.PATROL_HOP       = 40.0   -- nav hop length when the direct line is clear
K.STEER_HOP        = 5.0    -- combat / avoidance hop length
K.STEER_BACKOFF    = 0.5    -- seconds before retrying a steer that found nothing
K.PATH_LEASH       = 10.0

-- blacklist zones
K.ZONE_RADIUS      = 12.0
K.ZONE_MERGE       = 10.0
K.ZONE_TTL         = 900.0
K.ZONE_PRUNE_EVERY = 5.0
K.MAX_ZONES        = 24

-- stuck watch
K.STUCK_ZONE_RADIUS = 14.0
K.STUCK_GRACE      = 4.0
K.STUCK_MOVE       = 1.5    -- yards of progress that resets the stuck timer

-- geometry
K.EYE_Z            = 1.6
K.TRACE_BUDGET     = 10     -- trace lines per pulse
K.SIDESTEP_YARDS   = { 4, 8 }
K.OFFSET_DEGREES   = { 35, -35, 70, -70 }
K.ORBIT_DEGREES    = { 45, -45, 90, -90 }
K.COMBAT_OFFSET    = { 45, -45, 90, -90 }
-- after repeated blocked passes the search widens: walk along, then back around
K.ESCALATE = {
    { angles = K.OFFSET_DEGREES,         hop = nil },
    { angles = { 70, -70, 110, -110 },   hop = 8.0 },
    { angles = { 110, -110, 150, -150 }, hop = 12.0 },
}

-- state machine
K.SETTLE           = 0.35   -- a de-escalation must hold this long
K.COMBAT_EXIT_HOLD = 1.5    -- every combat-end condition must hold this long
K.CHASE_GIVE_UP    = 10.0   -- blacklist a mob we could not reach for this long

-- combat hysteresis. Bands are relative to the rotation's own max range, so
-- nothing here invents a mechanic the rotation has not already defined.
K.CHASE_BAND       = 3.0    -- stop chasing this far inside max range
K.RETREAT_BAND     = 4.0    -- retreat until this far past melee_danger
K.DEFAULT_MELEE_DANGER = 8.0
K.FACE_GAP         = 0.35   -- seconds between facing commands
K.FACE_LOCK        = 0.8    -- look_at lock duration
K.PREDICT_AHEAD    = 0.5    -- seconds of lookahead for closing enemies
K.PREDICT_MARGIN   = 1.5    -- predicted distance must beat the band by this

-- diagnostics
K.LOG_REPEAT       = 2.0    -- same debug line is not reprinted inside this

K.OFFMESH_WORDS = { "navmesh", "unreachable", "blocked", "blacklisted", "422", "max_stuck" }
K.SN_NEED = { "move_to", "follow_path", "stop", "is_moving", "get_state", "validate_destination" }

-- ----------------------------------------------------------------------------
-- ENGINE FLAGS
-- ----------------------------------------------------------------------------
K.FLAG_COLLISION, K.FLAG_LOS = nil, nil
do
    local cf = type(enums) == "table" and enums.collision_flags
    if type(cf) == "table" then
        if type(cf.Collision) == "number" then K.FLAG_COLLISION = cf.Collision end
        if type(cf.LineOfSight) == "number" then K.FLAG_LOS = cf.LineOfSight end
    end
end

return K

-- ============================================================================
-- Master Farmer - Grindbot
-- Druid grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- The reference grindbot's Druid branch is two lines - Mark of the Wild and
-- Thorns - with no rotation at all. This adds a balance (caster) filler.
--
-- WHY CASTER AND NOT FERAL
--   Cat/Bear levelling is stronger, but it needs form management: every heal
--   and every caster spell requires shifting out, shifting costs mana and a
--   GCD, and a bot that mis-sequences a shift spends the fight in the wrong
--   form doing nothing. Moonfire + Wrath is weaker per kill and far more
--   robust, which is the right trade for an unattended grinder. Feral can be
--   added later behind its own toggle once form state is readable.
--
-- SPELL IDS
--   Highest rank first. A wrong ID fails CLOSED - spellbook reports the spell
--   as unknown and it is never cast - but silently, so `mfg_druid_debug` prints
--   which ones resolved. Run it once after any ID edit.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type enums
local enums = require("common/enums")

local gui = require("gui")
local resting = require("resting")
local racials = require("racials")
local state = require("state")
local spellbook = require("spellbook")

local druid = {}

-- ----------------------------------------------------------------------------
-- SPELLS  (highest rank first)
-- ----------------------------------------------------------------------------
local function make(ids, track_buff, track_debuff)
    local spell = izi.spell(ids)
    if not spell then
        return nil
    end
    if track_buff and spell.track_buff then
        spell:track_buff(ids)
    end
    if track_debuff and spell.track_debuff then
        spell:track_debuff(ids)
    end
    return spellbook.watch(spell)
end

local MOTW_IDS      = { 26990, 9885, 9884, 8907, 5234, 6756, 5232, 1126 }
local THORNS_IDS    = { 26992, 9910, 9756, 8914, 1075, 782, 467 }
local MOONFIRE_IDS  = { 26988, 26987, 9835, 9834, 9833, 8929, 8928, 8927, 8926, 8925, 8924, 8921 }
local REJUV_IDS     = { 26982, 26981, 25299, 9841, 9840, 9839, 8910, 3627, 2091, 2090, 1430, 1058, 774 }
local ROOTS_IDS     = { 26989, 9853, 9852, 5196, 5195, 1062, 339 }
local FAERIE_IDS    = { 26993, 9907, 9749, 778, 770 }

local mark_of_wild = make(MOTW_IDS, true, false)
local thorns       = make(THORNS_IDS, true, false)

local moonfire     = make(MOONFIRE_IDS, false, true)
local wrath        = make({ 26985, 26984, 9912, 8905, 6780, 5180, 5179, 5178, 5177, 5176 })
local faerie_fire  = make(FAERIE_IDS, false, true)
local entangling   = make(ROOTS_IDS, false, true)
local rejuvenation = make(REJUV_IDS, true, false)
local regrowth     = make({ 26980, 9858, 9857, 9856, 8941, 8940, 8939, 8936 })
local healing_touch = make({ 26979, 26978, 25297, 9889, 9888, 9758, 8903, 6778, 5189, 5188, 5187, 5186, 5185 })

local SPELL_LABELS = {
    { "Mark of the Wild", mark_of_wild },
    { "Thorns",           thorns },
    { "Moonfire",         moonfire },
    { "Wrath",            wrath },
    { "Faerie Fire",      faerie_fire },
    { "Entangling Roots", entangling },
    { "Rejuvenation",     rejuvenation },
    { "Regrowth",         regrowth },
    { "Healing Touch",    healing_touch },
}

-- ----------------------------------------------------------------------------
-- HELPERS
-- ----------------------------------------------------------------------------
local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function rotation_note(text)
    local ok, rotation = pcall(require, "rotation")
    if ok and rotation and type(rotation.set_last_action) == "function" then
        rotation.set_last_action(text)
    end
    state.last_action = text
end

local function learned(spell)
    if not spell or not spellbook.ready() then
        return false
    end
    return spellbook.spell_known(spell)
end

local function as_pct(value)
    if type(value) ~= "number" then
        return nil
    end
    if value >= 0 and value <= 1.5 then
        return value * 100
    end
    return value
end

local function health_pct(unit)
    local pct = as_pct(safe(function() return unit:health_pct() end))
    if pct then
        return pct
    end
    -- unit:health_current() does not exist on this API. The working names are
    -- get_health_percentage (which health_pct above aliases) and the
    -- get_health / get_max_health pair, so the fallback uses those. Before
    -- 1.6.3 every step of this fallback threw, and a health_pct that ever
    -- failed would have left the unit looking permanently at full health.
    local pct = as_pct(safe(function() return unit:get_health_percentage() end))
    if pct then
        return pct
    end
    local cur = safe(function() return unit:get_health() end)
    local mx = safe(function() return unit:get_max_health() end)
    if type(cur) == "number" and type(mx) == "number" and mx > 0 then
        return (cur / mx) * 100
    end
    return 100
end

local function cast_self(spell, player, label)
    if not spell or not player then
        return false
    end
    local ok = safe(function() return spell:cast_safe(player, label) end)
    if ok ~= true then
        ok = safe(function() return spell:cast(player, label) end)
    end
    if ok == true then
        rotation_note(label)
        return true
    end
    return false
end

local function cast_at(spell, target, label)
    if not spell or not target then
        return false
    end
    local ok = safe(function() return spell:cast_safe(target, label) end)
    if ok ~= true then
        ok = safe(function() return spell:cast(target, label) end)
    end
    if ok == true then
        rotation_note(label)
        return true
    end
    return false
end

local function has_aura(unit, ids)
    if not unit then
        return false
    end
    if safe(function() return unit:has_buff(ids) end) == true then
        return true
    end
    return safe(function() return unit:has_aura(ids) end) == true
end

-- ----------------------------------------------------------------------------
-- DIAGNOSTIC
-- ----------------------------------------------------------------------------
local debug_printed = false

local function debug_dump()
    if debug_printed or not gui.is_on("druid_debug") then
        return
    end
    if not spellbook.ready() then
        return
    end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Druid spell resolution:")
    for i = 1, #SPELL_LABELS do
        local name, spell = SPELL_LABELS[i][1], SPELL_LABELS[i][2]
        core.log(string.format("    %-18s %s", name,
            (spell and learned(spell)) and "OK" or "not learned / unresolved"))
    end
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function druid.class_id()
    return enums.class_id.DRUID
end

function druid.label()
    return "Druid"
end

function druid.combat_range(player)
    if wrath and type(wrath.maximum_range) == "number" and wrath.maximum_range > 0 then
        return wrath.maximum_range
    end
    return 30
end

-- Entangling Roots is a real root, so unlike the Priest this class CAN kite.
-- Retreat only in the window where the target is actually held, otherwise
-- walking away just donates free melee swings.
--- How far out to look for something to fight.
---
--- Melee has to walk into contact and then stand still, so a wide scan just
--- drags extra mobs into a fight it cannot kite out of. At range the pull
--- starts from where the bot is already standing, so the extra warning is
--- free. This class does both, so the scan follows the same toggle its
--- combat range does.
function druid.scan_range(player)
    if gui.is_on("cat_form") then
        return 20
    end
    return 35
end

function druid.combat_profile()
    return {
        name         = "druid",
        melee_danger = 8,
        melee_safe   = 14,
        should_retreat = function(ctx)
            if not ctx or not ctx.target then
                return false
            end
            if ctx.melee_count < 1 and ctx.distance > 8 then
                return false
            end
            if not gui.is_on("entangling") then
                return false
            end
            return safe(function() return ctx.target:has_debuff(ROOTS_IDS) end) == true
        end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
function druid.register_gui(menu)
    local class_id = enums.class_id.DRUID
    local function opt(label, spell, tooltip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tooltip }
    end
    menu:checkbox("mfg_mark_of_wild", true, opt("Mark of the Wild", mark_of_wild))
    menu:checkbox("mfg_thorns", true, opt("Thorns", thorns))
    menu:checkbox("mfg_moonfire", true, opt("Moonfire", moonfire))
    menu:checkbox("mfg_wrath", true, opt("Wrath", wrath))
    menu:checkbox("mfg_faerie_fire", false, opt("Faerie Fire", faerie_fire))
    menu:checkbox("mfg_entangling", false, opt("Entangling Roots", entangling,
        "Root the target when it reaches melee, then step back out. Costs a GCD."))
    menu:checkbox("mfg_rejuvenation", true, opt("Rejuvenation", rejuvenation))
    menu:checkbox("mfg_regrowth", true, opt("Regrowth", regrowth))
    menu:checkbox("mfg_healing_touch", true, opt("Healing Touch", healing_touch))
    menu:slider_int("mfg_druid_heal_pct", 20, 80, 50, {
        label = "Self-heal below %",
        tab = "class",
        class_id = class_id,
    })
    menu:checkbox("mfg_druid_debug", false, {
        label = "Log spell resolution",
        tab = "class",
        class_id = class_id,
        tooltip = "Prints once which Druid spells the scanner resolved. Use after editing spell IDs.",
    })
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT BUFFS
-- ----------------------------------------------------------------------------
function druid.buffs_ooc(player)
    if not player then
        return false
    end
    if racials.ooc(player) then
        return true
    end
    debug_dump()
    if safe(function() return player:is_in_combat() end) == true then
        return false
    end
    if safe(function() return player:is_mounted() end) == true then
        return false
    end

    if gui.is_on("mark_of_wild") and learned(mark_of_wild) then
        if not has_aura(player, MOTW_IDS) then
            if cast_self(mark_of_wild, player, "Mark of the Wild") then
                return true
            end
        end
    end

    if gui.is_on("thorns") and learned(thorns) then
        if not has_aura(player, THORNS_IDS) then
            if cast_self(thorns, player, "Thorns") then
                return true
            end
        end
    end

    return false
end

-- ----------------------------------------------------------------------------
-- COMBAT
-- ----------------------------------------------------------------------------
local function try_survival(player)
    local hp = health_pct(player)
    local threshold = gui.slider("druid_heal_pct", 50) or 50
    if hp >= threshold then
        return false
    end

    -- HoT first: it keeps healing while we resume casting, where a direct heal
    -- costs the whole GCD for one tick of value.
    if gui.is_on("rejuvenation") and learned(rejuvenation) and not has_aura(player, REJUV_IDS) then
        if cast_self(rejuvenation, player, "Rejuvenation") then
            return true
        end
    end
    if gui.is_on("regrowth") and learned(regrowth) and hp < (threshold - 15) then
        if cast_self(regrowth, player, "Regrowth") then
            return true
        end
    end
    if gui.is_on("healing_touch") and learned(healing_touch) and hp < (threshold - 25) then
        if cast_self(healing_touch, player, "Healing Touch") then
            return true
        end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- RESTING
-- ----------------------------------------------------------------------------
--- Sit down and eat or drink. The thresholds are this class's to choose; the
--- machinery lives in resting.lua so a fix lands once rather than nine times.
function druid.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function druid.tick(player, target, ctx)
    if not player or not target then
        return false
    end
    ctx = ctx or {}
    -- Racials first: they are short cooldowns that only pay off while the
    -- fight is live, and none of them cost a global.
    if racials.tick(player, target, ctx) then
        return true
    end

    if try_survival(player) then
        return true
    end

    local dist = safe(function() return player:distance_to(target) end) or 99

    -- Root only once something is actually in melee, and only if it is not
    -- already rooted - re-casting clips the existing root for no gain.
    if gui.is_on("entangling") and learned(entangling) and dist <= 8 then
        if safe(function() return target:has_debuff(ROOTS_IDS) end) ~= true then
            if cast_at(entangling, target, "Entangling Roots") then
                return true
            end
        end
    end

    if dist > druid.combat_range(player) then
        return false
    end

    if gui.is_on("moonfire") and learned(moonfire) then
        if safe(function() return target:has_debuff(MOONFIRE_IDS) end) ~= true then
            if cast_at(moonfire, target, "Moonfire") then
                return true
            end
        end
    end

    if gui.is_on("faerie_fire") and learned(faerie_fire) then
        if safe(function() return target:has_debuff(FAERIE_IDS) end) ~= true then
            if cast_at(faerie_fire, target, "Faerie Fire") then
                return true
            end
        end
    end

    if gui.is_on("wrath") and learned(wrath) then
        if cast_at(wrath, target, "Wrath") then
            return true
        end
    end

    return false
end

return druid

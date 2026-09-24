-- ============================================================================
-- Master Farmer - Grindbot
-- Paladin grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- WHY THE AURA IS A DROPDOWN AND NOT SIX CHECKBOXES
--   The reference grindbot exposes six independent booleans - Devotion, Frost
--   Resistance, Concentration, Shadow Resistance, Retribution, Fire Resistance -
--   and casts the first enabled one whose buff is missing. Only ONE aura can be
--   active at a time, so enabling two makes each cast cancel the other and the
--   bot re-casts forever, burning a GCD every tick and never fighting.
--
--   One dropdown makes that state unrepresentable. This is the single most
--   important thing not to copy from the source.
--
-- SPELL IDS
--   Highest rank first. A wrong ID fails CLOSED but silently, so
--   `mfg_paladin_debug` prints which ones resolved. Run once after any ID edit.
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

local paladin = {}

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

-- Auras. Index order must match AURA_LABELS below.
local AURA_IDS = {
    { 27149, 10293, 10292, 1032, 10291, 643, 10290, 465 },   -- Devotion
    { 27150, 10301, 10300, 10299, 10298, 7294 },             -- Retribution
    { 19746 },                                               -- Concentration
    { 27152, 19898, 19897, 19888 },                          -- Frost Resistance
    { 27151, 19896, 19895, 19876 },                          -- Shadow Resistance
    { 27153, 19900, 19899, 19891 },                          -- Fire Resistance
}
local AURA_LABELS = {
    "Devotion Aura",
    "Retribution Aura",
    "Concentration Aura",
    "Frost Resistance Aura",
    "Shadow Resistance Aura",
    "Fire Resistance Aura",
}

local auras = {}
for i = 1, #AURA_IDS do
    auras[i] = make(AURA_IDS[i], true, false)
end

local BOM_IDS = { 27140, 25291, 19837, 19836, 19835, 19834, 19740 }
local BOW_IDS = { 27142, 25290, 19854, 19853, 19852, 19850, 19742 }
local SOR_IDS = { 27155, 20293, 20292, 20291, 20290, 20289, 20288, 20287, 21084 }

local blessing_might  = make(BOM_IDS, true, false)
local blessing_wisdom = make(BOW_IDS, true, false)
local seal_righteous  = make(SOR_IDS, true, false)

local judgement     = make({ 20271 })
local crusader_strike = make({ 35395 })
local hammer_wrath  = make({ 27180, 24275, 24274, 24239 })
local consecration  = make({ 27173, 20924, 20923, 20922, 26573 })
local holy_light    = make({ 27136, 27135, 25292, 10329, 10328, 3472, 1042, 879, 639, 635 })
local flash_light   = make({ 27137, 19943, 19942, 19941, 19940, 19939, 19750 })

local SPELL_LABELS = {
    { "Blessing of Might",  blessing_might },
    { "Blessing of Wisdom", blessing_wisdom },
    { "Seal of Righteousness", seal_righteous },
    { "Judgement",          judgement },
    { "Crusader Strike",    crusader_strike },
    { "Hammer of Wrath",    hammer_wrath },
    { "Consecration",       consecration },
    { "Holy Light",         holy_light },
    { "Flash of Light",     flash_light },
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

--- Selected aura index, clamped. The dropdown is 1-based and may return a
--- string label on some menu builds, so both shapes are handled.
local function aura_choice()
    local idx = tonumber(safe(function() return gui.combo("paladin_aura", 1) end))
    if type(idx) ~= "number" or idx ~= idx then
        return 1
    end
    idx = math.floor(idx)
    -- some menu builds are 0-based
    if idx == 0 then
        idx = 1
    end
    if idx < 1 then idx = 1 elseif idx > #AURA_IDS then idx = #AURA_IDS end
    return idx
end

-- ----------------------------------------------------------------------------
-- DIAGNOSTIC
-- ----------------------------------------------------------------------------
local debug_printed = false

local function debug_dump()
    if debug_printed or not gui.is_on("paladin_debug") then
        return
    end
    if not spellbook.ready() then
        return
    end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Paladin spell resolution:")
    for i = 1, #AURA_LABELS do
        core.log(string.format("    %-24s %s", AURA_LABELS[i],
            (auras[i] and learned(auras[i])) and "OK" or "not learned / unresolved"))
    end
    for i = 1, #SPELL_LABELS do
        local name, spell = SPELL_LABELS[i][1], SPELL_LABELS[i][2]
        core.log(string.format("    %-24s %s", name,
            (spell and learned(spell)) and "OK" or "not learned / unresolved"))
    end
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function paladin.class_id()
    return enums.class_id.PALADIN
end

function paladin.label()
    return "Paladin"
end

function paladin.combat_range(player)
    return 5        -- melee
end

-- A paladin has no ranged filler worth kiting for and heavy armour to stand in.
-- Retreating mid-fight is a straight damage loss, so this never asks for it.
--- How far out to look for something to fight.
---
--- Melee has to walk into contact and then stand still, so a wide
--- scan only drags extra mobs into a fight it cannot kite out of.
function paladin.scan_range(player)
    return 20
end

function paladin.combat_profile()
    return {
        name         = "paladin",
        melee_danger = 0,
        melee_safe   = 0,
        should_retreat = function()
            return false
        end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
function paladin.register_gui(menu)
    local class_id = enums.class_id.PALADIN
    local function opt(label, spell, tooltip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tooltip }
    end

    -- One choice, not six toggles. See the header comment.
    menu:combobox("mfg_paladin_aura", 1, AURA_LABELS, {
        label = "Aura",
        tab = "class",
        class_id = class_id,
        tooltip = "Only one aura can be active at a time, so this is a single choice. "
            .. "The highest rank you know is used.",
    })

    menu:checkbox("mfg_blessing", true, opt("Blessing (Might / Wisdom)", blessing_might,
        "Keeps one blessing up. Wisdom is preferred below the mana threshold, Might otherwise."))
    menu:checkbox("mfg_seal", true, opt("Seal of Righteousness", seal_righteous))
    menu:checkbox("mfg_judgement", true, opt("Judgement", judgement))
    menu:checkbox("mfg_crusader_strike", true, opt("Crusader Strike", crusader_strike))
    menu:checkbox("mfg_hammer_wrath", true, opt("Hammer of Wrath", hammer_wrath,
        "Execute: only usable below 20% target health."))
    menu:checkbox("mfg_consecration", false, opt("Consecration", consecration,
        "Off by default: it is expensive and pulls adds while grinding solo."))
    menu:checkbox("mfg_flash_light", true, opt("Flash of Light", flash_light))
    menu:checkbox("mfg_holy_light", true, opt("Holy Light", holy_light))
    menu:slider_int("mfg_paladin_heal_pct", 20, 80, 50, {
        label = "Self-heal below %",
        tab = "class",
        class_id = class_id,
    })
    menu:checkbox("mfg_paladin_debug", false, {
        label = "Log spell resolution",
        tab = "class",
        class_id = class_id,
        tooltip = "Prints once which Paladin spells the scanner resolved. Use after editing spell IDs.",
    })
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT BUFFS
-- ----------------------------------------------------------------------------
function paladin.buffs_ooc(player)
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

    -- Exactly one aura is ever considered, so two can never fight each other.
    local idx = aura_choice()
    local aura = auras[idx]
    if aura and learned(aura) then
        if not has_aura(player, AURA_IDS[idx]) then
            if cast_self(aura, player, AURA_LABELS[idx]) then
                return true
            end
        end
    end

    if gui.is_on("blessing") then
        local have_might = has_aura(player, BOM_IDS)
        local have_wisdom = has_aura(player, BOW_IDS)
        if not have_might and not have_wisdom then
            if learned(blessing_wisdom) and not learned(blessing_might) then
                if cast_self(blessing_wisdom, player, "Blessing of Wisdom") then
                    return true
                end
            elseif learned(blessing_might) then
                if cast_self(blessing_might, player, "Blessing of Might") then
                    return true
                end
            end
        end
    end

    if gui.is_on("seal") and learned(seal_righteous) then
        if not has_aura(player, SOR_IDS) then
            if cast_self(seal_righteous, player, "Seal of Righteousness") then
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
    local threshold = gui.slider("paladin_heal_pct", 50) or 50
    if hp >= threshold then
        return false
    end
    -- Flash first: a 1.5s cast landing is worth more than a 2.5s one that gets
    -- interrupted by the mob still hitting us.
    if gui.is_on("flash_light") and learned(flash_light) then
        if cast_self(flash_light, player, "Flash of Light") then
            return true
        end
    end
    if gui.is_on("holy_light") and learned(holy_light) and hp < (threshold - 20) then
        if cast_self(holy_light, player, "Holy Light") then
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
function paladin.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function paladin.tick(player, target, ctx)
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

    -- The seal is the damage engine and falls off on a timer, so it is
    -- maintained in combat too, not only out of it.
    if gui.is_on("seal") and learned(seal_righteous) and not has_aura(player, SOR_IDS) then
        if cast_self(seal_righteous, player, "Seal of Righteousness") then
            return true
        end
    end

    local dist = safe(function() return player:distance_to(target) end) or 99

    if gui.is_on("hammer_wrath") and learned(hammer_wrath) and dist <= 30 then
        if health_pct(target) < 20 then
            if cast_at(hammer_wrath, target, "Hammer of Wrath") then
                return true
            end
        end
    end

    if dist > 5 then
        return false
    end

    -- Judgement consumes the seal, so it goes after the seal check above and
    -- the seal is re-applied on the next tick.
    if gui.is_on("judgement") and learned(judgement) and has_aura(player, SOR_IDS) then
        if cast_at(judgement, target, "Judgement") then
            return true
        end
    end

    if gui.is_on("crusader_strike") and learned(crusader_strike) then
        if cast_at(crusader_strike, target, "Crusader Strike") then
            return true
        end
    end

    if gui.is_on("consecration") and learned(consecration) then
        if cast_self(consecration, player, "Consecration") then
            return true
        end
    end

    return false
end

return paladin

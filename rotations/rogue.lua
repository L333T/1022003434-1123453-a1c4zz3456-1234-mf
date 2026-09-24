-- ============================================================================
-- Master Farmer - Grindbot
-- Rogue grind filler (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- POISONS ARE NOT IMPLEMENTED, AND THIS IS THE REASON
--   Applying a poison is a two-step interaction: use the poison, which puts it
--   on the cursor, then click the weapon slot. The first half exists here
--   (core.input.use_container_item); the second does not. The reflected API
--   reference has no call that targets an inventory slot with a held item -
--   core.input has use_item, use_item_position and use_item_target, none of
--   which take slot 16 or 17.
--
--   unit:item_has_enchant CAN tell us a poison has worn off, so detection is
--   solved and only application is missing. The moment an inventory-slot use
--   appears, this is a small addition.
--
--   Half-implementing it would be worse than leaving it out: the poison would
--   sit on the cursor, and a cursor holding an item blocks other interactions.
--
-- ENERGY IS NOT MANA
--   Energy regenerates on a fixed tick regardless of what you do, so there is
--   no "conserve" state and no drinking. The rotation therefore spends down to
--   a floor and never waits.
--
-- SPELL IDS
--   Highest rank first; mfg_rogue_debug prints what resolved.
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

local rogue = {}

local MAINHAND_SLOT = 16

local function make(ids, track_buff, track_debuff)
    local spell = izi.spell(ids)
    if not spell then return nil end
    if track_buff and spell.track_buff then spell:track_buff(ids) end
    if track_debuff and spell.track_debuff then spell:track_debuff(ids) end
    return spellbook.watch(spell)
end

local SND_IDS      = { 6774, 5171 }
local EVASION_IDS  = { 26669, 5277 }
local RUPTURE_IDS  = { 26867, 11275, 11274, 8640, 8639, 1943 }

local sinister_strike = make({ 26862, 11294, 11293, 8621, 1759, 1758, 1757, 1752 })
local eviscerate  = make({ 31016, 26865, 11300, 11299, 8624, 8623, 6762, 2098 })
local slice_dice  = make(SND_IDS, true, false)
local rupture     = make(RUPTURE_IDS, false, true)
local backstab    = make({ 26863, 25300, 11280, 11279, 8721, 2590, 2589, 2588, 53 })
local evasion     = make(EVASION_IDS, true, false)
local kick        = make({ 1766 })
local sprint      = make({ 11305, 2983 })

local SPELL_LABELS = {
    { "Sinister Strike", sinister_strike }, { "Eviscerate", eviscerate },
    { "Slice and Dice", slice_dice }, { "Rupture", rupture },
    { "Backstab", backstab }, { "Evasion", evasion },
    { "Kick", kick }, { "Sprint", sprint },
}

local function safe(fn)
    local ok, r = pcall(fn)
    if ok then return r end
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
    if not spell or not spellbook.ready() then return false end
    return spellbook.spell_known(spell)
end

local function as_pct(v)
    if type(v) ~= "number" then return nil end
    if v >= 0 and v <= 1.5 then return v * 100 end
    return v
end

local function health_pct(unit)
    local p = as_pct(safe(function() return unit:health_pct() end))
    if p then return p end
    local c = safe(function() return unit:get_health() end)
    local m = safe(function() return unit:get_max_health() end)
    if type(c) == "number" and type(m) == "number" and m > 0 then return (c / m) * 100 end
    return 100
end

local function cast_self(spell, player, label)
    if not spell or not player then return false end
    local ok = safe(function() return spell:cast_safe(player, label) end)
    if ok ~= true then ok = safe(function() return spell:cast(player, label) end) end
    if ok == true then rotation_note(label) return true end
    return false
end

local function cast_at(spell, target, label)
    if not spell or not target then return false end
    local ok = safe(function() return spell:cast_safe(target, label) end)
    if ok ~= true then ok = safe(function() return spell:cast(target, label) end) end
    if ok == true then rotation_note(label) return true end
    return false
end

local function has_aura(unit, ids)
    if not unit then return false end
    if safe(function() return unit:has_buff(ids) end) == true then return true end
    return safe(function() return unit:has_aura(ids) end) == true
end

--- Combo points on the current target. Without this the finisher logic is
--- guesswork, so a build that cannot report it simply never finishes.
---
--- combo_points_current is the documented name; get_combo_points_target also
--- exists and is kept as a fallback. get_combo_points(target), which this used
--- to try first, exists on neither - every call threw and was swallowed.
local function combo_points(player, target)
    local n = safe(function() return player:combo_points_current() end)
    if type(n) == "number" then return n end
    n = safe(function() return player:get_combo_points_target() end)
    if type(n) == "number" then return n end
    return nil
end

local debug_printed = false
local function debug_dump(player)
    if debug_printed or not gui.is_on("rogue_debug") then return end
    if not spellbook.ready() then return end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Rogue spell resolution:")
    for i = 1, #SPELL_LABELS do
        core.log(string.format("    %-18s %s", SPELL_LABELS[i][1],
            (SPELL_LABELS[i][2] and learned(SPELL_LABELS[i][2])) and "OK" or "not learned / unresolved"))
    end
    core.log("    combo points readable: " .. tostring(combo_points(player, nil) ~= nil))
    local enc = safe(function() return player:item_has_enchant(MAINHAND_SLOT) end)
    core.log("    main-hand poison present: " .. tostring(enc)
        .. "  (detection only - application has no API, see file header)")
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function rogue.class_id() return enums.class_id.ROGUE end
function rogue.label() return "Rogue" end
function rogue.combat_range(player) return 5 end

-- Pure melee with no ranged filler: stepping out is a flat DPS loss and the
-- target simply follows. Never retreats.
--- How far out to look for something to fight.
---
--- Melee has to walk into contact and then stand still, so a wide
--- scan only drags extra mobs into a fight it cannot kite out of.
function rogue.scan_range(player)
    return 20
end

function rogue.combat_profile()
    return {
        name = "rogue", melee_danger = 0, melee_safe = 0,
        should_retreat = function() return false end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
function rogue.register_gui(menu)
    local class_id = enums.class_id.ROGUE
    local function opt(label, spell, tip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tip }
    end
    menu:checkbox("mfg_sinister_strike", true, opt("Sinister Strike", sinister_strike))
    menu:checkbox("mfg_backstab", false, opt("Backstab", backstab,
        "Requires being behind the target; the movement controller does not position for it."))
    menu:checkbox("mfg_slice_dice", true, opt("Slice and Dice", slice_dice))
    menu:checkbox("mfg_rupture", false, opt("Rupture", rupture))
    menu:checkbox("mfg_eviscerate", true, opt("Eviscerate", eviscerate))
    menu:checkbox("mfg_evasion", true, opt("Evasion", evasion))
    menu:checkbox("mfg_kick", true, opt("Kick", kick))
    menu:slider_int("mfg_combo_finish", 2, 5, 4, {
        label = "Finish at combo points", tab = "class", class_id = class_id })
    menu:slider_int("mfg_evasion_pct", 10, 70, 35, {
        label = "Evasion below %", tab = "class", class_id = class_id })
    menu:checkbox("mfg_rogue_debug", false, {
        label = "Log spell resolution", tab = "class", class_id = class_id,
        tooltip = "Also reports whether combo points and weapon enchants are readable." })
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT
-- ----------------------------------------------------------------------------
function rogue.buffs_ooc(player)
    if not player then return false end
    if racials.ooc(player) then
        return true
    end
    debug_dump(player)
    -- Nothing to maintain out of combat: Slice and Dice needs combo points and
    -- poisons cannot be applied (see header). Kept so the interface is complete.
    return false
end

-- ----------------------------------------------------------------------------
-- COMBAT
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- RESTING
-- ----------------------------------------------------------------------------
--- Sit down and eat or drink. The thresholds are this class's to choose; the
--- machinery lives in resting.lua so a fix lands once rather than nine times.
function rogue.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function rogue.tick(player, target, ctx)
    if not player or not target then return false end
    ctx = ctx or {}

    -- Racials first: short cooldowns that only pay off while the fight is
    -- live, and none of them cost a global.
    if racials.tick(player, target, ctx) then
        return true
    end

    local hp = health_pct(player)
    if gui.is_on("evasion") and learned(evasion) then
        local pct = gui.slider("evasion_pct", 35) or 35
        if hp < pct and not has_aura(player, EVASION_IDS) then
            if cast_self(evasion, player, "Evasion") then return true end
        end
    end

    local dist = safe(function() return player:distance_to(target) end) or 99
    if dist > 5 then return false end

    if gui.is_on("kick") and learned(kick) then
        if safe(function() return target:is_casting() end) == true then
            if cast_at(kick, target, "Kick") then return true end
        end
    end

    local cp = combo_points(player, target)
    local finish_at = gui.slider("combo_finish", 4) or 4

    -- Finishers only when the build can actually report combo points. Spending
    -- blind would fire Eviscerate at 1 point and waste the whole build-up.
    if type(cp) == "number" and cp >= finish_at then
        if gui.is_on("slice_dice") and learned(slice_dice) and not has_aura(player, SND_IDS) then
            if cast_self(slice_dice, player, "Slice and Dice") then return true end
        end
        if gui.is_on("rupture") and learned(rupture) then
            if safe(function() return target:has_debuff(RUPTURE_IDS) end) ~= true then
                if cast_at(rupture, target, "Rupture") then return true end
            end
        end
        if gui.is_on("eviscerate") and learned(eviscerate) then
            if cast_at(eviscerate, target, "Eviscerate") then return true end
        end
    end

    if gui.is_on("backstab") and learned(backstab) then
        if cast_at(backstab, target, "Backstab") then return true end
    end
    if gui.is_on("sinister_strike") and learned(sinister_strike) then
        if cast_at(sinister_strike, target, "Sinister Strike") then return true end
    end
    return false
end

return rogue

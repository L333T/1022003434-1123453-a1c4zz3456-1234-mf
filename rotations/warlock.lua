-- ============================================================================
-- Master Farmer - Grindbot
-- Warlock grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Pet handling lives in pets.lua, shared with the Hunter.
--
-- SUMMONING COSTS A SHARD
--   Every summon except the Imp consumes a Soul Shard. The reference bot
--   summons without checking, so a shardless Warlock burns a GCD on a failing
--   cast every tick forever. can_summon() gates on the shard count, and the Imp
--   - which is free - is the fallback rather than the last resort.
--
-- ARMOUR IS ONE SLOT, NOT THREE
--   Fel Armor, Demon Armor and Demon Skin are the same buff slot. The source
--   tests each independently, so with two enabled they overwrite each other
--   every tick. Here the best known one is chosen and the others are not tried.
--
-- SPELL IDS
--   Highest rank first; mfg_warlock_debug prints what actually resolved.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type enums
local enums = require("common/enums")

local gui = require("gui")
local resting = require("resting")
local racials = require("racials")
local pets = require("pets")
local state = require("state")
local spellbook = require("spellbook")

local warlock = {}

local SOUL_SHARD_ID = 6265

local function make(ids, track_buff, track_debuff)
    local spell = izi.spell(ids)
    if not spell then return nil end
    if track_buff and spell.track_buff then spell:track_buff(ids) end
    if track_debuff and spell.track_debuff then spell:track_debuff(ids) end
    return spellbook.watch(spell)
end

local FEL_ARMOR_IDS   = { 28189, 28176 }
local DEMON_ARMOUR_IDS = { 27260, 11735, 11734, 11733, 1086, 706 }
local DEMON_SKIN_IDS  = { 696, 687 }
local ARMOUR_ANY = { 28189, 28176, 27260, 11735, 11734, 11733, 1086, 706, 696, 687 }

local CORRUPTION_IDS  = { 27216, 25311, 11672, 11671, 6222, 6223, 172 }
local AGONY_IDS       = { 27218, 11713, 11712, 11711, 1014, 980 }
local IMMOLATE_IDS    = { 27215, 25309, 11668, 11667, 6219, 1094, 348 }
local FUNNEL_IDS      = { 27259, 11694, 11693, 11692, 755 }

local fel_armor   = make(FEL_ARMOR_IDS, true, false)
local demon_armor = make(DEMON_ARMOUR_IDS, true, false)
local demon_skin  = make(DEMON_SKIN_IDS, true, false)

local summon_imp        = make({ 688 })
local summon_voidwalker = make({ 697 })
local summon_felhunter  = make({ 691 })
local summon_succubus   = make({ 712 })
local summon_felguard   = make({ 30146 })
local health_funnel     = make(FUNNEL_IDS, true, false)

local corruption  = make(CORRUPTION_IDS, false, true)
local curse_agony = make(AGONY_IDS, false, true)
local immolate    = make(IMMOLATE_IDS, false, true)
local shadow_bolt = make({ 27209, 25307, 11661, 11660, 11659, 7641, 1106, 1088, 705, 695, 686 })
local drain_life  = make({ 27219, 11700, 11699, 689 })
local life_tap    = make({ 27222, 11689, 11688, 11687, 1454 })

local SPELL_LABELS = {
    { "Fel Armor", fel_armor }, { "Demon Armor", demon_armor }, { "Demon Skin", demon_skin },
    { "Summon Imp", summon_imp }, { "Summon Voidwalker", summon_voidwalker },
    { "Summon Felhunter", summon_felhunter }, { "Summon Succubus", summon_succubus },
    { "Summon Felguard", summon_felguard }, { "Health Funnel", health_funnel },
    { "Corruption", corruption }, { "Curse of Agony", curse_agony },
    { "Immolate", immolate }, { "Shadow Bolt", shadow_bolt },
    { "Drain Life", drain_life }, { "Life Tap", life_tap },
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

local function mana_pct(player)
    local p = as_pct(safe(function() return player:mana_pct() end))
    if p then return p end
    local c = safe(function() return player:mana_current() end)
    local m = safe(function() return player:mana_max() end)
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

--- Soul shards carried. Summoning anything but the Imp costs one.
local function shard_count()
    local item = safe(function() return izi.item(SOUL_SHARD_ID) end)
    if item then
        local n = safe(function() return item:count() end)
        if type(n) == "number" then return n end
    end
    return 0
end

local debug_printed = false
local function debug_dump()
    if debug_printed or not gui.is_on("warlock_debug") then return end
    if not spellbook.ready() then return end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Warlock spell resolution:")
    for i = 1, #SPELL_LABELS do
        core.log(string.format("    %-20s %s", SPELL_LABELS[i][1],
            (SPELL_LABELS[i][2] and learned(SPELL_LABELS[i][2])) and "OK" or "not learned / unresolved"))
    end
    core.log("    soul shards carried: " .. tostring(shard_count()))
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function warlock.class_id() return enums.class_id.WARLOCK end
function warlock.label() return "Warlock" end
function warlock.combat_range(player) return 30 end

-- The pet holds threat, so backing out is usually a loss of cast time for
-- nothing. Retreat only when something is actually on US and the pet is not
-- there to take it back.
--- How far out to look for something to fight.
---
--- A caster opens from where it is already standing, so a wide
--- scan costs nothing and gives the rotation time to start a cast.
function warlock.scan_range(player)
    return 35
end

function warlock.combat_profile()
    return {
        name         = "warlock",
        melee_danger = 8,
        melee_safe   = 12,
        should_retreat = function(ctx)
            if not ctx or not ctx.target then return false end
            if ctx.melee_count < 1 then return false end
            return not pets.alive(ctx.player)
        end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
local PET_CHOICES = { "Imp", "Voidwalker", "Felhunter", "Succubus", "Felguard" }

function warlock.register_gui(menu)
    local class_id = enums.class_id.WARLOCK
    local function opt(label, spell, tip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tip }
    end
    menu:combobox("mfg_warlock_pet", 2, PET_CHOICES, {
        label = "Pet", tab = "class", class_id = class_id,
        tooltip = "Voidwalker is the safest unattended: it tanks. Everything but the Imp costs a Soul Shard." })
    menu:checkbox("mfg_warlock_armour", true, opt("Armour (best known)", fel_armor,
        "Fel Armor / Demon Armor / Demon Skin share one buff slot, so only the best known one is cast."))
    menu:checkbox("mfg_health_funnel", true, opt("Health Funnel", health_funnel))
    menu:checkbox("mfg_corruption", true, opt("Corruption", corruption))
    menu:checkbox("mfg_curse_agony", true, opt("Curse of Agony", curse_agony))
    menu:checkbox("mfg_immolate", false, opt("Immolate", immolate))
    menu:checkbox("mfg_shadow_bolt", true, opt("Shadow Bolt", shadow_bolt))
    menu:checkbox("mfg_drain_life", true, opt("Drain Life", drain_life,
        "Used as the self-heal when health drops."))
    menu:checkbox("mfg_life_tap", true, opt("Life Tap", life_tap,
        "Trade health for mana when mana is low and health is healthy."))
    menu:slider_int("mfg_warlock_heal_pct", 20, 80, 45, {
        label = "Drain Life below %", tab = "class", class_id = class_id })
    menu:checkbox("mfg_warlock_debug", false, {
        label = "Log spell resolution", tab = "class", class_id = class_id })
end

local function chosen_summon()
    local idx = tonumber(safe(function() return gui.combo("warlock_pet", 2) end)) or 2
    idx = math.floor(idx)
    if idx == 0 then idx = 1 end
    local order = { summon_imp, summon_voidwalker, summon_felhunter, summon_succubus, summon_felguard }
    local labels = { "Summon Imp", "Summon Voidwalker", "Summon Felhunter", "Summon Succubus", "Summon Felguard" }
    if idx < 1 or idx > #order then idx = 2 end

    -- Fall back to the Imp when the chosen pet is unknown or unaffordable. The
    -- Imp is free, so a shardless Warlock still gets a pet instead of retrying
    -- an impossible summon forever.
    if learned(order[idx]) and (idx == 1 or shard_count() > 0) then
        return order[idx], labels[idx], idx
    end
    if learned(summon_imp) then
        return summon_imp, "Summon Imp", 1
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT
-- ----------------------------------------------------------------------------
function warlock.buffs_ooc(player)
    if not player then return false end
    if racials.ooc(player) then
        return true
    end
    debug_dump()
    if safe(function() return player:is_in_combat() end) == true then return false end
    if safe(function() return player:is_mounted() end) == true then return false end

    pets.passive(player)

    local summon, label, idx = chosen_summon()
    if summon then
        local acted = pets.maintain(player, {
            summon = summon, summon_label = label,
            can_summon = function() return idx == 1 or shard_count() > 0 end,
            heal = gui.is_on("health_funnel") and health_funnel or nil,
            heal_ids = FUNNEL_IDS, heal_label = "Health Funnel",
            heal_pct = 50,
            learned = learned, cast_self = cast_self,
        })
        if acted then return true end
    end

    -- One armour slot: pick the best known, never try the others.
    if gui.is_on("warlock_armour") and not has_aura(player, ARMOUR_ANY) then
        if learned(fel_armor) then
            if cast_self(fel_armor, player, "Fel Armor") then return true end
        elseif learned(demon_armor) then
            if cast_self(demon_armor, player, "Demon Armor") then return true end
        elseif learned(demon_skin) then
            if cast_self(demon_skin, player, "Demon Skin") then return true end
        end
    end
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
function warlock.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function warlock.tick(player, target, ctx)
    if not player or not target then return false end
    ctx = ctx or {}

    -- Racials first: short cooldowns that only pay off while the fight is
    -- live, and none of them cost a global.
    if racials.tick(player, target, ctx) then
        return true
    end

    pets.attack(player, target)

    local hp = health_pct(player)
    local threshold = gui.slider("warlock_heal_pct", 45) or 45

    if gui.is_on("drain_life") and learned(drain_life) and hp < threshold then
        if cast_at(drain_life, target, "Drain Life") then return true end
    end

    -- Life Tap trades health for mana, so it must never run while low. Gating
    -- it above the heal threshold keeps the two from fighting each other.
    if gui.is_on("life_tap") and learned(life_tap) then
        if mana_pct(player) < 25 and hp > (threshold + 25) then
            if cast_self(life_tap, player, "Life Tap") then return true end
        end
    end

    local dist = safe(function() return player:distance_to(target) end) or 99
    if dist > warlock.combat_range(player) then return false end

    if gui.is_on("curse_agony") and learned(curse_agony) then
        if safe(function() return target:has_debuff(AGONY_IDS) end) ~= true then
            if cast_at(curse_agony, target, "Curse of Agony") then return true end
        end
    end
    if gui.is_on("corruption") and learned(corruption) then
        if safe(function() return target:has_debuff(CORRUPTION_IDS) end) ~= true then
            if cast_at(corruption, target, "Corruption") then return true end
        end
    end
    if gui.is_on("immolate") and learned(immolate) then
        if safe(function() return target:has_debuff(IMMOLATE_IDS) end) ~= true then
            if cast_at(immolate, target, "Immolate") then return true end
        end
    end
    if gui.is_on("shadow_bolt") and learned(shadow_bolt) then
        if cast_at(shadow_bolt, target, "Shadow Bolt") then return true end
    end
    return false
end

return warlock

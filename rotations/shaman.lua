-- ============================================================================
-- Master Farmer - Grindbot
-- Shaman grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- WEAPON IMBUES - THE BUG NOT COPIED
--   The reference bot tests MainHand_Enchant once, then casts EVERY enabled
--   imbue in sequence without re-checking. Enable two and they overwrite each
--   other on every tick, so the Shaman spends the whole fight re-imbuing and
--   never attacks. Here the imbue is a single CHOICE (a dropdown), and it is
--   only cast when unit:item_has_enchant reports the main hand is bare.
--
--   unit:item_has_enchant is what makes this checkable at all - it was the
--   blocker that kept Shaman out of earlier versions.
--
-- SPELL IDS
--   Highest rank first; mfg_shaman_debug prints what resolved.
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

local shaman = {}

local MAINHAND_SLOT = 16

local function make(ids, track_buff, track_debuff)
    local spell = izi.spell(ids)
    if not spell then return nil end
    if track_buff and spell.track_buff then spell:track_buff(ids) end
    if track_debuff and spell.track_debuff then spell:track_debuff(ids) end
    return spellbook.watch(spell)
end

local LIGHTNING_SHIELD_IDS = { 25469, 15208, 15207, 10432, 10431, 945, 8134, 324 }
local FLAME_SHOCK_IDS      = { 25457, 29228, 10448, 10447, 8053, 8052, 8050 }

-- Imbue order must match IMBUE_LABELS.
local IMBUE_IDS = {
    { 25485, 16316, 16315, 16314, 8019, 8018, 8017 },   -- Rockbiter
    { 25489, 16342, 16341, 16339, 8024 },               -- Flametongue
    { 25500, 16356, 16355, 16353, 8033 },               -- Frostbrand
    { 25505, 16362, 16361, 8232 },                      -- Windfury
}
local IMBUE_LABELS = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" }

local imbues = {}
for i = 1, #IMBUE_IDS do imbues[i] = make(IMBUE_IDS[i]) end

local lightning_shield = make(LIGHTNING_SHIELD_IDS, true, false)
local lightning_bolt = make({ 25449, 25448, 15208, 15207, 10392, 10391, 6041, 943, 915, 548, 529, 403 })
local earth_shock  = make({ 25454, 10414, 10413, 10412, 8046, 8045, 8044, 8042 })
local flame_shock  = make(FLAME_SHOCK_IDS, false, true)
local frost_shock  = make({ 25464, 10473, 10472, 8056 })
local stormstrike  = make({ 17364 })
local healing_wave = make({ 25396, 25357, 10396, 10395, 6497, 3980, 1064, 939, 913, 547, 332, 331 })

local SPELL_LABELS = {
    { "Lightning Shield", lightning_shield }, { "Lightning Bolt", lightning_bolt },
    { "Earth Shock", earth_shock }, { "Flame Shock", flame_shock },
    { "Frost Shock", frost_shock }, { "Stormstrike", stormstrike },
    { "Healing Wave", healing_wave },
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

--- Is the main hand carrying a temporary enchant right now?
--- Returns nil when the build cannot answer, which is treated as "do not
--- re-imbue" - guessing "bare" would re-cast every tick and never attack.
local function mainhand_imbued(player)
    local v = safe(function() return player:item_has_enchant(MAINHAND_SLOT) end)
    if type(v) == "boolean" then
        return v
    end
    local id = safe(function() return player:item_enchant_id(MAINHAND_SLOT) end)
    if type(id) == "number" then
        return id > 0
    end
    local exp = safe(function() return player:item_enchant_expiration(MAINHAND_SLOT) end)
    if type(exp) == "number" then
        return exp > 0
    end
    return nil
end

local debug_printed = false
local function debug_dump(player)
    if debug_printed or not gui.is_on("shaman_debug") then return end
    if not spellbook.ready() then return end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Shaman spell resolution:")
    for i = 1, #IMBUE_LABELS do
        core.log(string.format("    %-20s %s", IMBUE_LABELS[i],
            (imbues[i] and learned(imbues[i])) and "OK" or "not learned / unresolved"))
    end
    for i = 1, #SPELL_LABELS do
        core.log(string.format("    %-20s %s", SPELL_LABELS[i][1],
            (SPELL_LABELS[i][2] and learned(SPELL_LABELS[i][2])) and "OK" or "not learned / unresolved"))
    end
    local st = mainhand_imbued(player)
    core.log("    main hand enchant readable: " .. (st == nil and "NO - imbues disabled" or ("YES (" .. tostring(st) .. ")")))
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function shaman.class_id() return enums.class_id.SHAMAN end
function shaman.label() return "Shaman" end

function shaman.combat_range(player)
    if gui.is_on("enhancement") then return 5 end
    return 30
end

--- How far out to look for something to fight.
---
--- Melee has to walk into contact and then stand still, so a wide scan just
--- drags extra mobs into a fight it cannot kite out of. At range the pull
--- starts from where the bot is already standing, so the extra warning is
--- free. This class does both, so the scan follows the same toggle its
--- combat range does.
function shaman.scan_range(player)
    if gui.is_on("enhancement") then
        return 20
    end
    return 35
end

function shaman.combat_profile()
    local melee = gui.is_on("enhancement")
    return {
        name         = "shaman",
        melee_danger = melee and 0 or 8,
        melee_safe   = melee and 0 or 12,
        -- Enhancement wants to BE in melee, so it never retreats. Elemental has
        -- no snare worth the global, so kiting costs more cast time than it saves.
        should_retreat = function() return false end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
function shaman.register_gui(menu)
    local class_id = enums.class_id.SHAMAN
    local function opt(label, spell, tip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tip }
    end
    -- One choice, not four toggles: see the header. Two enabled imbues overwrite
    -- each other every tick in the source.
    menu:combobox("mfg_shaman_imbue", 1, IMBUE_LABELS, {
        label = "Weapon Imbue", tab = "class", class_id = class_id,
        tooltip = "Only one imbue can be on a weapon, so this is a single choice." })
    menu:checkbox("mfg_enhancement", false, opt("Enhancement (melee)", stormstrike,
        "Fight in melee and use Stormstrike instead of holding range."))
    menu:checkbox("mfg_lightning_shield", true, opt("Lightning Shield", lightning_shield))
    menu:checkbox("mfg_flame_shock", true, opt("Flame Shock", flame_shock))
    menu:checkbox("mfg_earth_shock", false, opt("Earth Shock", earth_shock))
    menu:checkbox("mfg_frost_shock", false, opt("Frost Shock", frost_shock))
    menu:checkbox("mfg_lightning_bolt", true, opt("Lightning Bolt", lightning_bolt))
    menu:checkbox("mfg_healing_wave", true, opt("Healing Wave", healing_wave))
    menu:slider_int("mfg_shaman_heal_pct", 20, 80, 50, {
        label = "Self-heal below %", tab = "class", class_id = class_id })
    menu:checkbox("mfg_shaman_debug", false, {
        label = "Log spell resolution", tab = "class", class_id = class_id,
        tooltip = "Also reports whether the main-hand enchant is readable on this build." })
end

local function chosen_imbue()
    local idx = tonumber(safe(function() return gui.combo("shaman_imbue", 1) end)) or 1
    idx = math.floor(idx)
    if idx == 0 then idx = 1 end
    if idx < 1 or idx > #IMBUE_IDS then idx = 1 end
    return imbues[idx], IMBUE_LABELS[idx]
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT
-- ----------------------------------------------------------------------------
function shaman.buffs_ooc(player)
    if not player then return false end
    if racials.ooc(player) then
        return true
    end
    debug_dump(player)
    if safe(function() return player:is_in_combat() end) == true then return false end
    if safe(function() return player:is_mounted() end) == true then return false end

    -- Only re-imbue when the weapon is provably bare. nil means the build
    -- cannot answer, and re-casting blind would loop forever.
    local imbued = mainhand_imbued(player)
    if imbued == false then
        local spell, label = chosen_imbue()
        if spell and learned(spell) then
            if cast_self(spell, player, label) then return true end
        end
    end

    if gui.is_on("lightning_shield") and learned(lightning_shield) then
        if not has_aura(player, LIGHTNING_SHIELD_IDS) then
            if cast_self(lightning_shield, player, "Lightning Shield") then return true end
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
function shaman.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function shaman.tick(player, target, ctx)
    if not player or not target then return false end
    ctx = ctx or {}

    -- Racials first: short cooldowns that only pay off while the fight is
    -- live, and none of them cost a global.
    if racials.tick(player, target, ctx) then
        return true
    end

    local hp = health_pct(player)
    local threshold = gui.slider("shaman_heal_pct", 50) or 50
    if gui.is_on("healing_wave") and learned(healing_wave) and hp < threshold then
        if cast_self(healing_wave, player, "Healing Wave") then return true end
    end

    local dist = safe(function() return player:distance_to(target) end) or 99
    local melee = gui.is_on("enhancement")

    if melee then
        if dist > 5 then return false end
        if learned(stormstrike) and cast_at(stormstrike, target, "Stormstrike") then return true end
    elseif dist > 30 then
        return false
    end

    if gui.is_on("flame_shock") and learned(flame_shock) then
        if safe(function() return target:has_debuff(FLAME_SHOCK_IDS) end) ~= true then
            if cast_at(flame_shock, target, "Flame Shock") then return true end
        end
    end
    if gui.is_on("earth_shock") and learned(earth_shock) then
        if cast_at(earth_shock, target, "Earth Shock") then return true end
    end
    if gui.is_on("frost_shock") and learned(frost_shock) then
        if cast_at(frost_shock, target, "Frost Shock") then return true end
    end
    if not melee and gui.is_on("lightning_bolt") and learned(lightning_bolt) then
        if cast_at(lightning_bolt, target, "Lightning Bolt") then return true end
    end
    return false
end

return shaman

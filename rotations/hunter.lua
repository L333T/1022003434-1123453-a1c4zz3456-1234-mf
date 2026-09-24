-- ============================================================================
-- Master Farmer - Grindbot
-- Hunter grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Pet handling lives in pets.lua, shared with the Warlock.
--
-- THE DEAD ZONE
--   A Hunter cannot shoot inside roughly 8 yards and its melee is weak, so the
--   combat profile keeps the target OUT, not in. This is the only class here
--   whose melee_danger means "too close to shoot" rather than "about to die",
--   which is why it is the only one that retreats unconditionally when closed
--   on - see combat_profile.
--
-- SPELL IDS
--   Highest rank first. A wrong id fails CLOSED but silently; mfg_hunter_debug
--   prints what the scanner actually resolved. Run it once before trusting the
--   rotation.
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

local hunter = {}

local function make(ids, track_buff, track_debuff)
    local spell = izi.spell(ids)
    if not spell then return nil end
    if track_buff and spell.track_buff then spell:track_buff(ids) end
    if track_debuff and spell.track_debuff then spell:track_debuff(ids) end
    return spellbook.watch(spell)
end

local HAWK_IDS      = { 27044, 25296, 14322, 14321, 14320, 13165 }
local TRUESHOT_IDS  = { 27066, 20906, 19506 }
local MARK_IDS      = { 27065, 14325, 14324, 14323, 1130 }
local SERPENT_IDS   = { 27016, 25295, 13555, 13554, 13553, 13552, 13551, 13550, 13549, 1978 }
local MEND_IDS      = { 27046, 13544, 13543, 13542, 3662, 3661, 3111, 136 }

local aspect_hawk = make(HAWK_IDS, true, false)
local trueshot    = make(TRUESHOT_IDS, true, false)
local call_pet    = make({ 883 })
local revive_pet  = make({ 982 })
local mend_pet    = make(MEND_IDS, true, false)

local hunters_mark = make(MARK_IDS, false, true)
local serpent_sting = make(SERPENT_IDS, false, true)
local auto_shot   = make({ 75 })
local steady_shot = make({ 34120 })
local arcane_shot = make({ 27019, 14287, 14286, 14285, 14284, 14283, 14282, 14281, 3044 })
local multi_shot  = make({ 27021, 25294, 14290, 14289, 14288, 2643 })
local concussive  = make({ 5116 })
local raptor_strike = make({ 27014, 14266, 14265, 14264, 14263, 14262, 14261, 14260, 2973 })

local SPELL_LABELS = {
    { "Aspect of the Hawk", aspect_hawk }, { "Trueshot Aura", trueshot },
    { "Call Pet", call_pet }, { "Revive Pet", revive_pet }, { "Mend Pet", mend_pet },
    { "Hunter's Mark", hunters_mark }, { "Serpent Sting", serpent_sting },
    { "Auto Shot", auto_shot }, { "Steady Shot", steady_shot },
    { "Arcane Shot", arcane_shot }, { "Multi-Shot", multi_shot },
    { "Concussive Shot", concussive }, { "Raptor Strike", raptor_strike },
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

local debug_printed = false
local function debug_dump()
    if debug_printed or not gui.is_on("hunter_debug") then return end
    if not spellbook.ready() then return end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Hunter spell resolution:")
    for i = 1, #SPELL_LABELS do
        core.log(string.format("    %-20s %s", SPELL_LABELS[i][1],
            (SPELL_LABELS[i][2] and learned(SPELL_LABELS[i][2])) and "OK" or "not learned / unresolved"))
    end
    core.log("    pet happiness readable: " .. tostring(pets.happiness() ~= nil))
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function hunter.class_id() return enums.class_id.HUNTER end
function hunter.label() return "Hunter" end
function hunter.combat_range(player) return 34 end

-- The dead zone: a Hunter cannot shoot inside ~8 yards. Unlike every other
-- caster here, being closed on is a DPS problem rather than a survival one, and
-- the pet is holding threat anyway - so this retreats whenever something is in
-- melee, with no profile condition to satisfy.
--- How far out to look for something to fight.
---
--- A hunter pulls at range and has a pet to hold what it pulls,
--- so it wants the same warning a caster does.
function hunter.scan_range(player)
    return 35
end

function hunter.combat_profile()
    return {
        name         = "hunter",
        melee_danger = 8,
        melee_safe   = 14,
        should_retreat = function(ctx)
            if not ctx or not ctx.target then return false end
            return ctx.melee_count >= 1 or ctx.distance <= 8
        end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
function hunter.register_gui(menu)
    local class_id = enums.class_id.HUNTER
    local function opt(label, spell, tip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tip }
    end
    menu:checkbox("mfg_aspect_hawk", true, opt("Aspect of the Hawk", aspect_hawk))
    menu:checkbox("mfg_trueshot", true, opt("Trueshot Aura", trueshot))
    menu:checkbox("mfg_hunter_pet", true, opt("Summon / Revive Pet", call_pet))
    menu:checkbox("mfg_mend_pet", true, opt("Mend Pet", mend_pet))
    menu:checkbox("mfg_hunters_mark", true, opt("Hunter's Mark", hunters_mark))
    menu:checkbox("mfg_serpent_sting", true, opt("Serpent Sting", serpent_sting))
    menu:checkbox("mfg_arcane_shot", true, opt("Arcane Shot", arcane_shot))
    menu:checkbox("mfg_steady_shot", true, opt("Steady Shot", steady_shot))
    menu:checkbox("mfg_multi_shot", false, opt("Multi-Shot (2+)", multi_shot))
    menu:checkbox("mfg_concussive", false, opt("Concussive Shot", concussive,
        "Snare something that closes into the dead zone."))
    menu:slider_int("mfg_pet_heal_pct", 20, 90, 50, {
        label = "Mend Pet below %", tab = "class", class_id = class_id })
    menu:checkbox("mfg_hunter_debug", false, {
        label = "Log spell resolution", tab = "class", class_id = class_id,
        tooltip = "Prints once which Hunter spells resolved, and whether pet happiness is readable." })
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT
-- ----------------------------------------------------------------------------
function hunter.buffs_ooc(player)
    if not player then return false end
    if racials.ooc(player) then
        return true
    end
    debug_dump()
    if safe(function() return player:is_in_combat() end) == true then return false end
    if safe(function() return player:is_mounted() end) == true then return false end

    -- Park the pet first. An aggressive pet pulls packs while the bot paths,
    -- which is the main way an unattended Hunter dies.
    pets.passive(player)

    if gui.is_on("hunter_pet") then
        local acted = pets.maintain(player, {
            summon = call_pet, summon_label = "Call Pet",
            revive = revive_pet,
            heal = gui.is_on("mend_pet") and mend_pet or nil,
            heal_ids = MEND_IDS,
            heal_label = "Mend Pet",
            heal_pct = gui.slider("pet_heal_pct", 50) or 50,
            learned = learned, cast_self = cast_self,
            min_level = 10,
        })
        if acted then return true end
    end

    if gui.is_on("aspect_hawk") and learned(aspect_hawk) and not has_aura(player, HAWK_IDS) then
        if cast_self(aspect_hawk, player, "Aspect of the Hawk") then return true end
    end
    if gui.is_on("trueshot") and learned(trueshot) and not has_aura(player, TRUESHOT_IDS) then
        if cast_self(trueshot, player, "Trueshot Aura") then return true end
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
function hunter.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function hunter.tick(player, target, ctx)
    if not player or not target then return false end
    ctx = ctx or {}

    -- Racials first: short cooldowns that only pay off while the fight is
    -- live, and none of them cost a global.
    if racials.tick(player, target, ctx) then
        return true
    end

    pets.attack(player, target)

    local dist = safe(function() return player:distance_to(target) end) or 99

    -- Inside the dead zone shooting is impossible. Snare and let the movement
    -- controller open the gap rather than trading melee swings we lose.
    if dist <= 8 then
        if gui.is_on("concussive") and learned(concussive) then
            if cast_at(concussive, target, "Concussive Shot") then return true end
        end
        if learned(raptor_strike) then
            if cast_at(raptor_strike, target, "Raptor Strike") then return true end
        end
        return false
    end

    if dist > hunter.combat_range(player) then return false end

    if gui.is_on("hunters_mark") and learned(hunters_mark) then
        if safe(function() return target:has_debuff(MARK_IDS) end) ~= true then
            if cast_at(hunters_mark, target, "Hunter's Mark") then return true end
        end
    end
    if gui.is_on("serpent_sting") and learned(serpent_sting) then
        if safe(function() return target:has_debuff(SERPENT_IDS) end) ~= true then
            if cast_at(serpent_sting, target, "Serpent Sting") then return true end
        end
    end
    if gui.is_on("multi_shot") and learned(multi_shot) then
        local pack = (ctx.enemies and #ctx.enemies) or 0
        if pack >= 2 and cast_at(multi_shot, target, "Multi-Shot") then return true end
    end
    if gui.is_on("arcane_shot") and learned(arcane_shot) then
        if cast_at(arcane_shot, target, "Arcane Shot") then return true end
    end
    if gui.is_on("steady_shot") and learned(steady_shot) then
        if cast_at(steady_shot, target, "Steady Shot") then return true end
    end
    if learned(auto_shot) then
        if cast_at(auto_shot, target, "Auto Shot") then return true end
    end
    return false
end

return hunter

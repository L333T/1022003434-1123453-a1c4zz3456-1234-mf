-- ============================================================================
-- Master Farmer - Grindbot
-- Priest grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Ported from the reference grindbot's Buff_Check Priest branch, which kept
-- only Power Word: Fortitude and Shadowform. That is not enough to level with,
-- so this adds a shadow-leaning filler rotation and self-healing.
--
-- Two things the source does that are NOT copied:
--   * it casts Shadowform unconditionally whenever the spell is known.
--     Shadowform locks out every healing spell, so here it is behind a GUI
--     toggle that defaults OFF.
--   * it has no self-heal at all. A priest that cannot heal itself while
--     grinding dies to any two-pull.
--
-- SPELL IDS
--   Rank arrays are highest-rank-first, matching rotations/mage.lua. A wrong ID
--   fails CLOSED - spellbook reports the spell as not learned and it is simply
--   never cast - but it fails silently, so `mfg_priest_debug` logs which of
--   these the scanner actually resolved. Turn it on once after any ID edit.
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

local priest = {}

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

local PWF_IDS        = { 25389, 10938, 10937, 2791, 1245, 1244, 1243 }
local INNER_FIRE_IDS = { 25431, 10952, 10951, 1006, 602, 7128, 588 }
local SHADOWFORM_IDS = { 15473 }
local SWP_IDS        = { 25368, 25367, 10894, 10893, 10892, 2767, 992, 970, 594, 589 }
local RENEW_IDS      = { 25222, 25221, 25315, 10929, 10928, 10927, 6078, 6077, 6076, 6075, 6074, 139 }
local PWS_IDS        = { 25218, 25217, 10901, 10900, 10899, 10898, 6066, 6065, 3747, 600, 592, 17 }

local pw_fortitude = make(PWF_IDS, true, false)
local inner_fire   = make(INNER_FIRE_IDS, true, false)
local shadowform   = make(SHADOWFORM_IDS, true, false)
local power_word_shield = make(PWS_IDS, true, false)

local shadow_word_pain = make(SWP_IDS, false, true)
local mind_blast = make({ 25375, 25372, 10947, 10946, 10945, 8106, 8105, 8104, 8103, 8102, 8092 })
local mind_flay  = make({ 25387, 18807, 17314, 17313, 17312, 17311, 15407 })
local smite      = make({ 25364, 25363, 10934, 10933, 6060, 1004, 984, 598, 591, 585 })
local renew      = make(RENEW_IDS, true, false)
local flash_heal = make({ 25235, 25233, 10917, 10916, 10915, 9474, 9473, 9472, 2061 })
local lesser_heal = make({ 2053, 2052, 2050 })

local SPELL_LABELS = {
    { "Power Word: Fortitude", pw_fortitude },
    { "Inner Fire",            inner_fire },
    { "Shadowform",            shadowform },
    { "Power Word: Shield",    power_word_shield },
    { "Shadow Word: Pain",     shadow_word_pain },
    { "Mind Blast",            mind_blast },
    { "Mind Flay",             mind_flay },
    { "Smite",                 smite },
    { "Renew",                 renew },
    { "Flash Heal",            flash_heal },
    { "Lesser Heal",           lesser_heal },
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
    if not spell then
        return false
    end
    if not spellbook.ready() then
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

local function mana_pct(player)
    local pct = as_pct(safe(function() return player:mana_pct() end))
    if pct then
        return pct
    end
    local cur = safe(function() return player:mana_current() end)
    local mx = safe(function() return player:mana_max() end)
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
-- Wrong spell IDs fail closed and silently. This prints, once, exactly which of
-- the arrays above the scanner resolved, so a bad ID is visible instead of
-- looking like "the spell just never fires".
local debug_printed = false

local function debug_dump()
    if debug_printed or not gui.is_on("priest_debug") then
        return
    end
    if not spellbook.ready() then
        return
    end
    debug_printed = true
    core.log("[Master Farmer - Grindbot] Priest spell resolution:")
    for i = 1, #SPELL_LABELS do
        local name, spell = SPELL_LABELS[i][1], SPELL_LABELS[i][2]
        local mark = "not learned / unresolved"
        if spell and learned(spell) then
            mark = "OK"
        end
        core.log(string.format("    %-24s %s", name, mark))
    end
end

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
function priest.class_id()
    return enums.class_id.PRIEST
end

function priest.label()
    return "Priest"
end

function priest.combat_range(player)
    local flay = mind_flay
    if flay and type(flay.maximum_range) == "number" and flay.maximum_range > 0 then
        return flay.maximum_range
    end
    return 30
end

-- ----------------------------------------------------------------------------
-- MOVEMENT PROFILE
-- ----------------------------------------------------------------------------
-- The movement controller owns positioning; this only supplies the rules.
-- A priest has no reliable snare or root while levelling, so backing out of
-- melee mid-fight just eats damage with no cast time gained. Retreat only when
-- something is actually on us AND we are healthy enough to survive the walk.
--- How far out to look for something to fight.
---
--- A caster opens from where it is already standing, so a wide
--- scan costs nothing and gives the rotation time to start a cast.
function priest.scan_range(player)
    return 35
end

function priest.combat_profile()
    return {
        name         = "priest",
        melee_danger = 8,
        melee_safe   = 12,
        should_retreat = function(ctx)
            if not ctx or not ctx.target then
                return false
            end
            if ctx.melee_count < 1 and ctx.distance > 8 then
                return false
            end
            local player = ctx.player
            if player and health_pct(player) < 35 then
                return false        -- too low to kite; stand and fight or heal
            end
            return false            -- no snare available: kiting is a net loss
        end,
    }
end

-- ----------------------------------------------------------------------------
-- GUI
-- ----------------------------------------------------------------------------
function priest.register_gui(menu)
    local class_id = enums.class_id.PRIEST
    local function opt(label, spell, tooltip)
        return { label = label, tab = "class", class_id = class_id, spell = spell, tooltip = tooltip }
    end
    menu:checkbox("mfg_pw_fortitude", true, opt("Power Word: Fortitude", pw_fortitude))
    menu:checkbox("mfg_inner_fire", true, opt("Inner Fire", inner_fire))
    menu:checkbox("mfg_shadowform", false, opt("Shadowform", shadowform,
        "Off by default: Shadowform locks out every healing spell, including the self-heals below."))
    menu:checkbox("mfg_pw_shield", true, opt("Power Word: Shield", power_word_shield,
        "Shield when health drops, if Weakened Soul has expired."))
    menu:checkbox("mfg_swp", true, opt("Shadow Word: Pain", shadow_word_pain))
    menu:checkbox("mfg_mind_blast", true, opt("Mind Blast", mind_blast))
    menu:checkbox("mfg_mind_flay", true, opt("Mind Flay", mind_flay))
    menu:checkbox("mfg_smite", true, opt("Smite", smite,
        "Filler when Mind Flay is unavailable or Shadowform is off."))
    menu:checkbox("mfg_renew", true, opt("Renew", renew))
    menu:checkbox("mfg_flash_heal", true, opt("Flash Heal", flash_heal))
    menu:slider_int("mfg_priest_heal_pct", 20, 80, 50, {
        label = "Self-heal below %",
        tab = "class",
        class_id = class_id,
    })
    menu:checkbox("mfg_priest_debug", false, {
        label = "Log spell resolution",
        tab = "class",
        class_id = class_id,
        tooltip = "Prints once which Priest spells the scanner resolved. Use after editing spell IDs.",
    })
end

-- ----------------------------------------------------------------------------
-- OUT OF COMBAT BUFFS
-- ----------------------------------------------------------------------------
function priest.buffs_ooc(player)
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

    if gui.is_on("pw_fortitude") and learned(pw_fortitude) then
        if not has_aura(player, PWF_IDS) then
            if cast_self(pw_fortitude, player, "Power Word: Fortitude") then
                return true
            end
        end
    end

    if gui.is_on("inner_fire") and learned(inner_fire) then
        if not has_aura(player, INNER_FIRE_IDS) then
            if cast_self(inner_fire, player, "Inner Fire") then
                return true
            end
        end
    end

    -- Deliberately last, and off by default. Entering Shadowform makes every
    -- heal below uncastable, so it must never pre-empt a buff the player can
    -- still use while healing.
    if gui.is_on("shadowform") and learned(shadowform) then
        if not has_aura(player, SHADOWFORM_IDS) then
            if cast_self(shadowform, player, "Shadowform") then
                return true
            end
        end
    end

    return false
end

-- ----------------------------------------------------------------------------
-- COMBAT
-- ----------------------------------------------------------------------------
-- Weakened Soul blocks a re-shield; without checking it the bot would spam
-- Power Word: Shield into a guaranteed failure every tick.
local WEAKENED_SOUL = { 6788 }

local function try_survival(player)
    local hp = health_pct(player)
    local threshold = gui.slider("priest_heal_pct", 50) or 50

    if gui.is_on("pw_shield") and learned(power_word_shield) and hp < 70 then
        if not has_aura(player, PWS_IDS) and not has_aura(player, WEAKENED_SOUL) then
            if cast_self(power_word_shield, player, "Power Word: Shield") then
                return true
            end
        end
    end

    if hp >= threshold then
        return false
    end

    -- Shadowform blocks healing entirely; do not burn the GCD trying.
    if has_aura(player, SHADOWFORM_IDS) then
        return false
    end

    if gui.is_on("renew") and learned(renew) and not has_aura(player, RENEW_IDS) then
        if cast_self(renew, player, "Renew") then
            return true
        end
    end
    if gui.is_on("flash_heal") and learned(flash_heal) then
        if cast_self(flash_heal, player, "Flash Heal") then
            return true
        end
    end
    if learned(lesser_heal) then
        if cast_self(lesser_heal, player, "Lesser Heal") then
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
function priest.rest(player)
    return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
end

function priest.tick(player, target, ctx)
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

    local yards = priest.combat_range(player)
    local dist = safe(function() return player:distance_to(target) end) or 99
    if dist > yards then
        return false
    end

    -- Dot first: it keeps ticking while we close, and re-applying early wastes
    -- the remaining duration, so only cast when the debuff is actually absent.
    if gui.is_on("swp") and learned(shadow_word_pain) then
        if safe(function() return target:has_debuff(SWP_IDS) end) ~= true then
            if cast_at(shadow_word_pain, target, "Shadow Word: Pain") then
                return true
            end
        end
    end

    if gui.is_on("mind_blast") and learned(mind_blast) then
        if cast_at(mind_blast, target, "Mind Blast") then
            return true
        end
    end

    if gui.is_on("mind_flay") and learned(mind_flay) then
        if cast_at(mind_flay, target, "Mind Flay") then
            return true
        end
    end

    if gui.is_on("smite") and learned(smite) then
        if cast_at(smite, target, "Smite") then
            return true
        end
    end

    return false
end

return priest

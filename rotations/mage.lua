-- ============================================================================
-- Master Farmer - Grindbot
-- Mage grind filler + OOC buffs (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- Spell rank-1 IDs are registered with spellbook.define. The scanner saves the
-- highest known rank and Class-tab toggles feed izi.advanced_sequence.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type enums
local enums = require("common/enums")

---@type spell_queue
local spell_queue = require("common/modules/spell_queue")

---@type spell_helper
local spell_helper = require("common/utility/spell_helper")

---@type spell_prediction
local spell_prediction = require("common/modules/spell_prediction")

local consumables = require("data/consumables")
local gui = require("gui")
local state = require("state")
local spellbook = require("spellbook")
local targeting = require("targeting")

local movement_mod = nil

local function get_movement()
    if movement_mod then
        return movement_mod
    end
    local ok, movement = pcall(require, "movement")
    if ok then
        movement_mod = movement
        return movement
    end
    return nil
end

local mage = {}

-- Highest rank first. Conjured IDs from Orca, then vendor food/water.
local FOOD_ITEM_IDS = consumables.FOOD_ITEM_IDS
local WATER_ITEM_IDS = consumables.WATER_ITEM_IDS

local item_by_id = {}

local function item_of(id)
    if type(id) ~= "number" then
        return nil
    end
    local cached = item_by_id[id]
    if cached then
        return cached
    end
    local item = izi.item(id)
    if item then
        item_by_id[id] = item
    end
    return item
end

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

local frostbolt = make({ 27072, 27071, 25304, 10181, 10180, 10179, 8408, 8407, 8406, 7322, 837, 205, 116 })
local fireball = make({ 27070, 25306, 10151, 10150, 10149, 10148, 8402, 8401, 8400, 3140, 145, 143, 133 })
local arcane_missiles = make({ 38704, 38699, 27075, 25345, 10212, 10211, 8417, 8416, 5145, 5144, 5143 })
local fire_blast = make({ 27079, 27078, 10199, 10197, 8413, 8412, 2138, 2137, 2136 })
local scorch = make({ 27074, 27073, 10207, 10206, 10205, 8446, 8445, 8444, 2948 })
local pyroblast = make({ 33938, 27132, 18809, 12526, 12525, 12524, 12523, 12522, 12505, 11366 })
local flamestrike = make({ 27086, 10216, 10215, 8423, 8422, 2121, 2120 })
local blizzard = make({ 27085, 10187, 10186, 10185, 8427, 6141, 10 })
local cone_of_cold = make({ 27087, 10161, 10160, 10159, 8492, 120 })
local frost_nova = make({ 27088, 10230, 6131, 865, 122 }, false, true)
local ice_lance = make({ 30455 })
local blast_wave = make({ 11113 })
local dragons_breath = make({ 33043, 33041, 31661 })
local ice_barrier = make({ 33405, 27134, 13033, 13032, 13031, 11426 }, true, false)
local ICE_BARRIER_IDS = { 33405, 27134, 13033, 13032, 13031, 11426 }
local mana_shield = make({ 27131, 10193, 10192, 10191, 8495, 8494, 1463 }, true, false)
local ice_armor = make({ 27124, 10220, 10219, 7320, 7302 }, true, false)
local frost_armor = make({ 7301, 7300, 168 }, true, false)
local mage_armor = make({ 27125, 22783, 22782, 6117 }, true, false)
local molten_armor = make({ 30482 }, true, false)
local arcane_intellect = make({ 27126, 10157, 10156, 1461, 1460, 1459 }, true, false)
local icy_veins = make({ 12472 }, true, false)
local evocation = make({ 12051 }, true, false)
local counterspell = make({ 2139 })
local presence_of_mind = make({ 12043 }, true, false)
local combustion = make({ 11129 }, true, false)
local arcane_power = make({ 12042 }, true, false)
local water_elemental = make({ 31687 })
local freeze = make({ 33395 })
local cold_snap = make({ 11958 })
local conjure_water = make(consumables.CONJURE_WATER_SPELL_IDS)
local conjure_food = make(consumables.CONJURE_FOOD_SPELL_IDS)

spellbook.define({
    frostbolt = 116,
    fireball = 133,
    arcane_missiles = 5143,
    fire_blast = 2136,
    scorch = 2948,
    pyroblast = 11366,
    flamestrike = 2120,
    blizzard = 10,
    cone_of_cold = 120,
    frost_nova = 122,
    ice_lance = 30455,
    blast_wave = 11113,
    dragons_breath = 31661,
    ice_barrier = 11426,
    mana_shield = 1463,
    ice_armor = 7302,
    frost_armor = 168,
    mage_armor = 6117,
    molten_armor = 30482,
    arcane_intellect = 1459,
    icy_veins = 12472,
    evocation = 12051,
    counterspell = 2139,
    presence_of_mind = 12043,
    combustion = 11129,
    arcane_power = 12042,
    water_elemental = 31687,
    freeze = 33395,
    cold_snap = 11958,
    conjure_water = 5504,
    conjure_food = 587,
})

local ARMOR_ANY = {
    27124, 10220, 10219, 7320, 7302,
    7301, 7300, 168,
    27125, 22783, 22782, 6117,
    30482,
}

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function cancel_sequences()
    if type(izi.is_sequence_active) == "function" and izi.is_sequence_active() ~= true then
        return
    end
    if izi.sequence and type(izi.sequence.cancel_all) == "function" then
        pcall(function()
            izi.sequence:cancel_all()
        end)
        return
    end
    if type(izi.cancel_sequence) == "function" then
        pcall(function()
            izi.cancel_sequence()
        end)
    end
end

local function learned(spell)
    if type(spell) == "string" then
        return spellbook.has(spell)
    end
    if not spell then
        return false
    end
    if not spellbook.ready() then
        return false
    end
    return spellbook.spell_known(spell)
end

local function live(key, fallback)
    local sp = spellbook.spell(key)
    if sp then
        return sp
    end
    return fallback
end

local function castable(spell, unit)
    if not spell then
        return false
    end
    if unit then
        return safe(function()
            return spell:is_castable_to_unit(unit)
        end) == true
    end
    return safe(function()
        return spell:is_castable()
    end) == true
end

local function rotation_note(text)
    local ok, rotation = pcall(require, "rotation")
    if ok and rotation and type(rotation.set_last_action) == "function" then
        rotation.set_last_action(text)
    end
    state.last_action = text
end

local function mana_percent(player)
    local pct = safe(function() return player:mana_pct() end)
    if type(pct) == "number" then
        if pct >= 0 and pct <= 1.5 then
            return pct * 100
        end
        return pct
    end
    local cur = safe(function() return player:mana_current() end)
    local mx = safe(function() return player:mana_max() end)
    if type(cur) == "number" and type(mx) == "number" and mx > 0 then
        return (cur / mx) * 100
    end
    return 100
end

local function shield_down(player, ids)
    if not player then
        return false
    end
    if safe(function() return player:has_buff(ids) end) == true then
        return false
    end
    if safe(function() return player:has_aura(ids) end) == true then
        return false
    end
    return true
end

local function cast_self_buff(spell, player, label)
    if not spell or not player then
        return false
    end
    local ok = safe(function()
        return spell:cast_safe(player, label)
    end)
    if ok == true then
        rotation_note(label)
        return true
    end
    ok = safe(function()
        return spell:cast(player, label)
    end)
    if ok == true then
        rotation_note(label)
        return true
    end
    return false
end

local function try_ice_barrier(player)
    if gui.is_on("ice_barrier") ~= true or not player then
        return false
    end
    if not ice_barrier then
        ice_barrier = make(ICE_BARRIER_IDS, true, false)
    end
    if not ice_barrier then
        return false
    end
    if not shield_down(player, ICE_BARRIER_IDS) then
        return false
    end
    local cd_up = safe(function()
        return ice_barrier:cooldown_up()
    end)
    if cd_up == false then
        return false
    end
    return cast_self_buff(ice_barrier, player, "Ice Barrier")
end

local function spell_pause_sec(spell, fallback)
    local ms = safe(function()
        return spell:cast_time_ms()
    end)
    if type(ms) == "number" and ms == ms and ms > 0 then
        return (ms / 1000) + 0.2
    end
    local ct = safe(function()
        return spell:cast_time()
    end)
    if type(ct) == "number" and ct == ct and ct > 0 then
        if ct > 20 then
            return (ct / 1000) + 0.2
        end
        return ct + 0.2
    end
    return fallback
end

local function pause_cast(target, spell)
    local movement = get_movement()
    if not movement or type(movement.prepare_cast) ~= "function" then
        return
    end
    movement.prepare_cast(target, spell_pause_sec(spell, 0.5))
end

local function pause_channel(target, spell, fallback)
    local movement = get_movement()
    if not movement or type(movement.prepare_channel) ~= "function" then
        return
    end
    movement.prepare_channel(target, spell_pause_sec(spell, fallback or 3.0))
end

local function pause_ground(pos, spell, channel, fallback)
    local movement = get_movement()
    if not movement or type(movement.prepare_ground) ~= "function" then
        return
    end
    movement.prepare_ground(pos, spell_pause_sec(spell, fallback or 0.5), channel == true)
end

local function cast_self(spell, player, label)
    if not spell or not player then
        return false
    end
    pause_cast(player, spell)
    local ok = safe(function()
        return spell:cast_safe(player, label)
    end)
    if ok == true then
        rotation_note(label)
        return true
    end
    local movement = get_movement()
    if movement and type(movement.release) == "function" then
        movement.release()
    end
    return false
end

local function cast_unit(spell, target, label)
    if not spell or not target then
        return false
    end
    pause_cast(target, spell)
    local ok = safe(function()
        return spell:cast_safe(target, label)
    end)
    if ok == true then
        rotation_note(label)
        return true
    end
    local movement = get_movement()
    if movement and type(movement.release) == "function" then
        movement.release()
    end
    return false
end

local function cast_channel(spell, target, label, fallback)
    if not spell or not target then
        return false
    end
    pause_channel(target, spell, fallback)
    local ok = safe(function()
        return spell:cast_safe(target, label)
    end)
    if ok == true then
        rotation_note(label)
        return true
    end
    local movement = get_movement()
    if movement and type(movement.release) == "function" then
        movement.release()
    end
    return false
end

local function cast_pos(spell, pos, label, channel, fallback)
    if not spell or not pos then
        return false
    end
    pause_ground(pos, spell, channel, fallback)
    local ok = safe(function()
        return spell:cast_position(pos, label, { min_hits = 2, aoe_radius = 8 })
    end)
    if ok == true then
        rotation_note(label)
        return true
    end
    local movement = get_movement()
    if movement and type(movement.release) == "function" then
        movement.release()
    end
    return false
end

local last_blizzard_queue = 0
local BLIZZARD_RADIUS = 8
local BLIZZARD_RANGE = 30

local function blizzard_spell_id()
    local ranked = spellbook.best_id("blizzard")
    if type(ranked) == "number" and ranked > 0 then
        return ranked
    end
    if not blizzard then
        return nil
    end
    local id = safe(function()
        return blizzard:id()
    end)
    if type(id) == "number" and id > 0 then
        return id
    end
    return 10
end

local function blizzard_cast_time()
    local ct = 0.2
    if not blizzard then
        return ct
    end
    local raw = safe(function()
        return blizzard:cast_time()
    end)
    if type(raw) == "number" and raw > 0 then
        if raw > 20 then
            ct = raw / 1000
        else
            ct = raw
        end
        if ct < 0.2 then
            ct = 0.2
        end
    end
    return ct
end

local function cast_blizzard_most_hits(player, target)
    if not player or not target or not blizzard then
        return false
    end
    if safe(function() return player:is_channeling_or_casting() end) == true then
        return true
    end
    local now = izi.now()
    if (now - last_blizzard_queue) < 0.25 then
        return false
    end
    local sid = blizzard_spell_id()
    if type(sid) ~= "number" then
        return false
    end
    local player_position = safe(function()
        return player:get_position()
    end)
    if not player_position then
        return false
    end
    local range = BLIZZARD_RANGE
    if type(blizzard.maximum_range) == "number" and blizzard.maximum_range > 0 then
        range = blizzard.maximum_range
    end
    local pred_type = spell_prediction.prediction_type
    local geo_type = spell_prediction.geometry_type
    if type(pred_type) ~= "table" or type(geo_type) ~= "table" then
        return false
    end
    local spell_data = spell_prediction:new_spell_data(
        sid,
        range,
        BLIZZARD_RADIUS,
        blizzard_cast_time(),
        0.0,
        pred_type.MOST_HITS,
        geo_type.CIRCLE,
        player_position
    )
    if not spell_data then
        return false
    end
    local castable = safe(function()
        return spell_helper:is_spell_castable(sid, player, target, false, false)
    end) == true
    if not castable then
        return false
    end
    local prediction_result = spell_prediction:get_cast_position(target, spell_data)
    if not prediction_result then
        return false
    end
    local hits = prediction_result.amount_of_hits
    if type(hits) ~= "number" or hits < 2 then
        return false
    end
    local pos = prediction_result.cast_position
    if not pos then
        return false
    end
    pause_ground(pos, blizzard, true, 8.0)
    local queued = pcall(function()
        spell_queue:queue_spell_position(sid, pos, 1, "Blizzard most hits")
    end)
    if queued ~= true then
        local movement = get_movement()
        if movement and type(movement.release) == "function" then
            movement.release()
        end
        return false
    end
    last_blizzard_queue = now
    rotation_note("Blizzard")
    return true
end

local seq_player = nil
local seq_target = nil
local seq_dist = 99
local seq_pack = 0
local seq_frozen = false
local seq_gen = -1

local function seq_unit_ok(unit)
    if not unit then
        return false
    end
    return safe(function() return unit:is_valid() end) == true
end

local function seq_enemy()
    if seq_unit_ok(seq_target) then
        if safe(function() return seq_target:is_valid_enemy() end) == true then
            return seq_target
        end
        return seq_target
    end
    local t = izi.ts()
    if seq_unit_ok(t) then
        return t
    end
    return nil
end

local function seq_me()
    if seq_unit_ok(seq_player) then
        return seq_player
    end
    return izi.me()
end

local function enabled(key)
    return gui.is_on(key) == true
end

local function cond_self(key, fallback)
    return function()
        if not enabled(key) then
            return false
        end
        local sp = live(key, fallback)
        local me = seq_me()
        if not sp or not me then
            return false
        end
        if not learned(key) and not learned(sp) then
            return false
        end
        return safe(function()
            return sp:is_castable_to_unit(me)
        end) == true or safe(function()
            return sp:is_castable()
        end) == true
    end
end

local function cond_target(key, fallback, max_dist, extra)
    return function()
        if not enabled(key) then
            return false
        end
        local sp = live(key, fallback)
        local unit = seq_enemy()
        if not sp or not unit then
            return false
        end
        if type(max_dist) == "number" and seq_dist > max_dist then
            return false
        end
        if extra and extra() ~= true then
            return false
        end
        if not learned(key) and not learned(sp) then
            return false
        end
        return safe(function()
            return sp:is_castable_to_unit(unit)
        end) == true
    end
end

local function start_mage_sequence()
    if type(izi.is_sequence_active) == "function" and izi.is_sequence_active() then
        return true
    end
    if type(izi.is_sequence_on_cooldown) == "function" and izi.is_sequence_on_cooldown() then
        return false
    end
    local me = seq_me()
    local unit = seq_enemy()
    if not me or not unit then
        return false
    end
    local entries = {
        {
            spell = live("icy_veins", icy_veins),
            target = function() return seq_me() end,
            condition = cond_self("icy_veins", icy_veins),
        },
        {
            spell = live("presence_of_mind", presence_of_mind),
            target = function() return seq_me() end,
            condition = cond_self("presence_of_mind", presence_of_mind),
        },
        {
            spell = live("combustion", combustion),
            target = function() return seq_me() end,
            condition = cond_self("combustion", combustion),
        },
        {
            spell = live("arcane_power", arcane_power),
            target = function() return seq_me() end,
            condition = cond_self("arcane_power", arcane_power),
        },
        {
            spell = live("fire_blast", fire_blast),
            target = function() return seq_enemy() end,
            condition = cond_target("fire_blast", fire_blast, 19),
        },
        {
            spell = live("ice_lance", ice_lance),
            target = function() return seq_enemy() end,
            condition = cond_target("ice_lance", ice_lance, 35, function()
                return seq_frozen == true
            end),
        },
        {
            spell = live("cone_of_cold", cone_of_cold),
            target = function() return seq_enemy() end,
            condition = cond_target("cone", cone_of_cold, 8),
        },
        {
            spell = live("pyroblast", pyroblast),
            target = function() return seq_enemy() end,
            condition = cond_target("pyroblast", pyroblast, 30),
        },
        {
            spell = live("dragons_breath", dragons_breath),
            target = function() return seq_enemy() end,
            condition = cond_target("dragons_breath", dragons_breath, 8),
        },
        {
            spell = live("blast_wave", blast_wave),
            target = function() return seq_enemy() end,
            condition = cond_target("blast_wave", blast_wave, 8),
        },
        {
            spell = live("frostbolt", frostbolt),
            target = function() return seq_enemy() end,
            condition = cond_target("frostbolt", frostbolt, 34),
        },
        {
            spell = live("scorch", scorch),
            target = function() return seq_enemy() end,
            condition = cond_target("scorch", scorch, 29),
        },
        {
            spell = live("arcane_missiles", arcane_missiles),
            target = function() return seq_enemy() end,
            condition = cond_target("arcane_missiles", arcane_missiles, 29),
        },
        {
            spell = live("fireball", fireball),
            target = function() return seq_enemy() end,
            condition = cond_target("fireball", fireball, 34),
        },
    }
    local ready = {}
    for i = 1, #entries do
        local e = entries[i]
        if e.spell then
            ready[#ready + 1] = e
        end
    end
    if #ready < 1 then
        return false
    end
    if type(izi.advanced_sequence) ~= "function" then
        return false
    end
    local started = izi.advanced_sequence(ready, {
        timeout = 12.0,
        cooldown = 0,
        debug_name = "Mage Rotation",
        is_flexible_order = true,
    })
    if started then
        seq_gen = spellbook.generation()
        rotation_note("Mage sequence")
        return true
    end
    return false
end

function mage.class_id()
    return enums.class_id.MAGE
end

function mage.label()
    return "Mage"
end

function mage.preferred_food_ids()
    return FOOD_ITEM_IDS
end

function mage.preferred_drink_ids()
    return WATER_ITEM_IDS
end

function mage.combat_range(player)
    local bolt = live("frostbolt", frostbolt)
    if bolt and type(bolt.maximum_range) == "number" and bolt.maximum_range > 0 then
        return bolt.maximum_range
    end
    local ball = live("fireball", fireball)
    if ball and type(ball.maximum_range) == "number" and ball.maximum_range > 0 then
        return ball.maximum_range
    end
    return 30
end

function mage.register_gui(menu)
    local class_id = enums.class_id.MAGE
    local function opt(label, spell)
        return { label = label, tab = "class", class_id = class_id, spell = spell }
    end
    menu:checkbox("mfg_mage_wand", true, {
        label = "Use Wand",
        tab = "class",
        class_id = class_id,
        tooltip = "When mana is below 5% and a wand is equipped, pause spells and auto-attack with Wand or Melee.",
    })
    menu:checkbox("mfg_ice_armor", true, opt("Ice / Frost Armor", { ice_armor, frost_armor }))
    menu:checkbox("mfg_mage_armor", false, opt("Mage Armor", mage_armor))
    menu:checkbox("mfg_molten_armor", false, opt("Molten Armor", molten_armor))
    menu:checkbox("mfg_ice_barrier", true, {
        label = "Ice Barrier",
        tab = "class",
        class_id = class_id,
        tooltip = "Keep Ice Barrier up in combat and out of combat when the checkbox is on.",
    })
    menu:checkbox("mfg_mana_shield", false, opt("Mana Shield", mana_shield))
    menu:checkbox("mfg_icy_veins", true, opt("Icy Veins", icy_veins))
    menu:checkbox("mfg_presence_of_mind", true, opt("Presence of Mind", presence_of_mind))
    menu:checkbox("mfg_combustion", false, opt("Combustion", combustion))
    menu:checkbox("mfg_arcane_power", false, opt("Arcane Power", arcane_power))
    menu:checkbox("mfg_frostbolt", true, opt("Frostbolt", frostbolt))
    menu:checkbox("mfg_fireball", true, opt("Fireball", fireball))
    menu:checkbox("mfg_scorch", false, opt("Scorch", scorch))
    menu:checkbox("mfg_arcane_missiles", false, opt("Arcane Missiles", arcane_missiles))
    menu:checkbox("mfg_pyroblast", false, opt("Pyroblast", pyroblast))
    menu:checkbox("mfg_fire_blast", true, opt("Fire Blast", fire_blast))
    menu:checkbox("mfg_frost_nova", true, opt("Frost Nova", frost_nova))
    menu:checkbox("mfg_ice_lance", true, opt("Ice Lance (on freeze)", ice_lance))
    menu:checkbox("mfg_cone", false, opt("Cone of Cold", cone_of_cold))
    menu:checkbox("mfg_flamestrike", false, opt("Flamestrike (2+)", flamestrike))
    menu:checkbox("mfg_blizzard", false, opt("Blizzard (2+)", blizzard))
    menu:checkbox("mfg_blast_wave", false, opt("Blast Wave", blast_wave))
    menu:checkbox("mfg_dragons_breath", false, opt("Dragon's Breath", dragons_breath))
    menu:checkbox("mfg_water_ele", true, opt("Summon Water Elemental", water_elemental))
    menu:checkbox("mfg_counterspell", true, opt("Counterspell", counterspell))
end

function mage.buffs_ooc(player)
    if not player then
        return false
    end
    if safe(function() return player:is_in_combat() end) == true then
        return false
    end
    if safe(function() return player:is_mounted() end) == true then
        return false
    end
    if try_ice_barrier(player) then
        return true
    end
    if gui.is_on("ice_armor") then
        local has_armor = safe(function() return player:has_buff(ARMOR_ANY) end) == true
        if not has_armor then
            if learned(ice_armor) and cast_self(ice_armor, player, "Ice Armor") then
                return true
            end
            if learned(frost_armor) and cast_self(frost_armor, player, "Frost Armor") then
                return true
            end
        end
    end
    if gui.is_on("mage_armor") and learned(mage_armor) then
        if safe(function() return player:has_buff({ 27125, 22783, 22782, 6117 }) end) ~= true then
            if cast_self(mage_armor, player, "Mage Armor") then
                return true
            end
        end
    end
    if gui.is_on("molten_armor") and learned(molten_armor) then
        if safe(function() return player:has_buff({ 30482 }) end) ~= true then
            if cast_self(molten_armor, player, "Molten Armor") then
                return true
            end
        end
    end
    if learned(arcane_intellect) then
        if safe(function() return player:has_buff({ 27127, 23028, 27126, 10157, 10156, 1461, 1460, 1459 }) end) ~= true then
            if cast_self(arcane_intellect, player, "Arcane Intellect") then
                return true
            end
        end
    end
    local food_ok = true
    local drink_ok = true
    if type(mage.preferred_food_ids) == "function" then
        local ids = mage.preferred_food_ids()
        food_ok = false
        for i = 1, #ids do
            local item = item_of(ids[i])
            if item and item:count() >= 10 then
                food_ok = true
                break
            end
        end
    end
    if type(mage.preferred_drink_ids) == "function" then
        local ids = mage.preferred_drink_ids()
        drink_ok = false
        for i = 1, #ids do
            local item = item_of(ids[i])
            if item and item:count() >= 10 then
                drink_ok = true
                break
            end
        end
    end
    if not drink_ok and learned(conjure_water) then
        local threat = false
        local ok_t, targeting = pcall(require, "targeting")
        if ok_t and targeting and type(targeting.threat_nearby) == "function" then
            threat = targeting.threat_nearby(player, 50) == true
        end
        if not threat then
            local mv = get_movement()
            if mv and type(mv.stop) == "function" then
                mv.stop()
            end
            if cast_self(conjure_water, player, "Conjure Water") then
                return true
            end
        end
    end
    if not food_ok and learned(conjure_food) then
        local threat = false
        local ok_t, targeting = pcall(require, "targeting")
        if ok_t and targeting and type(targeting.threat_nearby) == "function" then
            threat = targeting.threat_nearby(player, 50) == true
        end
        if not threat then
            local mv = get_movement()
            if mv and type(mv.stop) == "function" then
                mv.stop()
            end
            if cast_self(conjure_food, player, "Conjure Food") then
                return true
            end
        end
    end
    return false
end

function mage.tick(player, target, ctx)
    if not player or not target then
        return false
    end
    ctx = ctx or {}
    local no_move = ctx.no_move == true
    local now = izi.now()
    if state.combat.kite_until > 0 then
        if now < state.combat.kite_until then
            return true
        end
        pcall(function()
            core.input.move_backward_stop()
        end)
        state.combat.kite_until = 0
    end

    local dist = safe(function() return player:distance_to(target) end) or 99
    local mana = mana_percent(player)
    local enemies = (ctx and ctx.enemies) or {}
    local pack = #enemies
    local yards = mage.combat_range(player)
    local movement_mod = get_movement()
    local los = safe(function() return player:los_to(target) end)
    if los ~= true and type(izi.is_los) == "function" then
        local izi_los = safe(function() return izi.is_los(player, target) end)
        if izi_los == true then
            los = true
        elseif izi_los == false then
            los = false
        end
    end
    local fight_ready = (dist <= yards and los ~= false)
    if movement_mod and type(movement_mod.in_fight_range) == "function" then
        local ready, range, has_los = movement_mod.in_fight_range(player, target, yards)
        fight_ready = ready == true
        if type(range) == "number" then
            dist = range
        end
        los = has_los
    end

    seq_player = player
    seq_target = target
    seq_dist = dist
    seq_pack = pack
    seq_frozen = safe(function()
        local ranks = spellbook.ranks("frost_nova")
        if type(ranks) == "table" and #ranks > 0 then
            return target:has_debuff(ranks) or target:has_debuff({ 33395 })
        end
        return target:has_debuff({ 27088, 10230, 6131, 865, 122, 33395 })
    end) == true

    if try_ice_barrier(player) then
        return true
    end

    if learned(evocation) and mana <= 20 then
        if safe(function() return player:has_buff({ 12051 }) end) ~= true then
            if cast_self(live("evocation", evocation), player, "Evocation") then
                return true
            end
        end
    end

    if gui.is_on("mana_shield") and learned(mana_shield) then
        local shield = live("mana_shield", mana_shield)
        if safe(function() return player:has_buff(spellbook.ranks("mana_shield") or { 27131, 10193, 10192, 10191, 8495, 8494, 1463 }) end) ~= true then
            if cast_self(shield, player, "Mana Shield") then
                return true
            end
        end
    end

    if gui.is_on("counterspell") and learned(counterspell) and dist <= 30 then
        if safe(function() return target:is_channeling_or_casting() end) == true then
            if safe(function() return player:los_to(target) end) ~= false then
                if cast_unit(live("counterspell", counterspell), target, "Counterspell") then
                    return true
                end
            end
        end
    end

    if gui.is_on("flamestrike") and pack >= 2 and dist < 29 and learned(flamestrike) then
        if (now - state.combat.nova_at) >= 10 then
            local pos = safe(function() return target:get_position() end)
            if pos and cast_pos(live("flamestrike", flamestrike), pos, "Flamestrike", false, 2.0) then
                state.combat.nova_at = now
                return true
            end
        end
    end

    if gui.is_on("frost_nova") and dist < 10 and learned(frost_nova) and castable(live("frost_nova", frost_nova)) then
        local nova = live("frost_nova", frost_nova)
        local ok = safe(function()
            return nova:cast_safe(player, "Frost Nova")
        end)
        if ok == true then
            rotation_note("Frost Nova")
            if no_move then
                return true
            end
            state.combat.kite_until = now + 1.25
            local movement = get_movement()
            if movement then
                if type(movement.release) == "function" then
                    movement.release()
                end
                movement.stop()
            end
            pcall(function()
                core.input.move_backward_start()
            end)
            pcall(function()
                izi.after(1.25, function()
                    pcall(function()
                        core.input.move_backward_stop()
                    end)
                    state.combat.kite_until = 0
                end)
            end)
            return true
        end
    end

    if not fight_ready then
        cancel_sequences()
        if targeting and type(targeting.start_auto_attack) == "function" then
            targeting.start_auto_attack(player, target)
        end
        if no_move then
            return true
        end
        if movement_mod and type(movement_mod.chase_unit) == "function" then
            movement_mod.chase_unit(player, target, yards)
        end
        return true
    end
    if not no_move then
        if movement_mod and type(movement_mod.face_combat) == "function" then
            movement_mod.face_combat(target)
        end
    end

    if targeting and type(targeting.should_use_wand) == "function" and targeting.should_use_wand(player) then
        cancel_sequences()
        targeting.start_auto_attack(player, target)
        rotation_note("Wand / melee")
        return true
    end

    if gui.is_on("blizzard") and pack >= 2 and dist < 35 and learned(blizzard) then
        if cast_blizzard_most_hits(player, target) then
            return true
        end
    end

    local pet = safe(function() return player:get_pet() end)
    local pet_ok = pet and safe(function() return pet:is_valid() end) == true and safe(function() return pet:is_dead_or_ghost() end) ~= true
    if gui.is_on("water_ele") and learned(water_elemental) and not pet_ok and dist <= 30 then
        if cast_self(live("water_elemental", water_elemental), player, "Water Elemental") then
            return true
        end
    elseif pet_ok then
        pcall(function()
            core.input.pet_attack(target)
        end)
        if learned(freeze) and dist <= 30 and castable(live("freeze", freeze), target) then
            if cast_unit(live("freeze", freeze), target, "Freeze") then
                return true
            end
        end
    elseif gui.is_on("water_ele") and learned(cold_snap) and learned(water_elemental) and dist <= 30 then
        if cast_self(live("cold_snap", cold_snap), player, "Cold Snap") then
            return true
        end
    end

    if type(izi.is_sequence_active) == "function" and izi.is_sequence_active() then
        if seq_gen ~= spellbook.generation() then
            cancel_sequences()
        else
            return true
        end
    end
    return start_mage_sequence()
end

return mage

-- ============================================================================
-- Master Farmer - Grindbot
-- Enemy scan, tap filter, player detect, corpse list
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.38
-- Folder: Master_Farmer_Grindbot_v1.3.38
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type unit_helper
local unit_helper = require("common/utility/unit_helper")

---@type auto_attack_helper
local auto_attack = require("common/utility/auto_attack_helper")

---@type enums
local enums = require("common/enums")

local gui = require("gui")
local state = require("state")

local targeting = {}

local OBJ_CACHE_GAP = 0.50
local obj_cache_t = -1
local obj_cache_list = nil

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function all_objects()
    local now = izi.now()
    if obj_cache_list and (now - obj_cache_t) < OBJ_CACHE_GAP then
        return obj_cache_list
    end
    local objects = core.object_manager.get_visible_objects()
    if type(objects) == "table" then
        obj_cache_list = objects
        obj_cache_t = now
        return objects
    end
    return nil
end

function targeting.cache_player(player)
    if not player then
        return nil
    end
    local pos = safe(function() return player:get_position() end)
    state.cached_pos = pos
    state.cached_now = izi.now()
    return pos
end

local function tap_denied(unit)
    local v = safe(function() return unit:is_tap_denied() end)
    if v == true then
        return true
    end
    if type(v) == "number" and v ~= 0 then
        return true
    end
    return false
end

local function player_nearby(player, range)
    if not gui.is_on("player_detect") then
        return false
    end
    local yards = gui.slider("player_yards", 30)
    local list = izi.enemies(range or 40, true)
    if type(list) ~= "table" then
        return false
    end
    for i = 1, #list do
        local u = list[i]
        if u and safe(function() return u:is_player() end) == true then
            local d = safe(function() return player:distance_to(u) end)
            if type(d) == "number" and d <= yards then
                return true
            end
        end
    end
    return false
end

local function id_wanted(npc_id, mobs)
    if type(mobs) ~= "table" or #mobs == 0 then
        return true
    end
    for i = 1, #mobs do
        if mobs[i] == npc_id then
            return true
        end
    end
    return false
end

local function enemy_units(player, pos, range)
    if pos then
        local around = safe(function()
            return unit_helper:get_enemy_list_around(pos, range, true, false, false, false)
        end)
        if type(around) == "table" and #around > 0 then
            return around
        end
    end
    local list = safe(function()
        return izi.enemies(range)
    end)
    if type(list) == "table" then
        return list
    end
    return {}
end

function targeting.find_mobs(player, mobs, range, pve_only, opts)
    local found = {}
    if not player then
        return found
    end
    opts = opts or {}
    range = tonumber(range) or 50
    if range > 80 then
        range = 80
    end
    if player_nearby(player, range) then
        return found
    end
    local pos = state.cached_pos or safe(function() return player:get_position() end)
    if not pos then
        return found
    end
    local list = enemy_units(player, pos, range)
    local ok_mv, movement = pcall(require, "movement")
    if not ok_mv then
        movement = nil
    end
    local skip_reach = opts.skip_reach == true
    local my_level = safe(function() return player:get_level() end) or 1
    local band = gui.attack_level_band()
    local untapped = gui.is_on("untapped")
    for i = 1, #list do
        local u = list[i]
        if u and safe(function() return u:is_valid() end) == true then
            local skip = false
            if safe(function() return u:is_dead_or_ghost() end) == true then
                skip = true
            elseif safe(function() return u:is_dead() end) == true then
                skip = true
            end
            if (not skip) and pve_only == true then
                if safe(function() return u:is_player() end) == true then
                    skip = true
                end
                if (not skip) and safe(function() return u:is_dummy() end) == true then
                    skip = true
                end
            end
            if not skip then
                local guid = safe(function() return u:get_guid() end)
                if (not state.was_killed(guid)) and not (state.is_unreachable and state.is_unreachable(guid)) then
                    local npc_id = safe(function() return u:get_npc_id() end) or 0
                    local lvl = safe(function() return u:get_level() end) or 1
                    local diff = lvl - my_level
                    local level_ok = true
                    if type(band) == "number" then
                        level_ok = diff >= -band and diff <= band
                    end
                    if id_wanted(npc_id, mobs) and level_ok then
                        if (not untapped) or (not tap_denied(u)) then
                            if safe(function() return player:can_attack(u) end) ~= false then
                                local upos = safe(function() return u:get_position() end)
                                local reach_ok = upos ~= nil
                                if (not skip_reach) and reach_ok and movement and type(movement.can_reach) == "function" then
                                    reach_ok = movement.can_reach(pos, upos) == true
                                end
                                if reach_ok then
                                    found[#found + 1] = u
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return found
end

function targeting.threat_nearby(player, yards)
    if not player then
        return false
    end
    yards = tonumber(yards) or 50
    local pos = state.cached_pos or safe(function() return player:get_position() end)
    if not pos then
        return false
    end
    local list = enemy_units(player, pos, yards)
    if type(list) ~= "table" then
        return false
    end
    for i = 1, #list do
        local u = list[i]
        if u and safe(function() return u:is_valid() end) == true then
            if safe(function() return u:is_dead_or_ghost() end) ~= true then
                if safe(function() return u:is_player() end) ~= true then
                    if safe(function() return u:is_dummy() end) ~= true then
                        if safe(function() return player:can_attack(u) end) ~= false then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function targeting.combat_scan(player, range)
    local found = {}
    if not player then
        return found
    end
    local pos = state.cached_pos or safe(function() return player:get_position() end)
    if not pos then
        return found
    end
    local list = enemy_units(player, pos, range or 40)
    if type(list) ~= "table" then
        return found
    end
    local me_guid = safe(function() return player:get_guid() end)
    for i = 1, #list do
        local u = list[i]
        if u and safe(function() return u:is_in_combat() end) == true and safe(function() return u:is_dead_or_ghost() end) ~= true then
            local tar = safe(function() return u:get_target() end)
            local tguid = tar and safe(function() return tar:get_guid() end)
            if me_guid ~= nil and tguid == me_guid then
                found[#found + 1] = u
            end
        end
    end
    return found
end

function targeting.find_corpses(player, range)
    if not player or type(izi.enemies_if) ~= "function" then
        return {}
    end
    local yards = range or 10
    if type(yards) ~= "number" or yards < 1 then
        yards = 10
    end
    local ok, list = pcall(izi.enemies_if, yards, function(enemy)
        if not enemy then
            return false
        end
        local ok_valid, valid = pcall(enemy.is_valid, enemy)
        if not ok_valid or valid ~= true then
            return false
        end
        local ok_dead, dead = pcall(enemy.is_dead, enemy)
        return ok_dead == true and dead == true
    end)
    if not ok or type(list) ~= "table" then
        return {}
    end
    return list
end

function targeting.nearest(player, units)
    local best = nil
    local best_d = 9999
    if not player or type(units) ~= "table" then
        return nil
    end
    for i = 1, #units do
        local u = units[i]
        local d = safe(function() return player:distance_to(u) end)
        if type(d) == "number" and d < best_d then
            best_d = d
            best = u
        end
    end
    return best, best_d
end

local function as_percent(value, current, maximum)
    if type(value) == "number" then
        if value >= 0 and value <= 1.5 then
            return value * 100
        end
        return value
    end
    if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
        return (current / maximum) * 100
    end
    return 100
end

local RANGED_SLOT = 18 -- INVSLOT_RANGED (equipment slots 1-19)
local WAND_MANA = 5
local wand_eq_until = 0
local wand_eq_val = false

local function mana_percent(player)
    local pct = safe(function() return player:mana_pct() end)
    local cur = safe(function() return player:mana_current() end)
    local mx = safe(function() return player:mana_max() end)
    return as_percent(pct, cur, mx)
end

local function ranged_item_id(player)
    local info = safe(function()
        return player:get_item_at_inventory_slot(RANGED_SLOT)
    end)
    if type(info) ~= "table" or not info.object then
        return nil
    end
    local id = safe(function()
        return info.object:get_item_id()
    end)
    if type(id) == "number" and id > 0 then
        return id
    end
    return nil
end

local function item_is_wand(item_id)
    local info = safe(function()
        return core.quests.get_item_info(item_id)
    end)
    if type(info) ~= "table" then
        return nil
    end
    local loc = info.equip_loc
    if loc == "INVTYPE_RANGEDRIGHT" then
        return true
    end
    if loc == "INVTYPE_RANGED" or loc == "INVTYPE_THROWN" then
        return false
    end
    local sub = info.item_sub_type
    if type(sub) == "string" then
        if string.find(string.lower(sub), "wand", 1, true) then
            return true
        end
    end
    return nil
end

function targeting.has_wand_equipped(player)
    if not player then
        return false
    end
    local now = izi.now()
    if now < wand_eq_until then
        return wand_eq_val
    end
    wand_eq_until = now + 2
    wand_eq_val = false
    local id = ranged_item_id(player)
    if not id then
        return false
    end
    local wand = item_is_wand(id)
    if wand == true then
        wand_eq_val = true
        return true
    end
    if wand == false then
        return false
    end
    local class_id = safe(function() return player:get_class() end)
    if class_id == enums.class_id.MAGE or class_id == enums.class_id.PRIEST or class_id == enums.class_id.WARLOCK then
        wand_eq_val = true
        return true
    end
    return false
end

function targeting.should_use_wand(player)
    if not player then
        return false
    end
    if gui.is_on("mage_wand") ~= true then
        return false
    end
    if mana_percent(player) >= WAND_MANA then
        return false
    end
    return targeting.has_wand_equipped(player)
end

local function is_attacking(player)
    return safe(function()
        return auto_attack:is_auto_attacking(player)
    end) == true
end

local function start_attack_type(unit, attack_type)
    if type(attack_type) ~= "number" then
        return false
    end
    return safe(function()
        return auto_attack:start_attack(unit, attack_type)
    end) == true
end

local function stop_attack_type(unit, attack_type)
    if type(attack_type) ~= "number" then
        return
    end
    safe(function()
        return auto_attack:stop_attack(unit, attack_type)
    end)
end

local function in_melee(player, unit)
    if safe(function() return unit:is_in_melee_range(5) end) == true then
        return true
    end
    local d = safe(function() return player:distance_to(unit) end)
    return type(d) == "number" and d <= 5
end

local function start_wand_or_melee(player, unit, types)
    if is_attacking(player) then
        return true
    end
    if type(types) ~= "table" then
        return false
    end
    if in_melee(player, unit) then
        if start_attack_type(unit, types.MELEE) then
            return true
        end
        return start_attack_type(unit, types.WAND)
    end
    if start_attack_type(unit, types.WAND) then
        return true
    end
    return start_attack_type(unit, types.MELEE)
end

function targeting.start_auto_attack(player, unit)
    if not player or not unit then
        return false
    end
    local types = auto_attack.ATTACK_TYPE
    if type(types) ~= "table" or type(types.MELEE) ~= "number" then
        return false
    end
    pcall(function()
        core.input.set_target(unit)
    end)
    local attacking = safe(function() return auto_attack:is_auto_attacking(player) end) == true
    local current = safe(function() return player:get_target() end)
    local same = false
    if current and attacking then
        local cg = safe(function() return current:get_guid() end)
        local ug = safe(function() return unit:get_guid() end)
        same = cg ~= nil and cg == ug
    end
    if same ~= true then
        start_attack_type(unit, types.MELEE)
    end
    if targeting.should_use_wand(player) then
        start_wand_or_melee(player, unit, types)
    end
    return true
end

function targeting.set_current(unit, kind)
    if not unit then
        state.reset_target()
        return
    end
    local pos = safe(function() return unit:get_position() end)
    state.target.unit = unit
    state.target.guid = safe(function() return unit:get_guid() end)
    state.target.kind = kind
    if pos then
        state.target.x = pos.x
        state.target.y = pos.y
        state.target.z = pos.z
    end
    pcall(function()
        core.input.set_target(unit)
    end)
end

local function names_match(got, want)
    if type(got) ~= "string" or type(want) ~= "string" or want == "" then
        return false
    end
    if got == want then
        return true
    end
    return string.lower(got) == string.lower(want)
end

function targeting.find_named(player, name_a, name_b, range)
    if not player then
        return nil
    end
    local objects = all_objects()
    if type(objects) ~= "table" then
        return nil
    end
    local best = nil
    local best_d = range or 80
    for i = 1, #objects do
        local obj = objects[i]
        if obj and safe(function() return obj:is_valid() end) == true then
            if safe(function() return obj:is_dead_or_ghost() end) ~= true then
                local got = safe(function() return obj:get_name() end)
                if names_match(got, name_a) or names_match(got, name_b) then
                    local d = safe(function() return player:distance_to(obj) end)
                    if type(d) == "number" and d < best_d then
                        best_d = d
                        best = obj
                    end
                end
            end
        end
    end
    return best
end

function targeting.find_npc(player, npc_id, range)
    if not player or not npc_id then
        return nil
    end
    local objects = all_objects()
    if type(objects) ~= "table" then
        return nil
    end
    local best = nil
    local best_d = range or 80
    for i = 1, #objects do
        local obj = objects[i]
        if obj and safe(function() return obj:is_valid() end) == true then
            local id = safe(function() return obj:get_npc_id() end)
            if id == npc_id then
                local d = safe(function() return player:distance_to(obj) end)
                if type(d) == "number" and d < best_d then
                    best_d = d
                    best = obj
                end
            end
        end
    end
    return best
end

return targeting

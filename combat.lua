-- ============================================================================
-- Master Farmer - Grindbot
-- Combat engine — threat scan, target latch, kill-first priority, class hooks
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.0c
-- Folder: MasterFarmer_v1.0c
-- Shared by every class rotation. Class modules opt in by exposing interrupt,
-- taunt or aggro_dump; the engine never casts on their behalf.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type enums
local enums = require("common/enums")

local state = require("state")

local combat = {}

-- ASSUMPTIONS: core.get_instance_type() answers the client's instance type
-- string, where "none" or an empty string is the open world. Anything else is
-- treated as an instance, which widens the scan to every hostile combatant
-- instead of only the ones already on the player or the pet.
local OPEN_WORLD = "none"

local DEFAULT_RANGE = 40.0
local DISMOUNT_RANGE = 40.0
local DEFAULT_HOLD = 1.0
local MELEE_HOLD = 10.0

-- Melee specs lose more from retargeting mid-swing, so they hold far longer.
local MELEE_HOLD_CLASSES = {
    [enums.class_id.WARRIOR] = true,
    [enums.class_id.ROGUE] = true,
    [enums.class_id.DRUID] = true,
}

local kill_first = {}
local fixed_unit = nil
local fixed_at = 0
local on_me_count = 0
local targeting_mod = nil

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function targeting_ref()
    if targeting_mod then
        return targeting_mod
    end
    local ok, mod = pcall(require, "targeting")
    if ok and type(mod) == "table" then
        targeting_mod = mod
    end
    return targeting_mod
end

local function guid_of(unit)
    if not unit then
        return nil
    end
    return safe(function() return unit:get_guid() end)
end

local function alive(unit)
    if not unit then
        return false
    end
    if safe(function() return unit:is_valid() end) ~= true then
        return false
    end
    return safe(function() return unit:is_dead_or_ghost() end) ~= true
end

local function grouped()
    local list = safe(function() return core.object_manager.get_party_frames() end)
    return type(list) == "table" and #list > 0
end

local function hold_time(player)
    local class_id = safe(function() return player:get_class() end)
    if class_id and MELEE_HOLD_CLASSES[class_id] then
        return MELEE_HOLD
    end
    return DEFAULT_HOLD
end

function combat.in_instance()
    local kind = safe(function() return core.get_instance_type() end)
    if type(kind) ~= "string" or kind == "" then
        return false
    end
    return string.lower(kind) ~= OPEN_WORLD
end

function combat.set_kill_first(ids)
    kill_first = {}
    if type(ids) ~= "table" then
        return
    end
    for i = 1, #ids do
        if type(ids[i]) == "number" and ids[i] > 0 then
            kill_first[#kill_first + 1] = ids[i]
        end
    end
end

function combat.kill_first()
    return kill_first
end

--- Hostile combatants around the player, nearest first.
--- In the open world only mobs fighting the player or the pet count. Inside an
--- instance every hostile in combat counts, matching how packs are pulled there.
---@return game_object[] pack, integer on_me
function combat.scan(player, range)
    local found = {}
    on_me_count = 0
    if not player then
        return found, 0
    end
    local yards = tonumber(range) or DEFAULT_RANGE
    local list = nil
    local targeting = targeting_ref()
    if targeting and type(targeting.enemy_list) == "function" then
        list = safe(function() return targeting.enemy_list(player, yards) end)
    end
    if type(list) ~= "table" then
        list = safe(function() return izi.enemies(yards) end) or {}
    end
    local me_guid = guid_of(player)
    local pet = safe(function() return player:get_pet() end)
    local pet_guid = pet and guid_of(pet) or nil
    local dungeon = combat.in_instance()
    local rows = {}
    for i = 1, #list do
        local u = list[i]
        if alive(u) and safe(function() return u:is_in_combat() end) == true then
            if safe(function() return player:can_attack(u) end) ~= false then
                local tar = safe(function() return u:get_target() end)
                local tguid = tar and guid_of(tar) or nil
                local mine = me_guid ~= nil and tguid ~= nil and tguid == me_guid
                local on_pet = pet_guid ~= nil and tguid ~= nil and tguid == pet_guid
                if dungeon or mine or on_pet then
                    local d = safe(function() return player:distance_to(u) end)
                    rows[#rows + 1] = {
                        unit = u,
                        distance = type(d) == "number" and d or 9999,
                        on_me = mine,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.distance < b.distance
    end)
    for i = 1, #rows do
        found[i] = rows[i].unit
        if rows[i].on_me then
            on_me_count = on_me_count + 1
        end
    end
    return found, on_me_count
end

--- How many enemies from the last scan are actually hitting the player.
function combat.on_me()
    return on_me_count
end

function combat.pick(player, pack)
    if type(pack) ~= "table" or #pack == 0 then
        return nil
    end
    for k = 1, #kill_first do
        for i = 1, #pack do
            local id = safe(function() return pack[i]:get_npc_id() end)
            if id == kill_first[k] then
                return pack[i]
            end
        end
    end
    -- Grouped play: help with something an ally already holds rather than
    -- pulling a fresh mob. No group-leader API exists, so ally aggro is the cue.
    if grouped() then
        local me_guid = guid_of(player)
        for i = 1, #pack do
            local tar = safe(function() return pack[i]:get_target() end)
            if tar and guid_of(tar) ~= me_guid then
                if safe(function() return tar:is_player() end) == true then
                    return pack[i]
                end
            end
        end
    end
    return pack[1]
end

function combat.hold(unit)
    fixed_unit = unit
    fixed_at = izi.now()
end

function combat.release()
    fixed_unit = nil
    fixed_at = 0
end

function combat.fixed_target()
    if alive(fixed_unit) then
        return fixed_unit
    end
    return nil
end

--- Resolve who to fight. A caller's own live target always wins; the latch only
--- fills in when that target is gone, so grind and quest routes stay in charge.
---@return game_object|nil target, game_object[] pack
function combat.acquire(player, range, candidate, pack)
    if type(pack) ~= "table" then
        pack = combat.scan(player, range)
    end
    if alive(candidate) then
        combat.hold(candidate)
        return candidate, pack
    end
    if alive(fixed_unit) and (izi.now() - fixed_at) < hold_time(player) then
        return fixed_unit, pack
    end
    local picked = combat.pick(player, pack)
    if picked then
        combat.hold(picked)
        local targeting = targeting_ref()
        if targeting and type(targeting.set_current) == "function" then
            pcall(function()
                targeting.set_current(picked, "kill")
            end)
        end
    else
        combat.release()
    end
    return picked, pack
end

function combat.dismount(player, target)
    if not player or safe(function() return player:is_mounted() end) ~= true then
        return false
    end
    if target then
        local d = safe(function() return player:distance_to(target) end)
        if type(d) == "number" and d > DISMOUNT_RANGE then
            return false
        end
    end
    pcall(function()
        core.input.dismount()
    end)
    return true
end

local function casting(unit)
    return safe(function() return unit:is_channeling_or_casting() end) == true
end

--- Give the class module its interrupt, taunt and aggro-dump windows before the
--- damage rotation runs. Every hook is optional.
function combat.assist(player, target, pack, module)
    if type(module) ~= "table" or type(pack) ~= "table" then
        return false
    end
    if type(module.interrupt) == "function" then
        for i = 1, #pack do
            local u = pack[i]
            if casting(u) and safe(function() return module.interrupt(player, u) end) == true then
                return true
            end
        end
    end
    if type(module.taunt) == "function" then
        local me_guid = guid_of(player)
        for i = 1, #pack do
            local u = pack[i]
            local tar = safe(function() return u:get_target() end)
            if not tar or guid_of(tar) ~= me_guid then
                if safe(function() return module.taunt(player, u) end) == true then
                    return true
                end
            end
        end
    end
    if #pack >= 2 and type(module.aggro_dump) == "function" then
        if safe(function() return module.aggro_dump(player, pack) end) == true then
            return true
        end
    end
    return false
end

function combat.reset()
    combat.release()
    on_me_count = 0
    if type(state.combat) == "table" then
        state.combat.kite_until = 0
    end
end

return combat

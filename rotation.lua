-- ============================================================================
-- Master Farmer - Grindbot
-- Class rotation dispatcher
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- Adding a class: create rotations/<class>.lua and register it here.
-- ============================================================================

---@type enums
local enums = require("common/enums")

local mage = require("rotations/mage")
local targeting = require("targeting")

local by_class = {}
if mage and mage.class_id then
    by_class[mage.class_id()] = mage
end

local rotation = {}
local last_action = "Idle"

function rotation.supported(class_id)
    return by_class[class_id] ~= nil
end

function rotation.module_for(class_id)
    return by_class[class_id]
end

function rotation.active(player)
    if not player then
        return nil
    end
    local ok, class_id = pcall(function()
        return player:get_class()
    end)
    if not ok then
        return nil
    end
    return by_class[class_id]
end

function rotation.register_gui(menu)
    if mage and type(mage.register_gui) == "function" then
        mage.register_gui(menu)
    end
end

function rotation.buffs_ooc(player)
    local mod = rotation.active(player)
    if not mod or type(mod.buffs_ooc) ~= "function" then
        return false
    end
    return mod.buffs_ooc(player) == true
end

function rotation.combat_range(player)
    local mod = rotation.active(player)
    if mod and type(mod.combat_range) == "function" then
        local yards = mod.combat_range(player)
        if type(yards) == "number" and yards > 0 then
            return yards
        end
    end
    return 30
end

function rotation.tick(player, target, ctx)
    local mod = rotation.active(player)
    if not mod or type(mod.tick) ~= "function" then
        return false
    end
    if player and target and targeting and type(targeting.start_auto_attack) == "function" then
        targeting.start_auto_attack(player, target)
    end
    if target then
        pcall(function()
            local movement = require("movement")
            if movement and type(movement.face_combat) == "function" then
                movement.face_combat(target)
            end
        end)
    end
    return mod.tick(player, target, ctx) == true
end

function rotation.preferred_food_ids(player)
    local mod = rotation.active(player)
    if mod and type(mod.preferred_food_ids) == "function" then
        return mod.preferred_food_ids()
    end
    return nil
end

function rotation.preferred_drink_ids(player)
    local mod = rotation.active(player)
    if mod and type(mod.preferred_drink_ids) == "function" then
        return mod.preferred_drink_ids()
    end
    return nil
end

function rotation.set_last_action(text)
    if type(text) == "string" and text ~= "" then
        last_action = text
    end
end

function rotation.last_action()
    return last_action
end

function rotation.class_labels()
    return {
        { id = enums.class_id.WARRIOR, label = "Warrior" },
        { id = enums.class_id.PALADIN, label = "Paladin" },
        { id = enums.class_id.HUNTER, label = "Hunter" },
        { id = enums.class_id.ROGUE, label = "Rogue" },
        { id = enums.class_id.PRIEST, label = "Priest" },
        { id = enums.class_id.SHAMAN, label = "Shaman" },
        { id = enums.class_id.MAGE, label = "Mage" },
        { id = enums.class_id.WARLOCK, label = "Warlock" },
        { id = enums.class_id.DRUID, label = "Druid" },
    }
end

return rotation

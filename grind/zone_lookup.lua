-- ============================================================================
-- Master Farmer - Grindbot
-- Grind zone lookup by race + level
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

local modes = require("modes")

local grind_zones = {}
local loaded_key = nil
local loaded_list = nil

local function list_for(race_id)
    local key = modes.race_key(race_id)
    if not key then
        return nil
    end
    if loaded_key == key then
        return loaded_list
    end
    if loaded_key then
        package.loaded["grind/zones/" .. loaded_key] = nil
        loaded_list = nil
    end
    local ok, list = pcall(require, "grind/zones/" .. key)
    if not ok or type(list) ~= "table" then
        loaded_key = nil
        loaded_list = nil
        return nil
    end
    loaded_key = key
    loaded_list = list
    pcall(collectgarbage, "step", 200)
    return list
end

function grind_zones.lookup(race_id, level)
    local list = list_for(race_id)
    if type(list) ~= "table" then
        return nil
    end
    for i = 1, #list do
        local row = list[i]
        if level >= row.min and level <= row.max then
            return row
        end
    end
    return nil
end

return grind_zones

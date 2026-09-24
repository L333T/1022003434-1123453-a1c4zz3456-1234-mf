-- ============================================================================
-- Master Farmer - Grindbot
-- Combat potions, and the gate that lets a rotation rest
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- WHAT MOVED, AND WHY THIS FILE STILL EXISTS  (1.8.0)
--   Eating and drinking now belong to the class rotations: each one decides
--   when to sit down and at what percentage, and resting.lua holds the shared
--   machinery. This file kept two jobs.
--
--   1. POTIONS. They are used in combat, which is exactly when resting cannot
--      happen, so they never belonged with the eat/drink code.
--
--   2. THE GATE. "Eat / Drink" on the Healing tab is what lets the loaded
--      rotation's resting run at all. With it off, no class rests.
--
--   healing.is_resting() is kept and forwards to resting.is_resting(), because
--   loot.lua, rotation.lua, grind/engine.lua, quest/engine.lua and main.lua all
--   ask this question and none of them should care where the answer comes from.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local gui = require("gui")
local resting = require("resting")

local healing = {}

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
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

local function health_pct(player)
    local pct = safe(function() return player:get_health_percentage() end)
    local cur = safe(function() return player:get_health() end)
    local maxh = safe(function() return player:max_health() end)
    return as_percent(pct, cur, maxh)
end

local function mana_pct(player)
    local maxm = safe(function() return player:mana_max() end)
    if type(maxm) == "number" and maxm <= 0 then
        return 100
    end
    local pct = safe(function() return player:mana_pct() end)
    local cur = safe(function() return player:mana_current() end)
    return as_percent(pct, cur, maxm)
end

-- ----------------------------------------------------------------------------
-- PUBLIC
-- ----------------------------------------------------------------------------
--- Forwarded so every existing caller keeps working: loot, rotation, the grind
--- and quest engines and main all ask healing whether the bot is sitting down.
function healing.is_resting()
    return resting.is_resting()
end

function healing.tick(player)
    if not player then
        resting.clear()
        return false
    end

    -- In combat: potions only. Resting is impossible here, and the rotation is
    -- busy fighting.
    if safe(function() return player:is_in_combat() end) == true then
        if gui.is_on("potions") then
            local hp = health_pct(player)
            local mana = mana_pct(player)
            local has_mana = (safe(function() return player:mana_max() end) or 0) > 0
            if hp <= gui.slider("hp_pot", 35) then
                izi.use_best_health_potion_safe()
            end
            if has_mana and mana <= gui.slider("mp_pot", 20) then
                izi.use_best_mana_potion_safe()
            end
        end
        return false
    end

    -- Out of combat: the Healing tab's Eat / Drink checkbox is the gate, and
    -- the loaded rotation decides the rest.
    if gui.is_on("eat_drink") ~= true then
        resting.clear()
        return false
    end

    local ok, rotation = pcall(require, "rotation")
    if not ok or type(rotation) ~= "table" or type(rotation.rest) ~= "function" then
        return false
    end
    return rotation.rest(player) == true
end

return healing

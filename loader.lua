-- ============================================================================
-- Master Farmer - Grindbot
-- Lazy grind / quest pack loader. Path tables stay on disk until a mode is checked.
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

local loader = {}

local grind_mod = nil
local quest_mod = nil
local grind_on = false
local quest_on = false

local GRIND_PACK = {
    "grind/paths/catalog",
    "grind/catalog",
    "grind/zone_lookup",
    "grind/engine",
    "grind",
}

local QUEST_PACK = {
    "quest/npc",
    "quest/engine",
    "quest",
}

local function drop(list)
    for i = #list, 1, -1 do
        package.loaded[list[i]] = nil
    end
    local ok, pf = pcall(require, "path_format")
    if ok and pf and type(pf.drop) == "function" then
        pf.drop()
    end
    pcall(collectgarbage, "step", 400)
end

function loader.ensure_grind()
    if grind_mod then
        grind_on = true
        return grind_mod
    end
    local ok, mod = pcall(require, "grind")
    if not ok or type(mod) ~= "table" then
        core.log_error("[Master Farmer - Grindbot] grind pack failed: " .. tostring(mod))
        return nil
    end
    grind_mod = mod
    grind_on = true
    return grind_mod
end

function loader.ensure_quest()
    if quest_mod then
        quest_on = true
        return quest_mod
    end
    local ok, mod = pcall(require, "quest")
    if not ok or type(mod) ~= "table" then
        core.log_error("[Master Farmer - Grindbot] quest pack failed: " .. tostring(mod))
        return nil
    end
    quest_mod = mod
    quest_on = true
    return quest_mod
end

function loader.unload_grind()
    if grind_mod and type(grind_mod.clear_profile) == "function" then
        pcall(grind_mod.clear_profile)
    end
    if grind_mod and type(grind_mod.clear_hunt) == "function" then
        pcall(grind_mod.clear_hunt)
    end
    grind_mod = nil
    grind_on = false
    drop(GRIND_PACK)
end

function loader.unload_quest()
    quest_mod = nil
    quest_on = false
    drop(QUEST_PACK)
end

function loader.grind()
    return grind_mod
end

function loader.quest()
    return quest_mod
end

function loader.grind_ready()
    return grind_on and grind_mod ~= nil
end

function loader.quest_ready()
    return quest_on and quest_mod ~= nil
end

return loader

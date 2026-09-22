-- ============================================================================
-- Master Farmer - Grindbot
-- Grind path catalog: Alliance 1-60 Elwynn / Westfall
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

local path_format = require("path_format")
local ENTRIES = require("grind/paths/catalog")

local novelist_paths = {}

local function region_of(entry)
    if type(entry) ~= "table" then
        return "custom"
    end
    if type(entry.region) == "string" and entry.region ~= "" then
        return entry.region
    end
    return "custom"
end

function novelist_paths.count()
    return #ENTRIES
end

function novelist_paths.entry(index)
    if type(index) ~= "number" then
        return nil
    end
    return ENTRIES[index]
end

function novelist_paths.entries_for_region(key)
    local out = {}
    if key == "custom" then
        for i = 1, #ENTRIES do
            out[#out + 1] = ENTRIES[i]
        end
        return out
    end
    for i = 1, #ENTRIES do
        if region_of(ENTRIES[i]) == key then
            out[#out + 1] = ENTRIES[i]
        end
    end
    return out
end

function novelist_paths.labels_for_region(key)
    local entries = novelist_paths.entries_for_region(key)
    local labels = {}
    for i = 1, #entries do
        labels[i] = entries[i].label or entries[i].id or ("Grind " .. i)
    end
    return labels
end

local function finish_path(raw, entry)
    local path, err = path_format.normalize(raw)
    if not path then
        return nil, err
    end
    if type(path.id) ~= "string" or path.id == "" then
        path.id = entry.id
    end
    if type(path.name) ~= "string" or path.name == "" or path.name == "default" then
        path.name = entry.label or entry.id
    end
    if type(raw.loop) == "boolean" then
        path.loop = raw.loop
    elseif type(entry.loop) == "boolean" then
        path.loop = entry.loop
    else
        path.loop = true
    end
    if type(raw.source) == "string" and raw.source ~= "" then
        path.source = raw.source
    elseif type(entry.source) == "string" and entry.source ~= "" then
        path.source = entry.source
    else
        path.source = "lvlgrind"
    end
    if type(raw.kind) == "string" then
        path.kind = raw.kind
    elseif type(entry.kind) == "string" then
        path.kind = entry.kind
    end
    if type(raw.pull) == "number" then
        path.pull = raw.pull
    elseif type(entry.pull) == "number" then
        path.pull = entry.pull
    else
        path.pull = 50
    end
    path.min = raw.min or entry.min
    path.max = raw.max or entry.max
    path.region = raw.region or entry.region
    path.mobs = raw.mobs
    path.merchant = raw.merchant
    path.repair = raw.repair
    return path
end

function novelist_paths.load_region(key, index)
    local entries = novelist_paths.entries_for_region(key)
    if type(index) ~= "number" or index < 1 then
        index = 1
    end
    local entry = entries[index]
    if not entry or type(entry.module) ~= "string" then
        return nil, "unknown grind path"
    end
    local raw, err = path_format.take_module(entry.module)
    if not raw or type(raw) ~= "table" then
        return nil, err or "unknown grind path"
    end
    return finish_path(raw, entry)
end

function novelist_paths.for_level(level, map_id)
    if type(level) ~= "number" then
        return nil, "no level"
    end
    local best = nil
    local best_span = 1000
    for i = 1, #ENTRIES do
        local entry = ENTRIES[i]
        if entry.kind ~= "grind" then
            -- skip vendor / herb auto-select
        else
            local mn = entry.min or 1
            local mx = entry.max or 70
            if level >= mn and level <= mx then
                local span = mx - mn
                local map_ok = type(map_id) ~= "number" or map_id == 0 or entry.map_id == 0 or entry.map_id == map_id
                if map_ok and (best == nil or span < best_span) then
                    best = entry
                    best_span = span
                end
            end
        end
    end
    if not best then
        return nil, "no grind path for this level"
    end
    local raw, err = path_format.take_module(best.module)
    if not raw or type(raw) ~= "table" then
        return nil, err or "unknown grind path"
    end
    return finish_path(raw, best)
end

return novelist_paths

-- ============================================================================
-- Master Farmer - Grindbot
-- Kalimdor Alliance PathTool catalog (lazy load)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

local path_format = require("path_format")
local ENTRIES = require("data/paths/catalog")

local path_catalog = {}

function path_catalog.count()
    return #ENTRIES
end

function path_catalog.labels()
    local labels = {}
    for i = 1, #ENTRIES do
        labels[i] = ENTRIES[i].label or ENTRIES[i].id or ("Path " .. i)
    end
    return labels
end

function path_catalog.entry(index)
    if type(index) ~= "number" then
        return nil
    end
    return ENTRIES[index]
end

function path_catalog.region_of(id)
    if type(id) ~= "string" or id == "" then
        return "custom"
    end
    for i = 1, #ENTRIES do
        local entry = ENTRIES[i]
        if entry.id == id then
            return path_catalog.region_of_entry(entry)
        end
    end
    return "custom"
end

function path_catalog.region_of_entry(entry)
    if type(entry) ~= "table" then
        return "custom"
    end
    if type(entry.region) == "string" and entry.region ~= "" then
        return entry.region
    end
    local module_name = entry.module or ""
    if string.find(module_name, "/kalimdor/", 1, true) then
        return "kalimdor"
    end
    return "custom"
end

function path_catalog.entries_for_region(key)
    local out = {}
    for i = 1, #ENTRIES do
        if path_catalog.region_of_entry(ENTRIES[i]) == key then
            out[#out + 1] = ENTRIES[i]
        end
    end
    return out
end

function path_catalog.labels_for_region(key)
    local entries = path_catalog.entries_for_region(key)
    local labels = {}
    for i = 1, #entries do
        labels[i] = entries[i].label or entries[i].id or ("Path " .. i)
    end
    return labels
end

local function finish_loaded(raw, entry)
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
    path.region = path_catalog.region_of_entry(entry)
    path.kind = "travel"
    if type(entry.source) == "string" and entry.source ~= "" then
        path.source = entry.source
    elseif type(path.source) ~= "string" or path.source == "" then
        path.source = "kalimdor"
    end
    return path
end

function path_catalog.load_region(key, index)
    local entries = path_catalog.entries_for_region(key)
    if type(index) ~= "number" or index < 1 then
        index = 1
    end
    local entry = entries[index]
    if not entry or type(entry.module) ~= "string" then
        return nil, "unknown path"
    end
    local raw, err = path_format.take_module(entry.module)
    if not raw then
        return nil, err or "unknown path"
    end
    return finish_loaded(raw, entry)
end

function path_catalog.load(index)
    local entry = path_catalog.entry(index)
    if not entry or type(entry.module) ~= "string" then
        return nil, "unknown path"
    end
    local raw, err = path_format.take_module(entry.module)
    if not raw then
        return nil, err or "unknown path"
    end
    return finish_loaded(raw, entry)
end

return path_catalog

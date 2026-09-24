-- ============================================================================
-- Master Farmer - Grindbot
-- Grind path catalog: Alliance 1-60 Elwynn / Westfall
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

local path_format = require("path_format")
local factions = require("data/factions")

-- Both of these are INDEXES: id, label, module name and a few numbers per
-- route, no waypoints. Together they are a few kilobytes, while the routes they
-- point at hold well over nine thousand waypoints between them - which is why
-- the module named by an entry is only required when that route is selected,
-- and dropped again when another is (path_format.take_module).
local ENTRIES = {}

local function add_index(mod)
    local ok, list = pcall(require, mod)
    if not ok then
        -- Saying nothing here produces an empty path menu and no clue why, so
        -- this is loud on purpose.
        core.log_warning("[Master Farmer - Grindbot] Path index " .. tostring(mod)
            .. " failed to load: " .. tostring(list))
        return
    end
    if type(list) ~= "table" then
        core.log_warning("[Master Farmer - Grindbot] Path index " .. tostring(mod)
            .. " is not a table.")
        return
    end
    for i = 1, #list do
        ENTRIES[#ENTRIES + 1] = list[i]
    end
end

add_index("grind/paths/catalog")
add_index("grind/paths/ally160/catalog")

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

-- Regions that also show another region's routes.
--
-- Every Alliance 1-60 w/Vendoring route is in an Eastern Kingdoms zone -
-- Elwynn, Westfall, Loch Modan, Duskwood, Wetlands, Arathi, STV, Hinterlands -
-- so they belong under Eastern Kingdoms as well as under their own heading.
-- The named list stays: it is the one place they appear grouped and in level
-- order, which is how you pick one.
local INCLUDES = {
    ek = { "ally160" },
}

--- Entries for `key`, plus anything INCLUDES pulls in, deduplicated by id.
---
--- Deduplication matters here rather than being defensive: the original eight
--- Eastern Kingdoms routes were converted from the same PathTool JSON as eight
--- of the ally160 ones and carry the same ids. Without this they would each be
--- listed twice under nearly identical labels. The ally160 copy wins, because
--- it is the one that knows about the route's vendor.
local function collect(key)
    local out, seen = {}, {}

    local function take(region_key)
        for i = 1, #ENTRIES do
            local entry = ENTRIES[i]
            if region_of(entry) == region_key then
                local id = entry.id
                if type(id) ~= "string" or not seen[id] then
                    if type(id) == "string" then
                        seen[id] = true
                    end
                    out[#out + 1] = entry
                end
            end
        end
    end

    local extra = INCLUDES[key]
    if extra then
        for i = 1, #extra do
            take(extra[i])
        end
    end
    take(key)
    return out
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
    if key == "custom" then
        local out = {}
        for i = 1, #ENTRIES do
            out[#out + 1] = ENTRIES[i]
        end
        return out
    end
    return collect(key)
end

-- ----------------------------------------------------------------------------
-- FACTION
-- ----------------------------------------------------------------------------
--- Every grind route for one side, in the order the catalog lists them.
---
--- This replaced the Continent filter. Continent was the wrong axis: all the
--- routes that exist are Eastern Kingdoms, so three of the four choices were
--- always empty, while the one thing a player actually needs to pick - which
--- side they are levelling - was not offered at all.
function novelist_paths.entries_for_faction(key)
    if type(key) ~= "string" or key == "" then
        key = factions.ALLIANCE
    end
    key = string.lower(key)

    local out, seen = {}, {}
    local function take(want_ally160)
        for i = 1, #ENTRIES do
            local entry = ENTRIES[i]
            if factions.of_entry(entry) == key then
                local from_ally160 = (entry.source == "ally160")
                if from_ally160 == want_ally160 then
                    local id = entry.id
                    if type(id) ~= "string" or not seen[id] then
                        if type(id) == "string" then
                            seen[id] = true
                        end
                        out[#out + 1] = entry
                    end
                end
            end
        end
    end

    -- ally160 first, and this ordering is load-bearing twice over. Eight of
    -- those routes were converted from the same PathTool JSON as the original
    -- Eastern Kingdoms eight and carry the same ids, so whichever is seen
    -- first wins the deduplication - and only the ally160 copy knows about the
    -- route's vendor. It is also the only one of the two catalogs that is
    -- sorted by level, which is the order the menu wants.
    take(true)
    take(false)
    return out
end

function novelist_paths.labels_for_faction(key)
    local entries = novelist_paths.entries_for_faction(key)
    local labels = {}
    for i = 1, #entries do
        labels[i] = entries[i].label or entries[i].id or ("Grind " .. i)
    end
    return labels
end

--- How many routes each side has. Used by the tab to say so plainly rather
--- than showing an empty list with no explanation.
function novelist_paths.faction_counts()
    local out = {}
    for i = 1, #factions.keys do
        local key = factions.keys[i]
        out[key] = #novelist_paths.entries_for_faction(key)
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
    path.faction = raw.faction or entry.faction or factions.ALLIANCE
    path.merchant = raw.merchant
    path.repair = raw.repair
    -- Set by the Alliance 1-60 w/Vendoring routes: visit the merchant once per
    -- completed lap, not only when the bags fill or the gear breaks.
    if type(raw.vendor_each_lap) == "boolean" then
        path.vendor_each_lap = raw.vendor_each_lap
    elseif type(entry.vendor_each_lap) == "boolean" then
        path.vendor_each_lap = entry.vendor_each_lap
    end
    return path
end

--- Load the nth route of a faction.
function novelist_paths.load_faction(key, index)
    local entries = novelist_paths.entries_for_faction(key)
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

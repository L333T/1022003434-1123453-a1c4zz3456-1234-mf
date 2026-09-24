-- ============================================================================
-- Master Farmer - Grindbot
-- Leveling grind patrols by continent (from Grind_Information zones)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

local path_format = require("path_format")
local raw = require("data/_zones_raw")

local EK = {
    [1415] = true, [1417] = true, [1418] = true, [1419] = true,
    [1420] = true, [1421] = true, [1422] = true, [1423] = true,
    [1424] = true, [1425] = true, [1426] = true, [1427] = true,
    [1428] = true, [1429] = true, [1430] = true, [1431] = true,
    [1432] = true, [1433] = true, [1434] = true, [1435] = true,
    [1436] = true, [1437] = true, [1453] = true, [1455] = true,
}

local KALIMDOR = {
    [1411] = true, [1412] = true, [1413] = true, [1414] = true,
    [1438] = true, [1439] = true, [1440] = true, [1441] = true,
    [1442] = true, [1443] = true, [1444] = true, [1445] = true,
    [1446] = true, [1447] = true, [1448] = true, [1449] = true,
    [1450] = true, [1451] = true, [1452] = true, [1454] = true,
    [1456] = true, [1457] = true,
}

local RACE_TITLE = {
    human = "Human",
    gnome = "Gnome",
    undead = "Undead",
    troll = "Troll",
}

local ZONE_NAME = {
    [1411] = "Durotar",
    [1412] = "Mulgore",
    [1413] = "The Barrens",
    [1414] = "Kalimdor",
    [1415] = "Eastern Kingdoms",
    [1416] = "Alterac Mountains",
    [1417] = "Arathi Highlands",
    [1418] = "Badlands",
    [1419] = "Blasted Lands",
    [1420] = "Tirisfal Glades",
    [1421] = "Silverpine Forest",
    [1422] = "Western Plaguelands",
    [1423] = "Eastern Plaguelands",
    [1424] = "Hillsbrad Foothills",
    [1425] = "The Hinterlands",
    [1426] = "Dun Morogh",
    [1427] = "Searing Gorge",
    [1428] = "Burning Steppes",
    [1429] = "Elwynn Forest",
    [1430] = "Deadwind Pass",
    [1431] = "Duskwood",
    [1432] = "Loch Modan",
    [1433] = "Redridge Mountains",
    [1434] = "Stranglethorn Vale",
    [1435] = "Swamp of Sorrows",
    [1436] = "Westfall",
    [1437] = "Wetlands",
    [1438] = "Teldrassil",
    [1439] = "Darkshore",
    [1440] = "Ashenvale",
    [1441] = "Thousand Needles",
    [1442] = "Stonetalon Mountains",
    [1443] = "Desolace",
    [1444] = "Feralas",
    [1445] = "Dustwallow Marsh",
    [1446] = "Tanaris",
    [1447] = "Azshara",
    [1448] = "Felwood",
    [1449] = "Un'Goro Crater",
    [1450] = "Moonglade",
    [1451] = "Silithus",
    [1452] = "Winterspring",
    [1453] = "Stormwind City",
    [1454] = "Orgrimmar",
    [1455] = "Ironforge",
    [1456] = "Thunder Bluff",
    [1457] = "Darnassus",
    [1458] = "Undercity",
    [1941] = "Eversong Woods",
    [1942] = "Ghostlands",
    [1943] = "Azuremyst Isle",
    [1944] = "Hellfire Peninsula",
    [1946] = "Zangarmarsh",
    [1947] = "The Exodar",
    [1948] = "Shadowmoon Valley",
    [1950] = "Bloodmyst Isle",
    [1951] = "Nagrand",
    [1952] = "Terokkar Forest",
    [1953] = "Netherstorm",
    [1954] = "Silvermoon City",
    [1955] = "Shattrath City",
    [1957] = "Isle of Quel'Danas",
}

local function continent_of(map_id)
    if EK[map_id] then
        return "ek"
    end
    if KALIMDOR[map_id] then
        return "kalimdor"
    end
    return "custom"
end

local function row_to_path(race_key, row, seq)
    if type(row) ~= "table" or type(row.coords) ~= "table" or #row.coords < 1 then
        return nil
    end
    local waypoints = {}
    for i = 1, #row.coords do
        local c = row.coords[i]
        local x, y, z
        if type(c) == "table" then
            x = c.x or c[1]
            y = c.y or c[2]
            z = c.z or c[3]
        end
        if type(x) == "number" and type(y) == "number" and type(z) == "number" then
            waypoints[#waypoints + 1] = { x = x, y = y, z = z }
        end
    end
    if #waypoints < 1 then
        return nil
    end
    local race_name = RACE_TITLE[race_key] or race_key
    local min_lv = row.min or 1
    local max_lv = row.max or min_lv
    local zone = ZONE_NAME[row.map_id or 0] or ("map " .. tostring(row.map_id or 0))
    local id = string.format("level_%s_%d_%d_%d", race_key, min_lv, max_lv, seq)
    return {
        id = id,
        name = string.format("%s  %d-%d  %s", race_name, min_lv, max_lv, zone),
        map_id = row.map_id or 0,
        loop = true,
        waypoints = waypoints,
        mobs = row.mobs,
        region = continent_of(row.map_id or 0),
        min = min_lv,
        max = max_lv,
        race_key = race_key,
    }
end

local ALL = {}
local BY_REGION = { ek = {}, kalimdor = {}, custom = {} }

local race_order = { "human", "gnome", "undead", "troll" }
for r = 1, #race_order do
    local race_key = race_order[r]
    local list = raw[race_key]
    if type(list) == "table" then
        for i = 1, #list do
            local path = row_to_path(race_key, list[i], i)
            if path then
                ALL[#ALL + 1] = path
                local bucket = BY_REGION[path.region] or BY_REGION.custom
                bucket[#bucket + 1] = path
            end
        end
    end
end

local leveling_paths = {}

function leveling_paths.entries_for_region(key)
    return BY_REGION[key] or BY_REGION.custom
end

function leveling_paths.labels_for_region(key)
    local entries = leveling_paths.entries_for_region(key)
    local labels = {}
    for i = 1, #entries do
        labels[i] = entries[i].name or entries[i].id
    end
    return labels
end

function leveling_paths.load_region(key, index)
    local entries = leveling_paths.entries_for_region(key)
    if type(index) ~= "number" or index < 1 then
        index = 1
    end
    local entry = entries[index]
    if not entry then
        return nil, "no leveling path"
    end
    local path, err = path_format.normalize(entry)
    if not path then
        return nil, err
    end
    path.id = entry.id
    path.name = entry.name
    path.loop = true
    path.mobs = entry.mobs
    return path
end

return leveling_paths

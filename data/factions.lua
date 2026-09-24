-- ============================================================================
-- Master Farmer - Grindbot
-- Faction lookup
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- BOTH APIS, IN THAT ORDER  (1.9.1)
--   unit:get_race_id()     integer, the race the character was created as
--   unit:get_faction_id()  number, the faction template the unit belongs to
--
--   Race is asked first because it is unambiguous: a race maps to exactly one
--   side and never changes. get_faction_id is asked second, as corroboration
--   and as the fallback for the tick or two before the player object can
--   answer get_race_id.
--
--   Both are methods on GAME_OBJECT, not on unit_helper. unit_helper carries
--   is_valid_enemy, get_health_percentage, get_enemy_list_around and the rest,
--   and has no faction or race call at all - targeting.lua already uses it for
--   what it does have.
-- ============================================================================

local factions = {}

factions.ALLIANCE = "alliance"
factions.HORDE = "horde"

factions.labels = { "Alliance", "Horde" }
factions.keys = { factions.ALLIANCE, factions.HORDE }

local BY_RACE = {
    [1] = factions.ALLIANCE,   -- Human
    [3] = factions.ALLIANCE,   -- Dwarf
    [4] = factions.ALLIANCE,   -- Night Elf
    [7] = factions.ALLIANCE,   -- Gnome
    [11] = factions.ALLIANCE,  -- Draenei
    [2] = factions.HORDE,      -- Orc
    [5] = factions.HORDE,      -- Undead
    [6] = factions.HORDE,      -- Tauren
    [8] = factions.HORDE,      -- Troll
    [10] = factions.HORDE,     -- Blood Elf
}

--- The faction key for a race id, or nil when the race is not known yet.
function factions.of_race(race_id)
    if type(race_id) ~= "number" then
        return nil
    end
    return BY_RACE[race_id]
end

-- Player faction template ids in TBC. Only used when the race is unreadable;
-- a template id is per-unit and far easier to get wrong than a race, so it is
-- never trusted over one.
local BY_FACTION_ID = {
    [1] = factions.ALLIANCE,     -- Human
    [3] = factions.ALLIANCE,     -- Dwarf
    [4] = factions.ALLIANCE,     -- Night Elf
    [8] = factions.ALLIANCE,     -- Gnome
    [1629] = factions.ALLIANCE,  -- Draenei
    [2] = factions.HORDE,        -- Orc
    [5] = factions.HORDE,        -- Undead
    [6] = factions.HORDE,        -- Tauren
    [9] = factions.HORDE,        -- Troll
    [914] = factions.HORDE,      -- Blood Elf
}

--- The faction key for a faction template id, or nil when it is not a player
--- faction.
function factions.of_faction_id(faction_id)
    if type(faction_id) ~= "number" then
        return nil
    end
    return BY_FACTION_ID[faction_id]
end

--- The faction key for a player object, or nil while the object is not ready.
---
--- Race first, faction id second. Returns the key and which call answered, so
--- the caller can log what it actually used rather than guessing.
function factions.of_player(player)
    if not player then
        return nil, "no player"
    end

    local ok, race = pcall(function() return player:get_race_id() end)
    if ok then
        local key = factions.of_race(race)
        if key then
            return key, "race " .. tostring(race)
        end
    end

    local ok2, fid = pcall(function() return player:get_faction_id() end)
    if ok2 then
        local key = factions.of_faction_id(fid)
        if key then
            return key, "faction " .. tostring(fid)
        end
    end

    return nil, "race and faction both unreadable"
end

--- 1 for Alliance, 2 for Horde. Used to drive the selector.
function factions.index_of(key)
    for i = 1, #factions.keys do
        if factions.keys[i] == key then
            return i
        end
    end
    return 1
end

function factions.key_at(index)
    if type(index) ~= "number" or index < 1 or index > #factions.keys then
        return factions.ALLIANCE
    end
    return factions.keys[index]
end

--- Faction a catalog entry belongs to. Everything that does not say otherwise
--- is Alliance: every route shipped so far is an Alliance levelling route, and
--- a Horde one will carry `faction = "horde"` explicitly.
function factions.of_entry(entry)
    if type(entry) ~= "table" then
        return factions.ALLIANCE
    end
    local f = entry.faction
    if type(f) == "string" and f ~= "" then
        return string.lower(f)
    end
    return factions.ALLIANCE
end

return factions

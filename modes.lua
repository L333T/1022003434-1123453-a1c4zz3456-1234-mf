-- ============================================================================
-- Master Farmer - Grindbot
-- Grind vs Quest mode helpers
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

-- ASSUMPTIONS: Classic / TBC race ids from the client (enums has no race table).
local RACE = {
    HUMAN = 1,
    ORC = 2,
    DWARF = 3,
    NIGHT_ELF = 4,
    UNDEAD = 5,
    TAUREN = 6,
    GNOME = 7,
    TROLL = 8,
    GOBLIN = 9,
    BLOOD_ELF = 10,
    DRAENEI = 11,
}

local QUEST_RACES = {
    [RACE.HUMAN] = true,
    [RACE.GNOME] = true,
    [RACE.UNDEAD] = true,
    [RACE.TROLL] = true,
}

local modes = {}
modes.RACE = RACE
modes.GRIND = "grind"
modes.QUEST = "quest"
modes.PATH = "path"

function modes.race_has_starter_quests(race_id)
    return QUEST_RACES[race_id] == true
end

local RACE_LABEL = {
    [RACE.HUMAN] = "Human",
    [RACE.GNOME] = "Gnome",
    [RACE.UNDEAD] = "Undead",
    [RACE.TROLL] = "Troll",
}

function modes.race_key(race_id)
    if race_id == RACE.HUMAN then
        return "human"
    end
    if race_id == RACE.GNOME then
        return "gnome"
    end
    if race_id == RACE.UNDEAD then
        return "undead"
    end
    if race_id == RACE.TROLL then
        return "troll"
    end
    return nil
end

function modes.race_label(race_id)
    return RACE_LABEL[race_id]
end

return modes

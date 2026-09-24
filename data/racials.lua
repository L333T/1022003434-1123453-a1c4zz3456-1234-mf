-- ============================================================================
-- Master Farmer - Grindbot
-- Racial abilities (TBC)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Only ACTIVE racials are listed. Passives (Diplomacy, Hardiness, The Human
-- Spirit, weapon specialisations, resistances) need no toggle and no cast, so
-- putting them in the menu would be nine checkboxes that do nothing.
--
-- Three actives are also left out on purpose:
--   * Shadowmeld  - breaks on any action, so a grind bot that uses it just
--                   stops fighting for a moment and then gets hit anyway
--   * Perception  - stealth detection, pointless against the mobs this bot
--                   pulls
--   * Find Treasure / Cannibalize - the first is a minimap toggle, the second
--                   needs a corpse in range and a channel the bot would break
--
-- `race_id` values are the client's own, the same ones unit:get_race_id()
-- returns. `kind` is what racials.lua dispatches on.
-- ============================================================================

local racials = {}

racials.race_id = {
    HUMAN = 1, ORC = 2, DWARF = 3, NIGHT_ELF = 4, UNDEAD = 5,
    TAUREN = 6, GNOME = 7, TROLL = 8, BLOOD_ELF = 10, DRAENEI = 11,
}

-- kind:
--   "offensive"  fire on cooldown once a fight is properly under way
--   "mana"       fire when mana is low
--   "heal"       fire when health is low
--   "free_cc"    fire when the matching crowd control is on us
--   "aoe_stun"   fire when enough things are in melee range
racials.list = {
    {
        key = "blood_fury", label = "Blood Fury", race = 2, kind = "offensive",
        -- Three versions in TBC: melee attack power, spell power, and the
        -- hybrid. Whichever one this character has is the one that resolves.
        ids = { 20572, 33697, 33702 },
        tooltip = "Orc attack/spell power burst, used once a fight is under way.",
    },
    {
        key = "berserking", label = "Berserking", race = 8, kind = "offensive",
        ids = { 26297 },
        tooltip = "Troll haste burst, used once a fight is under way.",
    },
    {
        key = "arcane_torrent", label = "Arcane Torrent", race = 10, kind = "mana",
        ids = { 28730, 25046, 50613 },
        tooltip = "Blood Elf mana return, used when mana runs low in combat.",
    },
    {
        key = "mana_tap", label = "Mana Tap", race = 10, kind = "mana_tap",
        ids = { 28734 },
        tooltip = "Blood Elf: drains the target to charge Arcane Torrent. Needs a target in range.",
    },
    {
        key = "gift_of_naaru", label = "Gift of the Naaru", race = 11, kind = "heal",
        ids = { 28880, 59542, 59543, 59544, 59545, 59547, 59548 },
        tooltip = "Draenei heal over time, used when health drops in combat.",
    },
    {
        key = "stoneform", label = "Stoneform", race = 3, kind = "free_cc",
        ids = { 20594 },
        cc = "bleed",
        tooltip = "Dwarf: clears bleed, poison and disease, and adds armour.",
    },
    {
        key = "will_of_forsaken", label = "Will of the Forsaken", race = 5, kind = "free_cc",
        ids = { 7744 },
        cc = "fear",
        tooltip = "Undead: breaks fear, sleep and charm.",
    },
    {
        key = "escape_artist", label = "Escape Artist", race = 7, kind = "free_cc",
        ids = { 20589 },
        cc = "root",
        tooltip = "Gnome: breaks roots and snares.",
    },
    {
        key = "war_stomp", label = "War Stomp", race = 6, kind = "aoe_stun",
        ids = { 20549 },
        tooltip = "Tauren: stuns everything in melee range. Used when more than one thing is on you.",
    },
}

--- The racials this race can use.
function racials.for_race(race_id)
    local out = {}
    if type(race_id) ~= "number" then
        return out
    end
    for i = 1, #racials.list do
        if racials.list[i].race == race_id then
            out[#out + 1] = racials.list[i]
        end
    end
    return out
end

return racials

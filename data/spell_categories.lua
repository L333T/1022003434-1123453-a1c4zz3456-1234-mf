-- ============================================================================
-- Master Farmer - Grindbot
-- Spell categories
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- HOW A SPELL GETS ITS CATEGORY
--   1. An explicit id, which always wins. Used where a name is ambiguous
--      across classes or where the keyword rules would get it wrong.
--   2. An explicit name.
--   3. A keyword rule on the name.
--   4. Nothing matched - it becomes "other", and it is still SHOWN. A spell
--      the bot cannot categorise is not a spell the player stops owning.
--
-- The keyword rules are a heuristic and are stated as one. "Blessing of",
-- "Aspect of", "Aura", "Armor", "Shield", "Ward" are buffs in every TBC class
-- that has them, which is what makes the rule worth having - but a keyword
-- rule is a guess, and anything it gets wrong is corrected by adding the id to
-- BY_ID above it rather than by making the keywords cleverer.
--
-- Only the BUFF category drives behaviour: buffs.lua casts what is enabled
-- there. The rest exist so the Spells tab can group the book into something
-- readable instead of one alphabetical wall.
-- ============================================================================

local categories = {}

categories.SINGLE_TARGET = "single_target"
categories.AOE = "aoe"
categories.INTERRUPT = "interrupt"
categories.BUFF = "buff"
categories.UTILITY = "utility"
categories.RACIAL = "racial"
categories.OTHER = "other"

categories.order = {
    categories.BUFF,
    categories.SINGLE_TARGET,
    categories.AOE,
    categories.INTERRUPT,
    categories.UTILITY,
    categories.RACIAL,
    categories.OTHER,
}

local LABELS = {
    [categories.BUFF] = "Buffs",
    [categories.SINGLE_TARGET] = "Single Target",
    [categories.AOE] = "Area of Effect",
    [categories.INTERRUPT] = "Interrupts",
    [categories.UTILITY] = "Utility",
    [categories.RACIAL] = "Racial",
    [categories.OTHER] = "Other",
}

function categories.label(key)
    return LABELS[key] or key
end

-- ----------------------------------------------------------------------------
-- EXPLICIT IDS
-- ----------------------------------------------------------------------------
-- Interrupts, because there is no keyword that finds them and getting one
-- wrong means the bot never kicks.
local BY_ID = {}

local function mark(category, ids)
    for i = 1, #ids do
        BY_ID[ids[i]] = category
    end
end

mark(categories.INTERRUPT, {
    2139,                                   -- Counterspell (Mage)
    1766,                                   -- Kick (Rogue)
    6552, 6554,                             -- Pummel (Warrior)
    72, 1671, 1672,                         -- Shield Bash (Warrior)
    19244, 19647,                           -- Spell Lock (Warlock felhunter)
    8042, 8044, 8045, 8046, 10412, 10413, 10414, 25454,  -- Earth Shock (Shaman)
    16979,                                  -- Feral Charge (Druid)
})

-- Area damage that the keyword rules would miss.
mark(categories.AOE, {
    1449, 8437, 8438, 8439, 10201, 27082,   -- Arcane Explosion
    10, 6141, 8427, 10185, 10186, 10187, 27085,  -- Blizzard
    2120, 2121, 8422, 8423, 10215, 10216, 27086, -- Flamestrike
    5740, 6219, 11677, 11678, 27212,        -- Rain of Fire
    1949, 11683, 11684, 27213,              -- Hellfire
    5185,                                   -- (Druid) Healing Touch is not AoE; placeholder removed below
})
BY_ID[5185] = nil

-- ----------------------------------------------------------------------------
-- KEYWORD RULES
-- ----------------------------------------------------------------------------
-- Ordered: the first rule that matches wins, so the more specific patterns
-- come first.
local RULES = {
    -- Buffs. These prefixes are buffs in every TBC class that has them.
    { categories.BUFF, {
        "^Blessing of ", "^Greater Blessing of ",
        "^Aspect of ", "^Seal of ",
        "^Power Word: Fortitude", "^Prayer of ",
        "^Mark of the Wild", "^Gift of the Wild",
        "Aura$", " Aura$",
        "Armor$", " Armor$",
        "Shield$", " Shield$",
        "Ward$", " Ward$",
        "^Arcane Intellect", "^Arcane Brilliance",
        "^Divine Spirit", "^Inner Fire", "^Shadow Protection",
        "^Thorns", "^Omen of Clarity", "^Barkskin",
        "^Battle Shout", "^Commanding Shout", "^Berserker Rage",
        "^Trueshot Aura", "^Righteous Fury",
        "^Slice and Dice", "^Evasion", "^Sprint", "^Stealth",
        "^Demon Skin", "^Fel Armor", "^Soul Link",
        "^Dampen Magic", "^Amplify Magic",
        "^Rockbiter Weapon", "^Flametongue Weapon",
        "^Frostbrand Weapon", "^Windfury Weapon",
        "^Lightning Shield", "^Water Shield",
    } },

    -- Things that are plainly not combat spells.
    { categories.UTILITY, {
        "^Conjure ", "^Create ", "^Summon ", "^Teleport", "^Portal",
        "^First Aid", "^Cooking", "^Fishing", "^Mining", "^Herbalism",
        "^Skinning", "^Enchanting", "^Tailoring", "^Blacksmithing",
        "^Alchemy", "^Leatherworking", "^Engineering", "^Jewelcrafting",
        "^Riding", "^Apprentice", "^Journeyman", "^Expert", "^Artisan",
        "^Slow Fall", "^Levitate", "^Water Walking", "^Water Breathing",
        "^Unending Breath", "^Detect ", "^Find ", "^Track ",
        "^Revive ", "^Resurrect", "^Redemption", "^Ancestral Spirit",
        "^Drink", "^Food", "^Languages?", "^Opening", "^Pick Lock",
        "^Feed Pet", "^Call Pet", "^Dismiss Pet", "^Tame Beast",
        "^Mount", "^Shapeshift", "^Bear Form", "^Cat Form",
        "^Travel Form", "^Aquatic Form", "^Moonkin Form", "^Dire Bear Form",
        "^Innervate", "^Eat", "^Sit",
    } },

    -- Anything that names a multi-target effect.
    { categories.AOE, {
        "Explosion", "Blizzard", "Flamestrike", "Rain of ", "Hellfire",
        "^Cleave", "^Whirlwind", "^Multi%-Shot", "^Volley", "^Fan of Knives",
        "^Consecration", "^Holy Nova", "^Hurricane", "^Chain Lightning",
        "^Magma Totem", "^Fire Nova", "^Swipe", "^Thunder Clap",
        "^Demoralizing Shout", "^Howl of Terror", "^Psychic Scream",
        "^Seed of Corruption", "^Blast Wave", "^Cone of Cold",
    } },
}

local function match_rules(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    for i = 1, #RULES do
        local category, patterns = RULES[i][1], RULES[i][2]
        for j = 1, #patterns do
            if string.find(name, patterns[j]) then
                return category
            end
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- RACIALS
-- ----------------------------------------------------------------------------
local racial_ids = nil

local function is_racial(id)
    if racial_ids == nil then
        racial_ids = {}
        local ok, data = pcall(require, "data/racials")
        if ok and type(data) == "table" and type(data.list) == "table" then
            for i = 1, #data.list do
                local ids = data.list[i].ids
                if type(ids) == "table" then
                    for j = 1, #ids do
                        racial_ids[ids[j]] = true
                    end
                end
            end
        end
    end
    return racial_ids[id] == true
end

-- ----------------------------------------------------------------------------
-- PUBLIC
-- ----------------------------------------------------------------------------
--- The category for one spell. Explicit id, then racial, then keyword, then
--- "other" - which is a real category that gets shown, not a bin.
function categories.category_of(id, name)
    if type(id) == "number" then
        local explicit = BY_ID[id]
        if explicit then
            return explicit
        end
        if is_racial(id) then
            return categories.RACIAL
        end
    end

    local byname = match_rules(name)
    if byname then
        return byname
    end

    -- A named spell with no rule is assumed to be something it casts at one
    -- thing, which is what most of a class's book is. Unnamed ids stay
    -- "other" so they are visibly unidentified rather than silently filed.
    if type(name) == "string" and name ~= "" and not string.find(name, "^Spell %d") then
        return categories.SINGLE_TARGET
    end
    return categories.OTHER
end

--- True when this category's spells are things buffs.lua should maintain.
function categories.is_buff(cat)
    return cat == categories.BUFF
end

return categories

-- ============================================================================
-- Master Farmer - Grindbot
-- GUI — Shamele chrome, class auto-detect, popup Path/Quest/Vendor/Grind
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

---@type color
local color = require("common/color")

---@type vec2
local vec2 = require("common/geometry/vector_2")

---@type enums
local enums = require("common/enums")

---@type izi_api
local izi = require("common/izi_sdk")

---@type plugin_helper
local plugin_helper = require("common/utility/plugin_helper")

local identity = require("version")
local ui = require("ui")
local modes = require("modes")
local state = require("state")
local spellbook = require("spellbook")
local loader = require("loader")

local gui = {}

local FONT_SMALL = enums.window_enums.font_id.FONT_SMALL

local CLASS_LABELS = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
    "Shaman", "Mage", "Warlock", "Druid",
}

local CLASS_IDS = {
    enums.class_id.WARRIOR,
    enums.class_id.PALADIN,
    enums.class_id.HUNTER,
    enums.class_id.ROGUE,
    enums.class_id.PRIEST,
    enums.class_id.SHAMAN,
    enums.class_id.MAGE,
    enums.class_id.WARLOCK,
    enums.class_id.DRUID,
}

local MODE_LABELS = { "Grind", "Quest", "Path" }
local REGION_LABELS = { "Eastern Kingdoms", "Kalimdor", "Outland", "Alliance 1-60 w/Vendoring", "Custom" }
local REGION_KEYS = { "ek", "kalimdor", "outland", "ally160", "custom" }

local factions = require("data/factions")
local EMPTY_PATH = "(select Grinding first)"
local EMPTY_QUEST = "(select Quest first)"

local PATH_LABELS = { EMPTY_PATH }

local menu = ui.new({
    id = "mfg_" .. string.gsub(identity.version, "%.", "_") .. "_main",
    name = identity.name,
    version = identity.version,
    header_text = identity.description,
    logo = "mf_assets\\mf_assets\\logo.png",
    logo_width = 345,
    logo_height = 79,
    font = "mf_assets\\mf_assets\\ManlineSlabs-pgPVy.otf",
    footer = "Contact Us On Discord: 1stblizz",
    header_hints = {
        { key = "Numpad 0", command = "Start" },
        { key = "Numpad 1", command = "Pause" },
        { key = "Numpad 2", command = "Stop" },
        { key = "Numpad 4", command = "Show / Hide GUI" },
    },
    size = { w = 851, h = 644 },
    position = { x = 80, y = 180 },
    nav = "top",
    tabs = {
        { id = "general", label = "General" },
        { id = "grinding", label = "Grinding" },
        { id = "questing", label = "Questing" },
        { id = "class", label = "Spells" },
        { id = "mode", label = "Mode" },
        { id = "healing", label = "Healing" },
        { id = "settings", label = "Settings" },
    },
})

menu:checkbox("mfg_enable", false, {
    label = "Start Bot",
    tab = "general",
    skip_draw = true,
    tooltip = "Internal run flag. Set by Start after Grind or Quest and a profile are chosen.",
})
menu:checkbox("mfg_player_detect", false, {
    label = "Player Detect (pause pulls)",
    tab = "general",
})
menu:slider_int("mfg_player_yards", 10, 80, 30, {
    label = "Player Detect Range",
    tab = "general",
})
menu:checkbox("mfg_rotation_only", false, {
    label = "Enable Rotation Only",
    tab = "general",
    tooltip = "Run the Class tab rotation on your current target with no bot movement. Leave Play off and steer the character yourself. Uncheck this, load a path, then Play to automate travel.",
})

menu:combobox("mfg_class", 7, CLASS_LABELS, {
    label = "Class Rotation",
    tooltip = "Hidden selector. Synced to the loaded player class.",
})

menu:combobox("mfg_mode", 1, MODE_LABELS, {
    label = "Bot Mode",
    tab = "mode",
    skip_draw = true,
    tooltip = "Legacy mode index. Use the Grinding / Quest checkboxes.",
})

-- These sit at the top of their own tab. A normal tab draws its registered
-- controls first and its custom content underneath, so the enable is always
-- the first thing on the page.
menu:checkbox("mfg_use_grind", false, {
    label = "Enable Grinding",
    tab = "grinding",
    tooltip = "Turn grinding on, then pick a faction and a route below. Cannot run with Questing.",
})
menu:checkbox("mfg_use_quest", false, {
    label = "Enable Questing",
    tab = "questing",
    tooltip = "Turn questing on, then pick a starter quest below. Cannot run with Grinding.",
})

-- Which side's routes to list. Defaults to the character's own faction the
-- first time a player object is available, so the common case needs no click.
menu:combobox("mfg_faction", 1, factions.labels, {
    label = "Faction",
    tab = "grinding",
    skip_draw = true,
    tooltip = "Alliance or Horde. The route list below shows only that side's profiles.",
})
menu:button("mfg_btn_start", {
    label = "Start",
    tab = "mode",
    tooltip = "Begin only after Grinding or Quest is checked and a profile is chosen. Numpad 0.",
    on_click = function()
        if type(gui.try_start) == "function" then
            gui.try_start()
        end
    end,
})

menu:combobox("mfg_path", 1, PATH_LABELS, {
    label = "Grind / Travel",
    tab = "path",
    skip_draw = true,
    tooltip = "All grind loops and travel routes for the selected continent. Load arms the profile; Play starts it.",
})

menu:checkbox("mfg_path_loop", false, {
    label = "Loop Path",
    tab = "path",
    tooltip = "Force a replay when the path finishes. Paths that already have loop=true in the file still loop.",
})
menu:checkbox("mfg_path_reverse", false, {
    label = "Reverse Path",
    tab = "path",
    tooltip = "Play the loaded path last-to-first. Works on travel routes and grind loops. Loop still repeats that reversed order.",
})
menu:checkbox("mfg_path_combat", true, {
    label = "Attack Along Path",
    tab = "path",
    tooltip = "Auto-target the closest PvE mob in rotation range and fight from the loaded path (10-yard leash). Starts melee auto-attack so any class swings when the mob is in melee.",
})
menu:checkbox("mfg_draw_path", true, {
    label = "Draw Loaded Path",
    tab = "path",
    tooltip = "Draw the loaded travel path in the world.",
})

menu:checkbox("mfg_move_debug", false, {
    label = "Movement Debug Log",
    tab = "path",
    tooltip = "Log every movement state change, ownership handoff and pause reason to the console. Lines are de-duplicated, so this is safe to leave on while diagnosing a stuck bot.",
})

menu:checkbox("mfg_eat_drink", true, {
    label = "Eat / Drink",
    tab = "healing",
    tooltip = "Out of combat: at 35% health or mana, FORCE-stop pathing and combat, then eat/drink until that resource is 100%. Uses the highest-ranked food/water in bags.",
})
menu:slider_int("mfg_eat_hp", 20, 35, 35, {
    label = "Eat Below HP %",
    tab = "healing",
    tooltip = "Eating starts at 35% health or lower and continues until health is 100%.",
})
menu:slider_int("mfg_drink_mana", 20, 35, 35, {
    label = "Drink Below Mana %",
    tab = "healing",
    tooltip = "Drinking starts at 35% mana or lower and continues until mana is 100%.",
})
menu:checkbox("mfg_potions", true, {
    label = "Use Potions",
    tab = "healing",
})
menu:checkbox("mfg_quest_debug", false, {
    label = "Log quest dialog steps",
    tab = "healing",
    tooltip = "Prints each step of a quest accept or hand-in, every reward choice considered, how it was rated, and which one was taken.",
})
menu:checkbox("mfg_rest_debug", false, {
    label = "Log why resting is blocked",
    tab = "healing",
    tooltip = "Prints the one gate that is currently stopping the bot from eating or drinking - combat, swimming, movement, an empty bag, or the client refusing the item. Once per second, only when it changes.",
})
menu:slider_int("mfg_hp_pot", 10, 60, 35, {
    label = "Health Potion %",
    tab = "healing",
})
menu:slider_int("mfg_mp_pot", 5, 50, 20, {
    label = "Mana Potion %",
    tab = "healing",
})

menu:checkbox("mfg_random_path", false, {
    label = "Random Patrol Skip",
    tab = "grind",
})
menu:slider_int("mfg_max_kill", 15, 180, 60, {
    label = "Max Kill Time (s)",
    tab = "grind",
})
menu:checkbox("mfg_fight_back", true, {
    label = "Fight Back",
    tab = "grind",
})
menu:slider_int("mfg_fight_back_hp", 20, 90, 70, {
    label = "Fight Back HP %",
    tab = "grind",
})
menu:slider_int("mfg_fight_back_yards", 10, 80, 30, {
    label = "Fight Back Range",
    tab = "grind",
})
menu:checkbox("mfg_atk_any", false, {
    label = "Attack Any Level",
    tab = "grind",
    tooltip = "Attack every valid enemy in range, regardless of level. Only one level option can be on.",
})
menu:checkbox("mfg_atk_5", false, {
    label = "Attack within 5 levels",
    tab = "grind",
    tooltip = "Attack enemies 5 levels below, the same level, or 5 levels above you. Only one level option can be on.",
})
menu:checkbox("mfg_atk_3", true, {
    label = "Attack within 3 levels",
    tab = "grind",
    tooltip = "Attack enemies 3 levels below, the same level, or 3 levels above you. Only one level option can be on.",
})
menu:checkbox("mfg_untapped", true, {
    label = "Skip Tapped Mobs",
    tab = "grind",
})
menu:checkbox("mfg_loot", true, {
    label = "Loot Corpses",
    tab = "grind",
    tooltip = "Loot dead enemies after a kill. Walks in if the corpse is within 40 yards (my kills) or 10 yards (all nearby).",
})
menu:checkbox("mfg_loot_mine", true, {
    label = "Loot My Kills Only",
    tab = "grind",
    tooltip = "Only loot corpses this bot marked as killed. Off = loot any lootable corpse within 10 yards.",
})

menu:combobox("mfg_quest", 1, { "(no starter quests)" }, {
    label = "Starter Quest",
    tab = "quest",
    skip_draw = true,
    tooltip = "Starter quests from quest/data for the loaded race. Pick one to inspect start/end NPCs.",
})
menu:checkbox("mfg_skip_trivial", true, {
    label = "Skip Grey Quests",
    tab = "quest",
    tooltip = "Skip a quest the NPC reports as trivial (grey). Grey quests award almost no experience, so running them costs more time than they return.",
})
menu:checkbox("mfg_quest_force", false, {
    label = "Use Selected Quest",
    tab = "quest",
    tooltip = "Stay on the quest chosen in this panel instead of auto-picking the next unfinished starter.",
})

menu:checkbox("mfg_vendor_sell", true, {
    label = "Sell at Vendor",
    tab = "vendor",
    tooltip = "Walk to the zone merchant when free bag slots drop to the trigger.",
})
menu:checkbox("mfg_repair", true, {
    label = "Repair at Vendor",
    tab = "vendor",
    tooltip = "Walk to the zone merchant when equipped durability is at or below the trigger.",
})
menu:checkbox("mfg_sell_grey", true, {
    label = "Sell Grey",
    tab = "vendor",
})
menu:checkbox("mfg_sell_white", true, {
    label = "Sell White",
    tab = "vendor",
})
menu:checkbox("mfg_sell_green", false, {
    label = "Sell Green",
    tab = "vendor",
    tooltip = "Off by default. Greens can be upgrades.",
})
menu:slider_int("mfg_bag_free", 1, 10, 1, {
    label = "Vendor at Free Slots",
    tab = "vendor",
})
menu:checkbox("mfg_vendor_each_lap", true, {
    label = "Vendor Every Lap",
    tab = "vendor",
    tooltip = "On an Alliance 1-60 w/Vendoring loop that names a merchant, sell and repair once per completed lap. Those routes begin and end at their vendor, so the stop costs no extra travel. Routes with no vendor in their notes are unaffected.",
})
menu:slider_int("mfg_repair_pct", 5, 50, 10, {
    label = "Repair at Durability %",
    tab = "vendor",
})

menu:checkbox("mfg_show_gui", true, {
    label = "Show GUI",
    tab = "settings",
})

menu:add_popup({
    id = "path",
    title = "Load Profile",
    tab = "path",
    w = 460,
    h = 720,
    x = 870,
    y = 36,
    on_open = function()
        gui.sync_profile_list(true)
    end,
})
menu:add_popup({
    id = "quest",
    title = "Quests",
    tab = "quest",
    w = 460,
    h = 640,
    x = 870,
    y = 56,
})
menu:add_popup({
    id = "vendor",
    title = "Vendor",
    tab = "vendor",
    w = 440,
    h = 480,
    x = 870,
    y = 76,
})
-- The profile picker.
--
-- A dropdown was the wrong widget for this. It shows 18 rows at most, scrolls
-- inside a 30px field, and gives no room for the level range or whether a route
-- has a vendor - the three things you choose on. A popup can list every route
-- at once with that detail on the row.
--
-- Height is computed from the route count rather than fixed, so the window is
-- the size of its contents: PROFILE_ROW per route, plus the header and the
-- footer line, capped so it cannot grow taller than a screen.
local PROFILE_ROW = 24
local PROFILE_HEAD = 58
local PROFILE_FOOT = 30
local PROFILE_MAX_H = 900

--- Height that shows every route of the LARGEST faction without scrolling.
---
--- Sized from the catalog at creation, not from the current selection: the
--- popup's height is fixed when it is registered, and sizing it to whichever
--- faction happened to be active would leave the other one scrolling. The cap
--- is a screen-height guard, not a row budget.
local function profile_popup_height()
    local n = 0
    local ok, grind_catalog = pcall(require, "grind/catalog")
    if ok and grind_catalog and type(grind_catalog.faction_counts) == "function" then
        local counts = grind_catalog.faction_counts() or {}
        for _, c in pairs(counts) do
            if type(c) == "number" and c > n then
                n = c
            end
        end
    end
    if n < 1 then
        n = 1
    end
    local h = PROFILE_HEAD + (n * PROFILE_ROW) + PROFILE_FOOT
    if h > PROFILE_MAX_H then
        h = PROFILE_MAX_H
    end
    return h
end

-- Height from the spellbook, the same way the profile picker sizes from the
-- catalog. A caster at 60 knows well over a hundred spells, so this one is
-- capped and scrolls; the count in the footer says how much is below the fold.
local SPELL_ROW = 22

menu:add_popup({
    id = "spells",
    title = "All Known Spells",
    tab = "spells",
    w = 460,
    h = 700,
    x = 700,
    y = 60,
})

menu:add_popup({
    id = "profiles",
    title = "Choose a Grind Profile",
    tab = "profiles",
    w = 520,
    h = profile_popup_height(),
    x = 720,
    y = 40,
    on_open = function()
        gui.sync_profile_list(true)
    end,
})

menu:add_popup({
    id = "grind",
    title = "Grind",
    tab = "grind",
    w = 440,
    h = 640,
    x = 870,
    y = 96,
})

local keybinds = {
    enable = core.menu.keybind(996, false, "mfg_kb_start"),
    pause = core.menu.keybind(997, false, "mfg_kb_pause"),
    stop = core.menu.keybind(998, false, "mfg_kb_stop"),
}

local aliases = {
    enable = "mfg_enable",
    player_detect = "mfg_player_detect",
    eat_drink = "mfg_eat_drink",
    potions = "mfg_potions",
    rest_debug = "mfg_rest_debug",
    quest_debug = "mfg_quest_debug",
    skip_trivial = "mfg_skip_trivial",
    train = "mfg_train",
    vendor_each_lap = "mfg_vendor_each_lap",
    random_path = "mfg_random_path",
    fight_back = "mfg_fight_back",
    untapped = "mfg_untapped",
    loot = "mfg_loot",
    loot_mine = "mfg_loot_mine",
    sell = "mfg_vendor_sell",
    repair = "mfg_repair",
    sell_grey = "mfg_sell_grey",
    sell_white = "mfg_sell_white",
    sell_green = "mfg_sell_green",
    path_loop = "mfg_path_loop",
    path_reverse = "mfg_path_reverse",
    path_combat = "mfg_path_combat",
    draw_path = "mfg_draw_path",
    move_debug = "mfg_move_debug",
    rotation_only = "mfg_rotation_only",
    quest_force = "mfg_quest_force",
    use_grind = "mfg_use_grind",
    use_quest = "mfg_use_quest",
    show_gui = "mfg_show_gui",
    -- Hunter / Warlock / Shaman / Rogue rotations
    aspect_hawk = "mfg_aspect_hawk",
    trueshot = "mfg_trueshot",
    hunter_pet = "mfg_hunter_pet",
    mend_pet = "mfg_mend_pet",
    hunters_mark = "mfg_hunters_mark",
    serpent_sting = "mfg_serpent_sting",
    arcane_shot = "mfg_arcane_shot",
    steady_shot = "mfg_steady_shot",
    multi_shot = "mfg_multi_shot",
    concussive = "mfg_concussive",
    hunter_debug = "mfg_hunter_debug",
    warlock_armour = "mfg_warlock_armour",
    health_funnel = "mfg_health_funnel",
    corruption = "mfg_corruption",
    curse_agony = "mfg_curse_agony",
    immolate = "mfg_immolate",
    shadow_bolt = "mfg_shadow_bolt",
    drain_life = "mfg_drain_life",
    life_tap = "mfg_life_tap",
    warlock_debug = "mfg_warlock_debug",
    enhancement = "mfg_enhancement",
    lightning_shield = "mfg_lightning_shield",
    flame_shock = "mfg_flame_shock",
    earth_shock = "mfg_earth_shock",
    frost_shock = "mfg_frost_shock",
    lightning_bolt = "mfg_lightning_bolt",
    healing_wave = "mfg_healing_wave",
    shaman_debug = "mfg_shaman_debug",
    sinister_strike = "mfg_sinister_strike",
    backstab = "mfg_backstab",
    slice_dice = "mfg_slice_dice",
    rupture = "mfg_rupture",
    eviscerate = "mfg_eviscerate",
    evasion = "mfg_evasion",
    kick = "mfg_kick",
    rogue_debug = "mfg_rogue_debug",
    -- Supplies (supplies.lua)
    buy_supplies = "mfg_buy_supplies",
    vendor_debug = "mfg_vendor_debug",
    -- Auto-equip (equip.lua)
    auto_equip = "mfg_auto_equip",
    equip_weapons = "mfg_equip_weapons",
    equip_debug = "mfg_equip_debug",
    -- Druid (rotations/druid.lua)
    mark_of_wild = "mfg_mark_of_wild",
    thorns = "mfg_thorns",
    moonfire = "mfg_moonfire",
    wrath = "mfg_wrath",
    faerie_fire = "mfg_faerie_fire",
    entangling = "mfg_entangling",
    rejuvenation = "mfg_rejuvenation",
    regrowth = "mfg_regrowth",
    healing_touch = "mfg_healing_touch",
    druid_debug = "mfg_druid_debug",
    -- Paladin (rotations/paladin.lua)
    blessing = "mfg_blessing",
    seal = "mfg_seal",
    judgement = "mfg_judgement",
    crusader_strike = "mfg_crusader_strike",
    hammer_wrath = "mfg_hammer_wrath",
    consecration = "mfg_consecration",
    flash_light = "mfg_flash_light",
    holy_light = "mfg_holy_light",
    paladin_debug = "mfg_paladin_debug",
    -- Priest (rotations/priest.lua)
    pw_fortitude = "mfg_pw_fortitude",
    inner_fire = "mfg_inner_fire",
    shadowform = "mfg_shadowform",
    pw_shield = "mfg_pw_shield",
    swp = "mfg_swp",
    mind_blast = "mfg_mind_blast",
    mind_flay = "mfg_mind_flay",
    smite = "mfg_smite",
    renew = "mfg_renew",
    flash_heal = "mfg_flash_heal",
    priest_debug = "mfg_priest_debug",
    ice_armor = "mfg_ice_armor",
    mage_armor = "mfg_mage_armor",
    molten_armor = "mfg_molten_armor",
    ice_barrier = "mfg_ice_barrier",
    mana_shield = "mfg_mana_shield",
    icy_veins = "mfg_icy_veins",
    presence_of_mind = "mfg_presence_of_mind",
    combustion = "mfg_combustion",
    arcane_power = "mfg_arcane_power",
    frostbolt = "mfg_frostbolt",
    fireball = "mfg_fireball",
    scorch = "mfg_scorch",
    arcane_missiles = "mfg_arcane_missiles",
    pyroblast = "mfg_pyroblast",
    fire_blast = "mfg_fire_blast",
    frost_nova = "mfg_frost_nova",
    ice_lance = "mfg_ice_lance",
    cone = "mfg_cone",
    flamestrike = "mfg_flamestrike",
    blizzard = "mfg_blizzard",
    blast_wave = "mfg_blast_wave",
    dragons_breath = "mfg_dragons_breath",
    water_ele = "mfg_water_ele",
    counterspell = "mfg_counterspell",
    mage_wand = "mfg_mage_wand",
    atk_any = "mfg_atk_any",
    atk_5 = "mfg_atk_5",
    atk_3 = "mfg_atk_3",
}

local slider_aliases = {
    player_yards = "mfg_player_yards",
    train_reserve = "mfg_train_reserve",
    eat_hp = "mfg_eat_hp",
    drink_mana = "mfg_drink_mana",
    hp_pot = "mfg_hp_pot",
    mp_pot = "mfg_mp_pot",
    max_kill = "mfg_max_kill",
    fight_back_hp = "mfg_fight_back_hp",
    fight_back_yards = "mfg_fight_back_yards",
    bag_free = "mfg_bag_free",
    repair_pct = "mfg_repair_pct",
    -- class self-heal thresholds (rotations/*.lua read these via gui.slider)
    pet_heal_pct = "mfg_pet_heal_pct",
    warlock_heal_pct = "mfg_warlock_heal_pct",
    shaman_heal_pct = "mfg_shaman_heal_pct",
    combo_finish = "mfg_combo_finish",
    evasion_pct = "mfg_evasion_pct",
    food_target = "mfg_food_target",
    drink_target = "mfg_drink_target",
    priest_heal_pct = "mfg_priest_heal_pct",
    druid_heal_pct = "mfg_druid_heal_pct",
    paladin_heal_pct = "mfg_paladin_heal_pct",
}

-- Combobox ids read via gui.combo(). Kept separate from checkbox and slider
-- aliases because gui.slider() only accepts numbers and gui.is_on() only
-- booleans, so a dropdown routed through either silently returns the fallback.
local combo_aliases = {
    class = "mfg_class",
    paladin_aura = "mfg_paladin_aura",
    warlock_pet = "mfg_warlock_pet",
    shaman_imbue = "mfg_shaman_imbue",
}

local function checkbox_element(key)
    local id = aliases[key] or key
    return menu:element(id)
end

local function keybind_enabled(element)
    if not element then
        return nil
    end
    local ok, st = pcall(function()
        return plugin_helper:is_toggle_enabled(element)
    end)
    if ok and type(st) == "boolean" then
        return st
    end
    ok, st = pcall(function()
        return element:get_state()
    end)
    if ok and type(st) == "boolean" then
        return st
    end
    return nil
end

local function is_on(key)
    local id = aliases[key] or key
    local via_menu = menu:get(id)
    if type(via_menu) == "boolean" then
        return via_menu
    end
    local element = checkbox_element(key)
    if element then
        local ok, st = pcall(function()
            return element:get_state()
        end)
        if ok and type(st) == "boolean" then
            return st
        end
        ok, st = pcall(function()
            return element:get()
        end)
        if ok and type(st) == "boolean" then
            return st
        end
    end
    local kb = keybinds[key]
    if kb then
        local kb_state = keybind_enabled(kb)
        if type(kb_state) == "boolean" then
            return kb_state
        end
    end
    if key == "path_combat" then
        return true
    end
    return false
end

local function set_on(key, value)
    local on = value == true
    local element = checkbox_element(key)
    if element then
        pcall(function()
            element:set(on)
        end)
    end
    if keybinds[key] then
        pcall(function()
            keybinds[key]:set_toggle_state(on)
        end)
    end
end

gui.is_on = is_on
gui.set_on = set_on

local ATK_IDS = {
    any = "mfg_atk_any",
    five = "mfg_atk_5",
    three = "mfg_atk_3",
}
local last_atk_mode = "three"

local function apply_atk_mode(mode)
    if mode ~= "any" and mode ~= "five" and mode ~= "three" then
        mode = "three"
    end
    last_atk_mode = mode
    menu:set(ATK_IDS.any, mode == "any")
    menu:set(ATK_IDS.five, mode == "five")
    menu:set(ATK_IDS.three, mode == "three")
end

function gui.sync_attack_level()
    local any = menu:get(ATK_IDS.any) == true
    local five = menu:get(ATK_IDS.five) == true
    local three = menu:get(ATK_IDS.three) == true
    local n = (any and 1 or 0) + (five and 1 or 0) + (three and 1 or 0)
    if n == 1 then
        if any then
            last_atk_mode = "any"
        elseif five then
            last_atk_mode = "five"
        else
            last_atk_mode = "three"
        end
        return
    end
    if n == 0 then
        apply_atk_mode(last_atk_mode)
        return
    end
    if any and last_atk_mode ~= "any" then
        apply_atk_mode("any")
    elseif five and last_atk_mode ~= "five" then
        apply_atk_mode("five")
    elseif three and last_atk_mode ~= "three" then
        apply_atk_mode("three")
    else
        apply_atk_mode(last_atk_mode)
    end
end

function gui.attack_level_band()
    gui.sync_attack_level()
    if menu:get(ATK_IDS.any) == true then
        return nil
    end
    if menu:get(ATK_IDS.five) == true then
        return 5
    end
    return 3
end

function gui.slider(key, fallback)
    local id = slider_aliases[key] or key
    local value = menu:get(id)
    if type(value) == "number" then
        return value
    end
    return fallback
end

--- Read a combobox as a 1-based index. Returns `fallback` when the element is
--- missing or has not been resolved yet, so a caller never has to guard nil.
function gui.combo(key, fallback)
    local id = combo_aliases[key] or key
    local value = menu:get(id)
    if type(value) == "number" then
        return value
    end
    return fallback
end

function gui.get_menu()
    return menu
end

function gui.mode()
    if is_on("use_quest") then
        return modes.QUEST
    end
    if is_on("use_grind") then
        return modes.GRIND
    end
    return nil
end

local path_source = "travel"
local armed_path = nil
local play_pending = false
local last_region_idx = nil
local last_path_key = ""
local picker_cache = {}
local picker_cache_key = ""

--- The faction whose routes the Grinding tab is listing, and its index.
---
--- Defaults to the character's own side the first time a player object is
--- available, so an Alliance character opens on Alliance routes without
--- touching anything. After that the player's choice sticks.
local faction_synced = false

function gui.faction_key()
    local idx = menu:get("mfg_faction")
    if type(idx) ~= "number" or idx < 1 or idx > #factions.keys then
        idx = 1
    end
    return factions.key_at(idx), idx
end

--- Point the selector at the character's own side, once.
---
--- It will NOT move you to a side that has no routes. Auto-selecting Horde on
--- a Horde character is correct in principle and useless in practice while
--- every shipped route is Alliance: the list goes empty and it looks as though
--- the profiles have vanished. So a side with nothing in it is not selected,
--- and the reason is logged once.
function gui.sync_faction(player)
    if faction_synced or not player then
        return
    end
    local key, how = factions.of_player(player)
    if not key then
        return
    end
    faction_synced = true

    local counts = {}
    local ok, grind_catalog = pcall(require, "grind/catalog")
    if ok and grind_catalog and type(grind_catalog.faction_counts) == "function" then
        counts = grind_catalog.faction_counts() or {}
    end

    if (counts[key] or 0) <= 0 then
        local fallback = nil
        for i = 1, #factions.keys do
            local k = factions.keys[i]
            if (counts[k] or 0) > 0 then
                fallback = k
                break
            end
        end
        core.log(string.format(
            "[Master Farmer - Grindbot] Detected %s (%s), which has no grind routes. %s",
            key, tostring(how),
            fallback and ("Showing " .. fallback .. " routes instead.")
                or "No routes are available for either side."))
        if not fallback then
            return
        end
        key = fallback
    else
        core.log(string.format("[Master Farmer - Grindbot] Faction: %s (from %s), %d routes.",
            key, tostring(how), counts[key] or 0))
    end

    local want = factions.index_of(key)
    if menu:get("mfg_faction") ~= want then
        menu:set("mfg_faction", want)
        picker_cache_key = ""
        last_path_key = ""
    end
end

function gui.region_key()
    -- The Continent control is gone. Travel paths still index by region, so
    -- this answers with the only region that has any, rather than nil.
    local idx = 1
    if type(idx) ~= "number" or idx < 1 then
        idx = 1
    end
    if idx > #REGION_KEYS then
        idx = #REGION_KEYS
    end
    return REGION_KEYS[idx], idx
end

local function clamp_index(idx, n)
    if type(idx) ~= "number" or idx < 1 then
        idx = 1
    end
    if n < 1 then
        return 1
    end
    if idx > n then
        return n
    end
    return idx
end

local function add_picker_rows(rows, kind, source, labels, ids)
    for i = 1, #labels do
        local raw = labels[i]
        local prefix = "Travel - "
        if kind == "grind" then
            prefix = "Grind - "
        end
        rows[#rows + 1] = {
            kind = kind,
            source = source,
            index = i,
            id = ids and ids[i] or nil,
            name = raw,
            label = prefix .. tostring(raw),
        }
    end
end

function gui.picker_entries()
    if not is_on("use_grind") then
        return {
            {
                kind = "none",
                source = "",
                index = 0,
                id = nil,
                name = EMPTY_PATH,
                label = EMPTY_PATH,
            },
        }
    end
    local key, region = gui.faction_key()
    local cache_key = tostring(region) .. "|" .. tostring(key)
    if picker_cache_key == cache_key and type(picker_cache) == "table" and #picker_cache > 0 then
        return picker_cache, key, region
    end
    local ok, grind_catalog = pcall(require, "grind/catalog")
    local rows = {}
    if ok and grind_catalog then
        local grind_labels = grind_catalog.labels_for_faction(key)
        local grind_ids = {}
        local entries = grind_catalog.entries_for_faction(key)
        for i = 1, #entries do
            grind_ids[i] = entries[i].id
        end
        add_picker_rows(rows, "grind", "lvlgrind", grind_labels, grind_ids)
    end

    if #rows == 0 then
        rows[1] = {
            kind = "none",
            source = "",
            index = 0,
            id = nil,
            name = EMPTY_PATH,
            label = EMPTY_PATH,
        }
    end
    picker_cache = rows
    picker_cache_key = cache_key
    return rows, key, region
end

function gui.combo_labels()
    local rows = gui.picker_entries()
    local labels = {}
    for i = 1, #rows do
        labels[i] = rows[i].label
    end
    return labels
end

function gui.travel_labels()
    return gui.combo_labels()
end

function gui.leveling_labels()
    return gui.combo_labels()
end

-- The chosen route index.
--
-- This used to be read straight back out of the mfg_path COMBOBOX ELEMENT,
-- and that is what hid most of the list. That element is created with a single
-- placeholder item and its item list is only refreshed by sync_profile_list,
-- so a real combobox widget - which cannot select an index it has no item for
-- - clamped every set() to whatever stale count it happened to be holding.
-- The dropdown showed all 27 routes and picking anything past the clamp
-- snapped straight back.
--
-- The index is ours, so we keep it. The element is still mirrored for the
-- older popups, but nothing reads the selection back out of it.
local selected_path = 1

local function live_path_count()
    local labels = gui.combo_labels()
    local n = #labels
    if n == 1 and labels[1] == EMPTY_PATH then
        n = 0
    end
    return n, labels
end

function gui.path_index()
    local n = live_path_count()
    return clamp_index(selected_path, n)
end

--- Choose a route. Clamped against the list as it is right now, never against
--- whatever the widget last heard about.
function gui.set_path_index(index)
    local n, labels = live_path_count()
    selected_path = clamp_index(index, n)
    -- Keep the element in step for the legacy popups: items FIRST, or the set
    -- is clamped away again.
    pcall(function()
        menu:set_combobox_items("mfg_path", labels)
        menu:set("mfg_path", selected_path)
    end)
    return selected_path
end

function gui.level_index()
    return gui.path_index()
end

function gui.selected_picker()
    local rows = gui.picker_entries()
    local idx = gui.path_index()
    return rows[idx]
end

function gui.profile_file()
    local row = gui.selected_picker()
    if not row or row.source ~= "custom" then
        return nil
    end
    return row.id
end

local function arm_path(path, kind)
    if not path then
        return path
    end
    if type(path.kind) ~= "string" or path.kind == "" then
        path.kind = kind
    end
    local okp, path_profiles = pcall(require, "path_profiles")
    if okp and path_profiles and type(path_profiles.remember) == "function" then
        path_profiles.remember(path)
    end
    armed_path = path
    return path
end

function gui.load_travel_path()
    local row = gui.selected_picker()
    local key, region = gui.region_key()
    path_source = "travel"
    local path, err = nil, nil
    if row and row.source == "custom" then
        path_profiles.prepare()
        path_profiles.apply_region(region)
        local file = row.id
        if file then
            path, err = path_profiles.load_file(file)
        else
            err = "no travel path"
        end
    else
        local index = row and row.index or 1
        path, err = path_catalog.load_region(key, index)
        if not path then
            local entries = path_catalog.entries_for_region(key)
            local entry = entries[index]
            if entry and type(path_profiles.seed_one) == "function" then
                path_profiles.seed_one(entry)
                local file = (entry.id or "path") .. ".json"
                path, err = path_profiles.load_file(file)
            end
        end
    end
    return arm_path(path, "travel"), err
end

function gui.load_grind_path()
    local row = gui.selected_picker()
    local key = gui.faction_key()
    path_source = "leveling"
    local index = row and row.index or 1
    local ok, grind_catalog = pcall(require, "grind/catalog")
    if not ok or not grind_catalog then
        return nil, "grind catalog not loaded"
    end
    local path, err = grind_catalog.load_faction(key, index)
    return arm_path(path, "grind"), err
end

function gui.load_selected_path()
    local row = gui.selected_picker()
    if not row or row.kind == "none" then
        return nil, "no path"
    end
    if row.kind == "grind" then
        return gui.load_grind_path()
    end
    return gui.load_travel_path()
end

function gui.ready_path()
    if type(armed_path) == "table" then
        return armed_path
    end
    return gui.load_selected_path()
end

function gui.sync_profile_list(restore_selected)
    if not is_on("use_grind") then
        picker_cache_key = ""
        last_path_key = ""
        menu:set_combobox_items("mfg_path", { EMPTY_PATH })
        gui.set_path_index(1)
        return
    end
    picker_cache_key = ""
    local key, region = gui.faction_key()
    local loaded = armed_path
    if restore_selected == true and loaded and type(loaded.faction) == "string" then
        region = factions.index_of(string.lower(loaded.faction))
        menu:set("mfg_faction", region)
        key = factions.key_at(region)
        picker_cache_key = ""
    end
    local labels = gui.combo_labels()
    local path_key = tostring(region) .. "|all|" .. table.concat(labels, "\n")
    if path_key ~= last_path_key then
        menu:set_combobox_items("mfg_path", labels)
        last_path_key = path_key
        if last_region_idx ~= nil and region ~= last_region_idx and restore_selected ~= true then
            gui.set_path_index(1)
        end
    end
    if restore_selected == true then
        loaded = armed_path
        local want = loaded and (loaded.name or loaded.id) or nil
        local want_id = loaded and loaded.id or nil
        if type(want) == "string" and want ~= "" then
            local rows = gui.picker_entries()
            for i = 1, #rows do
                local row = rows[i]
                if row.name == want or row.id == want or row.id == want_id or row.label == want then
                    gui.set_path_index(i)
                    if row.kind == "grind" then
                        path_source = "leveling"
                    else
                        path_source = "travel"
                    end
                    break
                end
            end
        end
    end
    last_region_idx = region
end

function gui.class_id()
    local idx = menu:get("mfg_class")
    if type(idx) ~= "number" then
        idx = 7
    end
    return CLASS_IDS[idx] or enums.class_id.MAGE
end

function gui.sync_player(player)
    if not player then
        return
    end
    local class_id = nil
    pcall(function()
        class_id = player:get_class()
    end)
    -- The race drives which racial toggles appear on the Class tab.
    local race_id = nil
    pcall(function()
        race_id = player:get_race_id()
    end)
    if type(race_id) == "number" then
        menu:set_player_race(race_id)
    end
    gui.sync_faction(player)
    if not class_id then
        return
    end
    menu:set_player_class(class_id)
    for i = 1, #CLASS_IDS do
        if CLASS_IDS[i] == class_id then
            menu:set("mfg_class", i)
            break
        end
    end
end

function gui.has_grind_profile()
    if not is_on("use_grind") then
        return false
    end
    local row = gui.selected_picker()
    return row ~= nil and row.kind == "grind"
end

function gui.has_quest_profile()
    if not is_on("use_quest") then
        return false
    end
    local ok, q = pcall(require, "quest")
    if not ok or not q or type(q.row_at) ~= "function" then
        return false
    end
    local row = q.row_at(izi.me(), gui.quest_index())
    return type(row) == "table" and type(row.id) == "number"
end

function gui.is_started()
    if not is_on("enable") then
        return false
    end
    local g = is_on("use_grind")
    local q = is_on("use_quest")
    if g == q then
        return false
    end
    if g and not gui.has_grind_profile() then
        return false
    end
    if q and not gui.has_quest_profile() then
        return false
    end
    local ok, rotation = pcall(require, "rotation")
    if not ok or type(rotation) ~= "table" then
        return false
    end
    local me = nil
    pcall(function()
        me = izi.me()
    end)
    local class_id = me and me.get_class and me:get_class() or gui.class_id()
    return rotation.supported(class_id) == true
end

menu.on_close = function()
    set_on("show_gui", false)
end

_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot
NS._sessions = NS._sessions or {}
local MY_SESSION = NS._sessions[identity.folder]

local last_toggle_at = { enable = -1, show_gui = -1 }
local last_activity = nil

local function can_start()
    local ok, rotation = pcall(require, "rotation")
    if not ok or type(rotation) ~= "table" then
        return false
    end
    local me = nil
    pcall(function()
        me = izi.me()
    end)
    local class_id = me and me.get_class and me:get_class() or nil
    if not class_id then
        return false
    end
    return rotation.supported(class_id) == true
end

local function start_bot()
    if NS._sessions[identity.folder] ~= MY_SESSION then
        return
    end
    gui.sync_activity()
    local g = is_on("use_grind")
    local q = is_on("use_quest")
    if g == q then
        core.log("[Master Farmer - Grindbot] Start blocked: check Grinding or Quest (not both).")
        state.set_note("Start", "Check Grinding or Quest")
        return
    end
    if not can_start() then
        core.log("[Master Farmer - Grindbot] Start blocked: no rotation for this class.")
        return
    end
    if g then
        loader.ensure_grind()
        gui.sync_profile_list(false)
        local path, err = gui.load_grind_path()
        if not path then
            core.log("[Master Farmer - Grindbot] Start blocked: choose a grind profile.")
            state.set_note("Start", err or "Choose a grind profile")
            return
        end
        local grind = loader.grind()
        if grind and type(grind.set_profile) == "function" then
            grind.set_profile(path)
        end
        menu:set("mfg_mode", 1)
    else
        loader.ensure_quest()
        local quest = loader.quest()
        local row = quest and quest.row_at and quest.row_at(izi.me(), gui.quest_index()) or nil
        if type(row) ~= "table" or type(row.id) ~= "number" then
            core.log("[Master Farmer - Grindbot] Start blocked: choose a quest profile.")
            state.set_note("Start", "Choose a quest profile")
            return
        end
        menu:set("mfg_quest_force", true)
        menu:set("mfg_mode", 2)
    end
    set_on("enable", true)
    state.set_note("Start", g and "Grinding" or "Quest")
end

function gui.try_start()
    start_bot()
end

function gui.apply_pending_play()
    return nil
end

function gui.quest_index()
    local idx = menu:get("mfg_quest")
    if not is_on("use_quest") then
        return clamp_index(idx, 1)
    end
    local n = 1
    local ok, q = pcall(require, "quest")
    if ok and q and type(q.labels) == "function" then
        local labels = q.labels(izi.me())
        if type(labels) == "table" and #labels > 0 then
            n = #labels
        end
    end
    return clamp_index(idx, n)
end

function gui.use_quest_mode()
    set_on("use_quest", true)
    set_on("use_grind", false)
    gui.sync_activity()
end

function gui.skip_selected_quest()
    local ok, q = pcall(require, "quest")
    if not ok or not q or type(q.row_at) ~= "function" then
        return
    end
    local row = q.row_at(izi.me(), gui.quest_index())
    if type(row) ~= "table" or type(row.id) ~= "number" then
        return
    end
    if type(state.quest.skipped) ~= "table" then
        state.quest.skipped = {}
    end
    state.quest.skipped[row.id] = true
    state.set_note("Quest", "Skipped " .. tostring(row.name or row.id))
end

function gui.clear_quest_skips()
    state.quest.skipped = {}
    state.set_note("Quest", "Cleared skipped quests")
end

local function pause_bot()
    set_on("enable", false)
end

local function stop_bot()
    set_on("enable", false)
    local ok, movement = pcall(require, "movement")
    if ok and movement and type(movement.nav_stop) == "function" then
        movement.nav_stop()
    end
    local ok_path, path_runner = pcall(require, "path_runner")
    if ok_path and path_runner and type(path_runner.stop) == "function" then
        path_runner.stop()
    end
    local ok_vendor, vendor = pcall(require, "vendor")
    if ok_vendor and vendor and type(vendor.reset) == "function" then
        vendor.reset()
    end
end

local function toggle_gui()
    local now = core.time()
    if type(now) ~= "number" then
        now = 0
    end
    if now - (last_toggle_at.show_gui or -1) < 0.20 then
        return
    end
    last_toggle_at.show_gui = now
    set_on("show_gui", not is_on("show_gui"))
end

local unsubs = {}
local function watch_key(code, fn)
    local ok, unsub = pcall(function()
        return izi.on_key_release(code, fn)
    end)
    if ok and type(unsub) == "function" then
        unsubs[#unsubs + 1] = unsub
    end
end

if type(NS.unbind_hotkeys) == "function" then
    pcall(NS.unbind_hotkeys)
    NS.unbind_hotkeys = nil
end

watch_key(996, start_bot)
watch_key(1006, start_bot)
watch_key(0x60, start_bot)
watch_key(997, pause_bot)
watch_key(0x61, pause_bot)
watch_key(998, stop_bot)
watch_key(0x62, stop_bot)
watch_key(1000, toggle_gui)
watch_key(0x64, toggle_gui)
watch_key(0x25, toggle_gui)

NS.unbind_hotkeys = function()
    for i = 1, #unsubs do
        pcall(unsubs[i])
    end
end

local KEY_CODES = {
    enable = { 0x60 },
    pause = { 0x61 },
    stop = { 0x62 },
    show_gui = { 0x64, 0x25 },
}
local key_was_down = { enable = false, pause = false, stop = false, show_gui = false }

local function key_is_down(codes)
    for i = 1, #codes do
        local ok, pressed = pcall(function()
            return core.input.is_key_pressed(codes[i])
        end)
        if ok and pressed == true then
            return true
        end
    end
    return false
end

function gui.sync_activity()
    local g = is_on("use_grind")
    local q = is_on("use_quest")
    if g and q then
        if last_activity == "grind" then
            set_on("use_quest", false)
            q = false
        else
            set_on("use_grind", false)
            g = false
        end
    end
    if g then
        if last_activity ~= "grind" then
            last_activity = "grind"
            set_on("enable", false)
            loader.unload_quest()
            loader.ensure_grind()
            picker_cache_key = ""
            gui.sync_profile_list(false)
            menu:set("mfg_mode", 1)
            state.set_note("Mode", "Grinding - choose a profile, then Start")
        end
        return
    end
    if q then
        if last_activity ~= "quest" then
            last_activity = "quest"
            set_on("enable", false)
            loader.unload_grind()
            armed_path = nil
            loader.ensure_quest()
            menu:set("mfg_mode", 2)
            state.set_note("Mode", "Quest - choose a profile, then Start")
        end
        return
    end
    if last_activity ~= nil then
        last_activity = nil
        set_on("enable", false)
        loader.unload_grind()
        loader.unload_quest()
        armed_path = nil
        picker_cache_key = ""
        last_path_key = ""
        menu:set_combobox_items("mfg_path", { EMPTY_PATH })
        menu:set_combobox_items("mfg_quest", { EMPTY_QUEST })
        state.set_note("Mode", "Select Grinding or Quest")
    end
end

function gui.process_keybinds()
    gui.sync_attack_level()
    gui.sync_activity()
    if key_is_down(KEY_CODES.enable) and not key_was_down.enable then
        start_bot()
    end
    if key_is_down(KEY_CODES.pause) and not key_was_down.pause then
        pause_bot()
    end
    if key_is_down(KEY_CODES.stop) and not key_was_down.stop then
        stop_bot()
    end
    if key_is_down(KEY_CODES.show_gui) and not key_was_down.show_gui then
        toggle_gui()
    end
    key_was_down.enable = key_is_down(KEY_CODES.enable)
    key_was_down.pause = key_is_down(KEY_CODES.pause)
    key_was_down.stop = key_is_down(KEY_CODES.stop)
    key_was_down.show_gui = key_is_down(KEY_CODES.show_gui)
end

local function class_status()
    local ok, rotation = pcall(require, "rotation")
    local idx = menu:get("mfg_class") or 7
    local name = CLASS_LABELS[idx] or "?"
    if ok and rotation and rotation.supported(CLASS_IDS[idx]) then
        return name .. " - ready"
    end
    return name .. " - no rotation yet"
end

local function mode_status()
    if gui.mode() == modes.QUEST then
        return "Quest"
    end
    if gui.mode() == modes.GRIND then
        return "Grind"
    end
    return "Idle"
end

menu:set_status({
    {
        label = "State",
        value = function()
            return gui.is_started() and "Running" or "Idle"
        end,
        color = function()
            if gui.is_started() then
                return color.new(90, 210, 110, 255)
            end
            return color.new(210, 78, 78, 255)
        end,
    },
    { label = "Class", value = class_status },
    { label = "Mode", value = mode_status },
    {
        label = "Note",
        value = function()
            return state.note ~= "" and state.note or "-"
        end,
    },
    {
        -- Movement state machine at a glance: which state, who owns the player,
        -- and why it is not moving when it is not moving.
        label = "Movement",
        value = function()
            local ok, movement = pcall(require, "movement")
            if not ok or not movement then
                return "-"
            end
            local okd, snap = pcall(movement.debug_snapshot)
            if not okd or type(snap) ~= "table" then
                return "-"
            end
            local text = tostring(snap.state) .. " / " .. tostring(snap.owner)
            if snap.restriction then
                text = text .. " (" .. tostring(snap.restriction) .. ")"
            elseif snap.retreating then
                text = text .. " (kiting)"
            elseif snap.paused then
                text = text .. " (paused)"
            elseif snap.sentinel then
                text = text .. " (navmesh)"
            elseif snap.quiet then
                text = text .. " (settling)"
            end
            if snap.target_dist then
                text = text .. string.format("  %.0fyd", snap.target_dist)
            end
            return text
        end,
    },
    {
        label = "Last Action",
        value = function()
            local ok, rotation = pcall(require, "rotation")
            if ok and rotation and type(rotation.last_action) == "function" then
                return rotation.last_action()
            end
            return state.last_action or "-"
        end,
    },
})

menu:set_actions({
    {
        id = "toggle_enable",
        label = "Start",
        style = "start",
        on_click = start_bot,
    },
    {
        id = "toggle_pause",
        label = "Pause",
        style = "pause",
        on_click = pause_bot,
    },
    {
        id = "toggle_stop",
        label = "Stop",
        style = "stop",
        on_click = stop_bot,
    },
})

-- ============================================================================
-- GRINDING TAB
-- ============================================================================
-- The enable checkbox is a registered control, so the tab system draws it
-- above everything here. Below it: which side, which route, and what that
-- route actually is - in that order, because that is the order the questions
-- get asked.
local FACTION_TINT = {
    alliance = { 96, 150, 235 },
    horde    = { 200, 70, 62 },
}

--- The route button. Draws the current route and opens the picker.
---
--- Every route chooser in the plugin is this, so there is exactly one way to
--- pick a profile. A dropdown was the wrong widget for a 27-entry list - it
--- caps at 18 rows inside a 30px field and has nowhere to show the level range
--- or the vendor flag - and having one on the Mode tab and another on the
--- Grinding tab meant two widgets disagreeing about what was selected.
--- Returns the y below the button.
local function draw_route_button(win, x, y, width, entry)
    local gold = color.new(232, 222, 196, 255)
    local mute = color.new(180, 170, 150, 255)
    local bmin = vec2.new(x, y)
    local bmax = vec2.new(x + width, y + 30)

    local hover = false
    pcall(function()
        hover = win:is_mouse_hovering_rect(bmin, bmax) == true
    end)
    pcall(function()
        win:render_rect_filled(bmin, bmax,
            hover and color.new(52, 58, 72, 235) or color.new(38, 40, 48, 220), 4.0)
    end)
    pcall(function()
        win:render_rect(bmin, bmax, color.new(96, 150, 235, hover and 255 or 150), 4.0, 1.0)
    end)

    local label = entry and tostring(entry.label or entry.id) or "Choose a route..."
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 8), gold, label)
    win:render_text(FONT_SMALL, vec2.new(x + width - 58, y + 8), mute, "change")

    local pressed = false
    pcall(function()
        pressed = win:is_rect_clicked(bmin, bmax) == true
    end)
    if pressed then
        menu:open_popup("profiles")
    end
    return y + 36
end

--- The catalog entry currently chosen, or nil.
local function current_route_entry()
    local ok, grind_catalog = pcall(require, "grind/catalog")
    if not ok or not grind_catalog or type(grind_catalog.entries_for_faction) ~= "function" then
        return nil
    end
    local entries = grind_catalog.entries_for_faction(gui.faction_key())
    return entries[gui.path_index()]
end

local function faction_colour(key)
    local c = FACTION_TINT[key] or FACTION_TINT.alliance
    return color.new(c[1], c[2], c[3], 255)
end

-- ============================================================================
-- PROFILE PICKER POPUP
-- ============================================================================
menu:on_tab("profiles", function(win, x, y, w, h)
    local gold = color.new(232, 222, 196, 255)
    local mute = color.new(180, 170, 150, 255)
    local ok_col = color.new(90, 210, 110, 255)
    local warn = color.new(220, 176, 56, 255)
    local sel_col = color.new(96, 150, 235, 255)

    local key = gui.faction_key()
    local entries = {}
    local ok, grind_catalog = pcall(require, "grind/catalog")
    if ok and grind_catalog and type(grind_catalog.entries_for_faction) == "function" then
        entries = grind_catalog.entries_for_faction(key)
    end

    if #entries == 0 then
        win:render_text(FONT_SMALL, vec2.new(x + 12, y + 8), warn,
            "No routes for this faction.")
        win:render_text(FONT_SMALL, vec2.new(x + 12, y + 28), mute,
            "Switch faction on the Grinding tab.")
        return
    end

    local chosen = gui.path_index()
    local row_h = PROFILE_ROW
    local row_y = y + 4

    for i = 1, #entries do
        local e = entries[i]
        local is_sel = (i == chosen)
        local rmin = vec2.new(x + 6, row_y)
        local rmax = vec2.new(x + w - 6, row_y + row_h - 2)

        -- The selected row gets a plate; the rest get one only on hover, so
        -- the list reads as a list rather than as 27 buttons.
        local hover = false
        pcall(function()
            hover = win:is_mouse_hovering_rect(rmin, rmax) == true
        end)
        if is_sel then
            pcall(function()
                win:render_rect_filled(rmin, rmax, color.new(46, 62, 92, 210), 3.0)
            end)
        elseif hover then
            pcall(function()
                win:render_rect_filled(rmin, rmax, color.new(40, 40, 48, 160), 3.0)
            end)
        end

        local clicked_row = false
        pcall(function()
            clicked_row = win:is_rect_clicked(rmin, rmax) == true
        end)
        if clicked_row then
            gui.set_path_index(i)
            armed_path = nil
            menu:close_popup("profiles")
        end

        -- One row, three columns, fixed x positions so they line up down the
        -- list instead of drifting with the label length.
        local levels = string.format("%s-%s", tostring(e.min or "?"), tostring(e.max or "?"))
        local label = tostring(e.label or e.id or "?")
        win:render_text(FONT_SMALL, vec2.new(x + 14, row_y + 5),
            is_sel and sel_col or gold, label)
        win:render_text(FONT_SMALL, vec2.new(x + w - 150, row_y + 5), mute, levels)
        local has_vendor = type(e.vendors) == "table" and #e.vendors > 0
        win:render_text(FONT_SMALL, vec2.new(x + w - 92, row_y + 5),
            has_vendor and ok_col or mute, has_vendor and "vendor" or "no vendor")

        row_y = row_y + row_h
    end

    win:render_text(FONT_SMALL, vec2.new(x + 12, row_y + 6), mute,
        string.format("%d routes - click one to load it.", #entries))
end)

-- ============================================================================
-- ALL KNOWN SPELLS
-- ============================================================================
-- Everything the scanner found, one row per rank family rather than one per
-- rank - eleven Frostbolts is not a list, it is a wall. The rank count is
-- shown instead, and the id is the best rank.
menu:on_tab("spells", function(win, x, y, w, h)
    local gold = color.new(232, 222, 196, 255)
    local mute = color.new(180, 170, 150, 255)
    local ok_col = color.new(90, 210, 110, 255)
    local warn = color.new(220, 176, 56, 255)
    local head = color.new(96, 150, 235, 255)

    if not spellbook.ready() then
        win:render_text(FONT_SMALL, vec2.new(x + 12, y + 8), warn,
            string.format("Scanning the spellbook... %.1fs", spellbook.wait_left()))
        return
    end

    local groups = spellbook.categories and spellbook.categories() or {}
    if #groups == 0 then
        win:render_text(FONT_SMALL, vec2.new(x + 12, y + 8), warn, "No spells found.")
        return
    end

    local ok_b, buffs = pcall(require, "buffs")
    local ok_c, cats = pcall(require, "data/spell_categories")
    local buff_key = (ok_c and cats and cats.BUFF) or "buff"

    local row_y = y + 4
    local bottom = y + h - 24
    local shown = 0

    for gi = 1, #groups do
        if row_y > bottom then break end
        local grp = groups[gi]

        -- Category heading, so the book reads as sections rather than one
        -- alphabetical run.
        win:render_text(FONT_SMALL, vec2.new(x + 10, row_y), head,
            string.format("%s  (%d)", tostring(grp.label), #grp.spells))
        row_y = row_y + SPELL_ROW

        for si = 1, #grp.spells do
            if row_y > bottom then break end
            local fam = grp.spells[si]
            local n = (type(fam.ranks) == "table") and #fam.ranks or 1

            -- Buffs get a tick box; buffs.lua keeps the ticked ones up.
            local is_buff = (grp.key == buff_key) and ok_b and buffs
            if is_buff then
                local on = buffs.is_enabled(fam.name)
                local bmin = vec2.new(x + 16, row_y + 2)
                local bmax = vec2.new(x + 28, row_y + 14)
                pcall(function()
                    win:render_rect_filled(bmin, bmax,
                        on and color.new(90, 210, 110, 220) or color.new(38, 40, 48, 220), 2.0)
                end)
                pcall(function()
                    win:render_rect(bmin, bmax, color.new(120, 130, 150, 220), 2.0, 1.0)
                end)
                local hit = false
                pcall(function()
                    hit = win:is_rect_clicked(vec2.new(x + 12, row_y), vec2.new(x + w - 10, row_y + 18)) == true
                end)
                if hit then
                    buffs.toggle(fam.name)
                end
                win:render_text(FONT_SMALL, vec2.new(x + 34, row_y), on and ok_col or gold,
                    tostring(fam.name))
            else
                win:render_text(FONT_SMALL, vec2.new(x + 22, row_y), gold, tostring(fam.name))
            end

            win:render_text(FONT_SMALL, vec2.new(x + w - 118, row_y), mute,
                (n > 1) and string.format("%d ranks", n) or "1 rank")
            win:render_text(FONT_SMALL, vec2.new(x + w - 60, row_y), mute, tostring(fam.id))

            row_y = row_y + SPELL_ROW
            shown = shown + 1
        end
        row_y = row_y + 4
    end

    local ids, distinct = 0, 0
    if spellbook.counts then
        ids, distinct = spellbook.counts()
    end
    local on_n = (ok_b and buffs and buffs.enabled_count and buffs.enabled_count()) or 0
    win:render_text(FONT_SMALL, vec2.new(x + 12, row_y + 2), mute,
        string.format("%d of %d spells shown, %d ranks in the book - %d buff%s kept up.",
            shown, distinct, ids, on_n, on_n == 1 and "" or "s"))
end)

menu:on_tab("grinding", function(win, x, y, w, h)
    local gold = color.new(232, 222, 196, 255)
    local mute = color.new(180, 170, 150, 255)
    local ok_col = color.new(90, 210, 110, 255)
    local warn = color.new(220, 176, 56, 255)

    -- One grid for the whole page. Every row is placed from LEFT and LINE
    -- rather than by adding ad-hoc offsets, which is what left the uneven gaps.
    local LEFT = x + 12
    local LINE = 18
    local field_w = w - 24
    if field_w < 120 then
        field_w = math.max(80, w - 12)
    end
    local cy = y + 4

    local function text(col, str)
        win:render_text(FONT_SMALL, vec2.new(LEFT, cy), col, str)
        cy = cy + LINE
    end

    if not is_on("use_grind") then
        text(warn, "Tick Enable Grinding to choose a route.")
        text(mute, "Grinding and Questing cannot run at the same time.")
        return
    end

    gui.sync_faction(izi.me())

    -- 1. which side
    local key, fidx = gui.faction_key()
    local new_f, after = menu:draw_dropdown(win, "mfg_tab_faction", LEFT, cy, field_w,
        "Faction", factions.labels, fidx)
    if new_f ~= fidx then
        menu:set("mfg_faction", new_f)
        gui.set_path_index(1)
        armed_path = nil
        last_path_key = ""
        picker_cache_key = ""
        gui.sync_profile_list(false)
        key = factions.key_at(new_f)
    end
    cy = after + 6

    local counts = {}
    local ok_cat, grind_catalog = pcall(require, "grind/catalog")
    if ok_cat and grind_catalog and type(grind_catalog.faction_counts) == "function" then
        counts = grind_catalog.faction_counts() or {}
    end
    local mine = counts[key] or 0
    local other_key = (key == factions.ALLIANCE) and factions.HORDE or factions.ALLIANCE
    local other = counts[other_key] or 0

    text(faction_colour(key), string.format("%s - %d route%s",
        factions.labels[factions.index_of(key)], mine, mine == 1 and "" or "s"))
    text(mute, string.format("%s has %d.",
        factions.labels[factions.index_of(other_key)], other))
    cy = cy + 4

    if mine == 0 then
        text(warn, "No routes for this faction yet.")
        text(mute, "Every route shipped so far is an Alliance levelling route.")
        text(mute, "Add one under grind/paths tagged faction = \"horde\".")
        return
    end

    -- 2. which route - a button, because the list is 27 long and each entry
    --    carries a level range and a vendor flag that no dropdown row can show.
    local entry = nil
    if ok_cat and grind_catalog and type(grind_catalog.entries_for_faction) == "function" then
        local entries = grind_catalog.entries_for_faction(key)
        entry = entries[gui.path_index()]
    end

    cy = draw_route_button(win, LEFT, cy, field_w, entry) + 2

    -- 3. what that route is
    if entry then
        text(mute, string.format("Levels %s-%s   %d waypoints   %s",
            tostring(entry.min or "?"), tostring(entry.max or "?"),
            tonumber(entry.count) or 0,
            (entry.loop == true) and "loops" or "point to point"))
        local vendors = entry.vendors
        if type(vendors) == "table" and #vendors > 0 then
            local ids = {}
            for i = 1, #vendors do
                ids[i] = tostring(vendors[i])
            end
            text(ok_col, "Vendor on route: npc " .. table.concat(ids, ", "))
        else
            text(mute, "No vendor on this route - it will not sell or repair here.")
        end
    else
        text(warn, "No route selected.")
    end
    cy = cy + 4

    local armed = armed_path
    text(armed and ok_col or warn,
        armed and ("Loaded: " .. tostring(armed.name or armed.id))
            or "Press Start to load and run this route.")
end)

-- ============================================================================
-- QUESTING TAB
-- ============================================================================
menu:on_tab("questing", function(win, x, y, w, h)
    local gold = color.new(232, 222, 196, 255)
    local mute = color.new(180, 170, 150, 255)
    local ok_col = color.new(90, 210, 110, 255)
    local warn = color.new(220, 176, 56, 255)

    local field_w = w - 20
    if field_w < 120 then
        field_w = math.max(80, w - 8)
    end

    if not is_on("use_quest") then
        win:render_text(FONT_SMALL, vec2.new(x + 10, y + 6), warn,
            "Tick Enable Questing to choose a starter quest.")
        win:render_text(FONT_SMALL, vec2.new(x + 10, y + 26), mute,
            "Grinding and Questing cannot run at the same time.")
        return
    end

    local ok, quest = pcall(require, "quest")
    if not ok or type(quest) ~= "table" or type(quest.snapshot) ~= "function" then
        win:render_text(FONT_SMALL, vec2.new(x + 10, y + 6), warn, "Quest engine not loaded.")
        return
    end

    local info = quest.snapshot(izi.me())
    if type(info) ~= "table" then
        win:render_text(FONT_SMALL, vec2.new(x + 10, y + 6), mute, "Waiting for the player...")
        return
    end

    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 4),
        info.race_ok and gold or warn,
        string.format("%s  -  %d starter quest%s",
            tostring(info.race_label or "Unknown"), tonumber(info.count) or 0,
            (tonumber(info.count) or 0) == 1 and "" or "s"))

    if not info.race_ok or (tonumber(info.count) or 0) == 0 then
        win:render_text(FONT_SMALL, vec2.new(x + 10, y + 24), mute,
            "No starter quests for this race yet.")
        win:render_text(FONT_SMALL, vec2.new(x + 10, y + 42), mute,
            "Human, Gnome, Troll and Undead are the races with quest data.")
        return
    end

    local labels = info.labels
    if type(labels) ~= "table" or #labels == 0 then
        labels = { EMPTY_QUEST }
    end
    local qidx = gui.quest_index()
    local new_q, y2 = menu:draw_dropdown(win, "mfg_tab_quest", x + 10, y + 24, field_w,
        "Starter Quest", labels, qidx)
    if new_q ~= qidx then
        menu:set("mfg_quest", new_q)
    end

    local sel = info.selected
    if type(sel) == "table" then
        win:render_text(FONT_SMALL, vec2.new(x + 10, y2), gold,
            tostring(sel.name or sel.id))
        win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 18), mute,
            string.format("Levels %s-%s   quest id %s",
                tostring(sel.min_level or "?"), tostring(sel.max_level or "?"), tostring(sel.id)))
        win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 36),
            info.skipped and warn or ok_col,
            "Step: " .. tostring(info.phase or "-"))
        y2 = y2 + 58
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2), mute,
        "Press Start to begin. The bot works the list in level order.")
end)

menu:on_tab("class", function(win, x, y, w, h)
    local class_id = menu:player_class()
    local idx = menu:get("mfg_class") or 7
    local name = CLASS_LABELS[idx] or "Unknown"
    local yy = y + 8
    if type(class_id) ~= "number" then
        win:render_text(FONT_SMALL, vec2.new(x + 10, yy), color.new(180, 170, 150, 255), "Waiting for player class...")
        return
    end
    local ok, rotation = pcall(require, "rotation")
    local ready = ok and rotation and rotation.supported(class_id) == true
    local line = name .. (ready and "  -  rotation loaded" or "  -  no rotation for this class")
    local col = ready and color.new(90, 210, 110, 255) or color.new(220, 176, 56, 255)
    win:render_text(FONT_SMALL, vec2.new(x + 10, yy), col, line)
    if not spellbook.ready() then
        win:render_text(FONT_SMALL, vec2.new(x + 10, yy + 22), color.new(220, 176, 56, 255), string.format("Waiting for spellbook scan  %.1fs", spellbook.wait_left()))
        win:render_text(FONT_SMALL, vec2.new(x + 10, yy + 40), color.new(180, 170, 150, 255), "Spells appear after the one-time 5 second load scan.")
        return
    end
    -- What the scan actually found, rather than a promise about it.
    local ids, distinct = 0, 0
    if spellbook.counts then
        ids, distinct = spellbook.counts()
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, yy + 22), color.new(180, 170, 150, 255),
        string.format("%d spells known, %d ranks in the spellbook.", distinct, ids))

    -- The toggles below are the ones the rotation drives. The full book is a
    -- click away rather than inlined: a level 60 caster has well over a
    -- hundred spells and this header has 72px.
    local bmin = vec2.new(x + 10, yy + 40)
    local bmax = vec2.new(x + 190, yy + 66)
    local hover = false
    pcall(function()
        hover = win:is_mouse_hovering_rect(bmin, bmax) == true
    end)
    pcall(function()
        win:render_rect_filled(bmin, bmax,
            hover and color.new(52, 58, 72, 235) or color.new(38, 40, 48, 220), 4.0)
    end)
    pcall(function()
        win:render_rect(bmin, bmax, color.new(96, 150, 235, hover and 255 or 150), 4.0, 1.0)
    end)
    win:render_text(FONT_SMALL, vec2.new(x + 22, yy + 46), color.new(232, 222, 196, 255),
        "View all known spells")
    local pressed = false
    pcall(function()
        pressed = win:is_rect_clicked(bmin, bmax) == true
    end)
    if pressed then
        menu:open_popup("spells")
    end
end)

menu:on_tab("mode", function(win, x, y, w, h)
    gui.sync_activity()
    local mode = gui.mode()
    local line = "Check Grinding or Quest. Paths load only after that. Then pick a profile and press Start."
    if mode == modes.GRIND then
        line = "Grinding is on. Choose a grind profile below, then Start."
    elseif mode == modes.QUEST then
        line = "Quest is on. Choose a starter quest below, then Start."
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 8), color.new(232, 222, 196, 255), line)

    local field_w = w - 20
    if field_w < 120 then
        field_w = math.max(80, w - 8)
    end
    local y2 = y + 32
    if mode == modes.GRIND then
        local _, region_idx = gui.faction_key()
        local new_region, ny = menu:draw_dropdown(win, "mfg_dd_faction", x + 10, y2, field_w, "Faction", factions.labels, region_idx)
        if new_region ~= region_idx then
            menu:set("mfg_faction", new_region)
            gui.set_path_index(1)
            armed_path = nil
            last_path_key = ""
            picker_cache_key = ""
            gui.sync_profile_list(false)
        end
        win:render_text(FONT_SMALL, vec2.new(x + 10, ny), color.new(180, 170, 150, 255), "Grind profile")
        local entry = current_route_entry()
        local y3 = draw_route_button(win, x + 10, ny + 16, field_w, entry)
        local ready_text = entry and ("Profile: " .. tostring(entry.label or entry.id))
            or "Click above to choose a grind profile"
        local ready_col = entry and color.new(90, 210, 110, 255) or color.new(220, 176, 56, 255)
        win:render_text(FONT_SMALL, vec2.new(x + 10, y3), ready_col, ready_text)
        y2 = y3 + 22
    elseif mode == modes.QUEST then
        local labels = { EMPTY_QUEST }
        local ok, q = pcall(require, "quest")
        if ok and q and type(q.labels) == "function" then
            local got = q.labels(izi.me())
            if type(got) == "table" and #got > 0 then
                labels = got
            end
        end
        menu:set_combobox_items("mfg_quest", labels)
        local qidx = gui.quest_index()
        local new_q, y3 = menu:draw_dropdown(win, "mfg_dd_quest", x + 10, y2, field_w, "Quest profile", labels, qidx)
        if new_q ~= qidx then
            menu:set("mfg_quest", new_q)
        end
        local ready = gui.has_quest_profile()
        local ready_text = ready and "Quest profile selected" or "Select a quest profile"
        local ready_col = ready and color.new(90, 210, 110, 255) or color.new(220, 176, 56, 255)
        win:render_text(FONT_SMALL, vec2.new(x + 10, y3), ready_col, ready_text)
        y2 = y3 + 22
    end

    local gap = 10
    local btn_w = math.floor((w - 20 - gap) / 2)
    if btn_w < 80 then
        btn_w = math.max(80, w - 20)
    end
    local btn_h = 34
    local row1 = y2 + 8
    local left = x + 10
    local right = left + btn_w + gap
    if menu:draw_launcher(win, left, row1, btn_w, btn_h, "Vendor") then
        menu:open_popup("vendor")
    end
    if mode == modes.GRIND then
        if menu:draw_launcher(win, right, row1, btn_w, btn_h, "Grind settings") then
            menu:open_popup("grind")
        end
    elseif mode == modes.QUEST then
        if menu:draw_launcher(win, right, row1, btn_w, btn_h, "Quest details") then
            menu:open_popup("quest")
        end
    end
end)

menu:on_tab("path", function(win, x, y, w, h)
    gui.sync_profile_list(false)
    local ok_pr, path_runner = pcall(require, "path_runner")
    local field_w = w - 20
    if field_w < 120 then
        field_w = math.max(80, w - 8)
    end
    local _, region_idx = gui.faction_key()
    local new_region, y2 = menu:draw_dropdown(win, "mfg_dd_faction", x + 10, y, field_w, "Faction", factions.labels, region_idx)
    if new_region ~= region_idx then
        menu:set("mfg_faction", new_region)
        gui.set_path_index(1)
        armed_path = nil
        last_path_key = ""
        picker_cache_key = ""
        gui.sync_profile_list(false)
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2), color.new(180, 170, 150, 255), "Grind profile")
    local y3 = draw_route_button(win, x + 10, y2 + 16, field_w, current_route_entry())
    path_source = "leveling"
    local loaded = armed_path
    local name = "-"
    local count = 0
    local map_id = 0
    local ready = loaded ~= nil
    if loaded then
        name = loaded.name or loaded.id or "-"
        count = loaded.waypoints and #loaded.waypoints or 0
        map_id = loaded.map_id or 0
    end
    local status = "Idle"
    if ok_pr and path_runner and type(path_runner.status_text) == "function" then
        status = path_runner.status_text()
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y3), color.new(232, 222, 196, 255), string.format("%s   wp:%d   map:%s", tostring(name), count, tostring(map_id)))
    local ready_text = ready and ("Ready for Play - " .. tostring(name)) or "Select a path, then press Load."
    local ready_col = ready and color.new(90, 210, 110, 255) or color.new(180, 170, 150, 255)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y3 + 18), ready_col, ready_text)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y3 + 36), color.new(180, 170, 150, 255), "Status: " .. tostring(status))

    local gap = 10
    local btn_w = math.floor((w - 20 - gap) / 3)
    if btn_w < 70 then
        btn_w = 70
    end
    local btn_h = 32
    local by = y3 + 58
    local x1 = x + 10
    local x2 = x1 + btn_w + gap
    local x3 = x2 + btn_w + gap

    local function preview_path(path)
        if path and ok_pr and path_runner and type(path_runner.set_preview) == "function" then
            path_runner.set_preview(path)
        end
    end

    if menu:draw_launcher(win, x1, by, btn_w, btn_h, "Load") then
        local path, err = gui.load_selected_path()
        if path then
            preview_path(path)
            state.set_note("Path", "Loaded " .. tostring(path.name) .. " - ready for Play")
            core.log("[Master Farmer - Grindbot] Loaded path: " .. tostring(path.name))
        else
            state.set_note("Path", err or "load failed")
            core.log_warning("[Master Farmer - Grindbot] Profile load failed: " .. tostring(err))
        end
    end
    if menu:draw_launcher(win, x2, by, btn_w, btn_h, "Save") then
        local path = armed_path or path_profiles.last_loaded()
        if not path then
            path = select(1, gui.load_selected_path())
        end
        if path then
            local fname = (path.id or "path") .. ".json"
            local ok_save, saved = path_profiles.save_path(path, fname)
            if ok_save then
                gui.sync_profile_list(false)
                preview_path(path)
                state.set_note("Path", "Saved " .. tostring(saved))
                core.log("[Master Farmer - Grindbot] Saved profile: " .. tostring(saved))
            else
                state.set_note("Path", saved or "save failed")
            end
        else
            state.set_note("Path", "Nothing to save")
        end
    end
    if menu:draw_launcher(win, x3, by, btn_w, btn_h, "Play") then
        local path = armed_path
        local err = nil
        if not path then
            path, err = gui.load_selected_path()
        end
        if path then
            armed_path = path
            path_profiles.remember(path)
            preview_path(path)
            if gui.is_on("rotation_only") then
                state.set_note("Path", "Rotation Only - movement off")
                core.log("[Master Farmer - Grindbot] Rotation Only is on; Play does not move.")
            else
                play_pending = true
                state.set_note("Path", "Starting " .. tostring(path.name))
            end
        else
            state.set_note("Path", err or "play failed - Load a path first")
        end
    end
end)

menu:on_tab("quest", function(win, x, y, w, h)
    local player = nil
    pcall(function()
        player = izi.me()
    end)
    local info = nil
    local ok, q = pcall(require, "quest")
    if ok and q and type(q.snapshot) == "function" then
        info = q.snapshot(player)
    end
    if type(info) ~= "table" then
        info = {
            race_label = "Unknown",
            race_ok = false,
            count = 0,
            labels = { "(no starter quests)" },
            index = 1,
            status = "-",
            note = state.note or "",
            phase = "-",
            start_name = "-",
            end_name = "-",
            hunt = "-",
        }
    end

    local field_w = w - 20
    if field_w < 120 then
        field_w = math.max(80, w - 8)
    end
    local gold = color.new(232, 222, 196, 255)
    local mute = color.new(180, 170, 150, 255)
    local hi = color.new(248, 226, 132, 255)
    local ok_col = color.new(90, 210, 110, 255)

    local race_line = info.race_ok
        and string.format("%s - %d starter quests in quest/data/%s.lua", tostring(info.race_label), info.count or 0, tostring(info.race_key or "?"))
        or (tostring(info.race_label) .. " - no starter quest data. Use Grind or Path.")
    win:render_text(FONT_SMALL, vec2.new(x + 10, y), info.race_ok and gold or mute, race_line)

    local labels = info.labels
    if type(labels) ~= "table" or #labels == 0 then
        labels = { "(no starter quests)" }
    end
    local idx = info.index or 1
    local new_idx, y2 = menu:draw_dropdown(win, "mfg_dd_quest", x + 10, y + 20, field_w, "Starter Quest", labels, idx)
    if new_idx ~= idx then
        menu:set("mfg_quest", new_idx)
        idx = new_idx
    end

    local sel = info.selected
    local name = "-"
    local qid = "-"
    local levels = "-"
    if type(sel) == "table" then
        name = sel.name or "-"
        qid = tostring(sel.id or "-")
        if sel.min_level and sel.max_level then
            levels = string.format("%d-%d", sel.min_level, sel.max_level)
        end
    end
    local map_line = info.map_id and ("map " .. tostring(info.map_id)) or "-"
    local engine = info.current
    local running = "-"
    if type(engine) == "table" then
        running = string.format("%s (%d)", engine.name or "Quest", engine.id or 0)
    end

    win:render_text(FONT_SMALL, vec2.new(x + 10, y2), hi, "Selected: " .. tostring(name) .. "  id " .. qid)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 18), gold, "Levels " .. levels .. "   " .. map_line)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 36), gold, "Start NPC  " .. tostring(info.start_name or "-"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 54), gold, "End NPC    " .. tostring(info.end_name or "-"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 72), mute, tostring(info.hunt or "-"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 90), info.race_ok and ok_col or mute, "Step: " .. tostring(info.phase or "-"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 108), mute, "Engine: " .. tostring(running) .. "   " .. tostring(info.note or ""))

    local gap = 10
    local btn_w = math.floor((w - 20 - gap * 2) / 3)
    if btn_w < 70 then
        btn_w = 70
    end
    local btn_h = 32
    local by = y2 + 130
    local x1 = x + 10
    local x2 = x1 + btn_w + gap
    local x3 = x2 + btn_w + gap

    if menu:draw_launcher(win, x1, by, btn_w, btn_h, "Quest Mode") then
        gui.use_quest_mode()
        state.set_note("Quest", "Mode set to Quest")
    end
    if menu:draw_launcher(win, x2, by, btn_w, btn_h, "Skip") then
        gui.skip_selected_quest()
    end
    if menu:draw_launcher(win, x3, by, btn_w, btn_h, "Clear Skips") then
        gui.clear_quest_skips()
    end
end)

menu:on_tab("vendor", function(win, x, y, w, h)
    local line = "Idle"
    if state.vendor and state.vendor.active then
        line = "At vendor - " .. tostring(state.note or "")
    elseif state.note_head == "Vendor" then
        line = tostring(state.note or "")
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 16), color.new(248, 226, 132, 255), line)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 40), color.new(232, 222, 196, 255), "Grind and Quest walk to the zone merchant from Grind_Information.")
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 62), color.new(180, 170, 150, 255), "Keeps hearthstone plus mage food and water. Path mode does not vendor.")
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 84), color.new(180, 170, 150, 255), "Repair uses core.input.repair_all_items. Greys/whites sell via use_container_item.")
end)

menu:on_tab("grind", function(win, x, y, w, h)
    local band = gui.attack_level_band()
    local line = "Pulls enemies 3 levels below to 3 levels above you."
    if band == nil then
        line = "Pulls any level enemy in range."
    elseif band == 5 then
        line = "Pulls enemies 5 levels below to 5 levels above you."
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 8), color.new(232, 222, 196, 255), line)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 28), color.new(180, 170, 150, 255), "Only one level option can be on. Loot Corpses pulls loot after a kill.")
end)

menu:on_tab("settings", function(win, x, y, w, h)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 8), color.new(232, 222, 196, 255), "Show / hide GUI: Numpad 4.")
    win:render_text(FONT_SMALL, vec2.new(x + 10, y + 28), color.new(180, 170, 150, 255), "Path combat stays on the loaded path (10 yards) and hits the closest enemy in rotation range.")
end)

function gui.draw()
    pcall(function()
        gui.sync_player(izi.me())
    end)
    if not is_on("show_gui") then
        menu:set_visible(false)
        return
    end
    menu:set_visible(true)
    local start_btn = menu.actions[1]
    local pause_btn = menu.actions[2]
    if start_btn then
        start_btn.label = gui.is_started() and "Running" or "Start"
        start_btn.style = gui.is_started() and "neutral" or "start"
    end
    if pause_btn then
        pause_btn.label = gui.is_started() and "Pause" or "Paused"
    end
    local ok, err = pcall(function()
        menu:draw()
    end)
    gui.sync_attack_level()
    if not ok then
        core.log_error("[Master Farmer - Grindbot] GUI draw failed: " .. tostring(err))
    end
end

set_on("show_gui", true)

return gui

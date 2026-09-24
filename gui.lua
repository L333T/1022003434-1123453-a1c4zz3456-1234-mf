-- ============================================================================
-- Master Farmer - Grindbot
-- GUI — Shamele chrome, class auto-detect, popup Path/Quest/Vendor/Grind
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.39
-- Folder: Master_Farmer_Grindbot_v1.3.39
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
local REGION_LABELS = { "Eastern Kingdoms", "Kalimdor", "Outland", "Custom" }
local REGION_KEYS = { "ek", "kalimdor", "outland", "custom" }
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
        { id = "class", label = "Class" },
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
menu:checkbox("mfg_teleport", true, {
    label = "Teleport Detect",
    tab = "general",
})
menu:slider_int("mfg_teleport_yards", 20, 200, 80, {
    label = "Teleport Distance (yd)",
    tab = "general",
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

menu:checkbox("mfg_use_grind", false, {
    label = "Grinding",
    tab = "mode",
    tooltip = "Load grind paths after this is checked. Cannot run with Quest.",
})
menu:checkbox("mfg_use_quest", false, {
    label = "Quest",
    tab = "mode",
    tooltip = "Load quest data after this is checked. Cannot run with Grinding.",
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

menu:combobox("mfg_path_region", 1, REGION_LABELS, {
    label = "Continent",
    tab = "path",
    skip_draw = true,
    tooltip = "Filter grind and travel paths by Eastern Kingdoms, Kalimdor, Outland, or extra JSON you added under scripts_data/mfg_profiles.",
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
menu:slider_int("mfg_path_combat_yards", 10, 60, 50, {
    label = "Path Combat Range",
    tab = "path",
    tooltip = "Yards to scan for PvE mobs while traveling. Novelist profiles also use their R50 pull range when larger.",
})
menu:checkbox("mfg_draw_path", true, {
    label = "Draw Loaded Path",
    tab = "path",
    tooltip = "Draw the loaded travel path in the world.",
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
menu:slider_int("mfg_repair_pct", 5, 50, 10, {
    label = "Repair at Durability %",
    tab = "vendor",
})
menu:checkbox("mfg_buy_food", true, {
    label = "Buy Food / Drink",
    tab = "vendor",
    tooltip = "While the merchant window is open, restock the highest-level food and drink the vendor sells that you can use.",
})
menu:slider_int("mfg_food_count", 0, 60, 20, {
    label = "Keep Food Count",
    tab = "vendor",
})
menu:slider_int("mfg_drink_count", 0, 60, 20, {
    label = "Keep Drink Count",
    tab = "vendor",
    tooltip = "Ignored for classes with no mana pool.",
})
menu:text_input("mfg_keep_items", true, {
    label = "Keep Item IDs",
    tab = "vendor",
    tooltip = "Comma-separated item IDs the bot will never sell. Food, drink, potions, and your hearthstone are already protected.",
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
    teleport = "mfg_teleport",
    player_detect = "mfg_player_detect",
    eat_drink = "mfg_eat_drink",
    potions = "mfg_potions",
    random_path = "mfg_random_path",
    fight_back = "mfg_fight_back",
    untapped = "mfg_untapped",
    loot = "mfg_loot",
    loot_mine = "mfg_loot_mine",
    sell = "mfg_vendor_sell",
    repair = "mfg_repair",
    buy_food = "mfg_buy_food",
    sell_grey = "mfg_sell_grey",
    sell_white = "mfg_sell_white",
    sell_green = "mfg_sell_green",
    path_loop = "mfg_path_loop",
    path_reverse = "mfg_path_reverse",
    path_combat = "mfg_path_combat",
    draw_path = "mfg_draw_path",
    rotation_only = "mfg_rotation_only",
    quest_force = "mfg_quest_force",
    use_grind = "mfg_use_grind",
    use_quest = "mfg_use_quest",
    show_gui = "mfg_show_gui",
    ice_armor = "mfg_ice_armor",
    mage_armor = "mfg_mage_armor",
    molten_armor = "mfg_molten_armor",
    ice_barrier = "mfg_ice_barrier",
    mana_shield = "mfg_mana_shield",
    mana_gem = "mfg_mana_gem",
    conjure_gems = "mfg_conjure_gems",
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
    teleport_yards = "mfg_teleport_yards",
    player_yards = "mfg_player_yards",
    eat_hp = "mfg_eat_hp",
    drink_mana = "mfg_drink_mana",
    hp_pot = "mfg_hp_pot",
    mp_pot = "mfg_mp_pot",
    mana_gem_pct = "mfg_mana_gem_pct",
    max_kill = "mfg_max_kill",
    fight_back_hp = "mfg_fight_back_hp",
    fight_back_yards = "mfg_fight_back_yards",
    path_combat_yards = "mfg_path_combat_yards",
    bag_free = "mfg_bag_free",
    repair_pct = "mfg_repair_pct",
    food_count = "mfg_food_count",
    drink_count = "mfg_drink_count",
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

function gui.keep_items()
    local value = menu:get("mfg_keep_items")
    if type(value) == "string" then
        return value
    end
    return ""
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

function gui.region_key()
    local idx = menu:get("mfg_path_region")
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
        local prefix = "Travel — "
        if kind == "grind" then
            prefix = "Grind — "
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
    local key, region = gui.region_key()
    local cache_key = tostring(region) .. "|" .. tostring(key)
    if picker_cache_key == cache_key and type(picker_cache) == "table" and #picker_cache > 0 then
        return picker_cache, key, region
    end
    local ok, grind_catalog = pcall(require, "grind/catalog")
    local rows = {}
    if ok and grind_catalog then
        local grind_labels = grind_catalog.labels_for_region(key)
        local grind_ids = {}
        local entries = grind_catalog.entries_for_region(key)
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

function gui.path_index()
    local labels = gui.combo_labels()
    local n = #labels
    if n == 1 and labels[1] == EMPTY_PATH then
        n = 0
    end
    return clamp_index(menu:get("mfg_path"), n)
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
    local key = gui.region_key()
    path_source = "leveling"
    local index = row and row.index or 1
    local ok, grind_catalog = pcall(require, "grind/catalog")
    if not ok or not grind_catalog then
        return nil, "grind catalog not loaded"
    end
    local path, err = grind_catalog.load_region(key, index)
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
        menu:set("mfg_path", 1)
        return
    end
    picker_cache_key = ""
    local key, region = gui.region_key()
    local loaded = armed_path
    if restore_selected == true and loaded and type(loaded.region) == "string" then
        local r = loaded.region
        if r == "kalimdor" then
            region = 2
        elseif r == "outland" then
            region = 3
        elseif r == "custom" then
            region = 4
        elseif r == "ek" then
            region = 1
        end
        menu:set("mfg_path_region", region)
        key = REGION_KEYS[region]
        picker_cache_key = ""
    end
    local labels = gui.combo_labels()
    local path_key = tostring(region) .. "|all|" .. table.concat(labels, "\n")
    if path_key ~= last_path_key then
        menu:set_combobox_items("mfg_path", labels)
        last_path_key = path_key
        if last_region_idx ~= nil and region ~= last_region_idx and restore_selected ~= true then
            menu:set("mfg_path", 1)
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
                    menu:set("mfg_path", i)
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
    if ok and movement and type(movement.stop) == "function" then
        movement.stop()
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
            state.set_note("Mode", "Grinding — choose a profile, then Start")
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
            state.set_note("Mode", "Quest — choose a profile, then Start")
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
        return name .. " — ready"
    end
    return name .. " — no rotation yet"
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
            return state.note ~= "" and state.note or "—"
        end,
    },
    {
        label = "Last Action",
        value = function()
            local ok, rotation = pcall(require, "rotation")
            if ok and rotation and type(rotation.last_action) == "function" then
                return rotation.last_action()
            end
            return state.last_action or "—"
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
    local line = name .. (ready and "  —  rotation loaded" or "  —  no rotation for this class")
    local col = ready and color.new(90, 210, 110, 255) or color.new(220, 176, 56, 255)
    win:render_text(FONT_SMALL, vec2.new(x + 10, yy), col, line)
    if not spellbook.ready() then
        win:render_text(FONT_SMALL, vec2.new(x + 10, yy + 22), color.new(220, 176, 56, 255), string.format("Waiting for spellbook scan  %.1fs", spellbook.wait_left()))
        win:render_text(FONT_SMALL, vec2.new(x + 10, yy + 40), color.new(180, 170, 150, 255), "Spells appear after the one-time 5 second load scan.")
        return
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, yy + 22), color.new(180, 170, 150, 255), "Only spells in your spellbook are listed. Other class rotations stay hidden.")
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
        local _, region_idx = gui.region_key()
        local new_region, ny = menu:draw_dropdown(win, "mfg_dd_region", x + 10, y2, field_w, "Continent", REGION_LABELS, region_idx)
        if new_region ~= region_idx then
            menu:set("mfg_path_region", new_region)
            menu:set("mfg_path", 1)
            armed_path = nil
            last_path_key = ""
            picker_cache_key = ""
            gui.sync_profile_list(false)
        end
        local path_labels = gui.combo_labels()
        local path_idx = gui.path_index()
        local new_path, y3 = menu:draw_dropdown(win, "mfg_dd_path", x + 10, ny, field_w, "Grind profile", path_labels, path_idx)
        if new_path ~= path_idx then
            menu:set("mfg_path", new_path)
            armed_path = nil
        end
        local row = gui.selected_picker()
        local ready = row and row.kind == "grind"
        local ready_text = ready and ("Profile: " .. tostring(row.label)) or "Select a grind profile"
        local ready_col = ready and color.new(90, 210, 110, 255) or color.new(220, 176, 56, 255)
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
    local _, region_idx = gui.region_key()
    local new_region, y2 = menu:draw_dropdown(win, "mfg_dd_region", x + 10, y, field_w, "Continent", REGION_LABELS, region_idx)
    if new_region ~= region_idx then
        menu:set("mfg_path_region", new_region)
        menu:set("mfg_path", 1)
        armed_path = nil
        last_path_key = ""
        picker_cache_key = ""
        gui.sync_profile_list(false)
    end
    local path_labels = gui.combo_labels()
    local path_idx = gui.path_index()
    local new_path, y3 = menu:draw_dropdown(win, "mfg_dd_path", x + 10, y2, field_w, "Grind / Travel", path_labels, path_idx)
    if new_path ~= path_idx then
        menu:set("mfg_path", new_path)
        local row = gui.selected_picker()
        if row and row.kind == "grind" then
            path_source = "leveling"
        else
            path_source = "travel"
        end
        armed_path = nil
        if ok_pr and path_runner and type(path_runner.clear_preview) == "function" then
            path_runner.clear_preview()
        end
    end
    local loaded = armed_path
    local name = "—"
    local count = 0
    local map_id = 0
    local ready = loaded ~= nil
    if loaded then
        name = loaded.name or loaded.id or "—"
        count = loaded.waypoints and #loaded.waypoints or 0
        map_id = loaded.map_id or 0
    end
    local status = "Idle"
    if ok_pr and path_runner and type(path_runner.status_text) == "function" then
        status = path_runner.status_text()
    end
    win:render_text(FONT_SMALL, vec2.new(x + 10, y3), color.new(232, 222, 196, 255), string.format("%s   wp:%d   map:%s", tostring(name), count, tostring(map_id)))
    local ready_text = ready and ("Ready for Play — " .. tostring(name)) or "Select a path, then press Load."
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
            state.set_note("Path", "Loaded " .. tostring(path.name) .. " — ready for Play")
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
                state.set_note("Path", "Rotation Only — movement off")
                core.log("[Master Farmer - Grindbot] Rotation Only is on; Play does not move.")
            else
                play_pending = true
                state.set_note("Path", "Starting " .. tostring(path.name))
            end
        else
            state.set_note("Path", err or "play failed — Load a path first")
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
            status = "—",
            note = state.note or "",
            phase = "—",
            start_name = "—",
            end_name = "—",
            hunt = "—",
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
        and string.format("%s — %d starter quests in quest/data/%s.lua", tostring(info.race_label), info.count or 0, tostring(info.race_key or "?"))
        or (tostring(info.race_label) .. " — no starter quest data. Use Grind or Path.")
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
    local name = "—"
    local qid = "—"
    local levels = "—"
    if type(sel) == "table" then
        name = sel.name or "—"
        qid = tostring(sel.id or "—")
        if sel.min_level and sel.max_level then
            levels = string.format("%d–%d", sel.min_level, sel.max_level)
        end
    end
    local map_line = info.map_id and ("map " .. tostring(info.map_id)) or "—"
    local engine = info.current
    local running = "—"
    if type(engine) == "table" then
        running = string.format("%s (%d)", engine.name or "Quest", engine.id or 0)
    end

    win:render_text(FONT_SMALL, vec2.new(x + 10, y2), hi, "Selected: " .. tostring(name) .. "  id " .. qid)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 18), gold, "Levels " .. levels .. "   " .. map_line)
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 36), gold, "Start NPC  " .. tostring(info.start_name or "—"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 54), gold, "End NPC    " .. tostring(info.end_name or "—"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 72), mute, tostring(info.hunt or "—"))
    win:render_text(FONT_SMALL, vec2.new(x + 10, y2 + 90), info.race_ok and ok_col or mute, "Step: " .. tostring(info.phase or "—"))
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
        line = "At vendor — " .. tostring(state.note or "")
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

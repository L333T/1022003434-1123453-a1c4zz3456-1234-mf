-- ============================================================================
-- Master Farmer - Grindbot
-- Main — update cascade
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- Standalone IZI. movement.lua is a single-owner state machine: simple_movement
-- drives all travel and combat repositioning, Sentinel is the navmesh fallback
-- for long/blocked out-of-combat legs, movement_handler does facing and cast
-- pauses only. Nothing else in the plugin issues a movement command.
-- No FB_Nexus. No NavLib.
-- Tick: death -> rest -> loot -> buffs -> train -> vendor -> equip -> grind XOR quest (Start gated)
-- ============================================================================

local PLUGIN_MODULES = {
    "spellbook",
    "ui",
    "version",
    "state",
    "modes",
    "path_format",
    "data/consumables",
    "loader",
    "gui",
    "targeting",
    "movement",
    "loot",
    "path_runner",
    "rotations/mage",
    "rotation",
    "death",
    "healing",
    "vendor",
    "supplies",
    "equip",
    "trainer",
    "resting",
    "racials",
    "data/racials",
    "data/factions",
    "events",
    "buffs",
    "data/spell_categories",
    "config",
    -- The path INDEXES. These were missing, and the effect was invisible and
    -- very confusing: a reload reused the previous session's grind/catalog
    -- table, so a newly added route list never appeared in the menu however
    -- many times the plugin was reloaded. They are index tables of a few
    -- kilobytes, so dropping them costs nothing.
    "grind/catalog",
    "grind/paths/catalog",
    "grind/paths/ally160/catalog",
    "path_catalog",
    "data/paths/catalog",
}

for i = 1, #PLUGIN_MODULES do
    package.loaded[PLUGIN_MODULES[i]] = nil
end

---@type izi_api
local izi = require("common/izi_sdk")

local identity = require("version")

_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot
NS.meta = NS.meta or {
    name = identity.name,
    version = identity.version,
    author = identity.authors,
}
NS._sessions = NS._sessions or {}
if type(NS._sessions[identity.folder]) ~= "number" then
    NS._sessions[identity.folder] = 1
end
local MY_SESSION = NS._sessions[identity.folder]

local function is_stale()
    return NS._sessions[identity.folder] ~= MY_SESSION
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function load_mod(name)
    local ok, mod = pcall(require, name)
    if ok then
        return mod
    end
    core.log_error("[Master Farmer - Grindbot] require failed (" .. name .. "): " .. tostring(mod))
    return nil
end

local gui = load_mod("gui")
if not gui then
    core.log_error("[Master Farmer - Grindbot] GUI module failed - window will not appear.")
else
    core.register_on_render_window_callback(function()
        if is_stale() then
            return
        end
        local ok, err = pcall(function()
            gui.draw()
        end)
        if not ok then
            core.log_error("[Master Farmer - Grindbot] GUI: " .. tostring(err))
        end
    end)
    core.log(string.format("[Master Farmer - Grindbot] v%s GUI ready", identity.version))
end

local state = load_mod("state")
local spellbook = load_mod("spellbook")
local targeting = load_mod("targeting")
local movement = load_mod("movement")
local loot = load_mod("loot")
local rotation = load_mod("rotation")
local death = load_mod("death")
local healing = load_mod("healing")
local vendor = load_mod("vendor")
local combat = load_mod("combat")
local equip = load_mod("equip")
local trainer = load_mod("trainer")

-- Game events. Registered once per SESSION, not once per load: the callback
-- cap is per plugin and this file re-runs on every hot reload. events.install
-- keeps the guard on the shared namespace and refreshes the handler table, so
-- a reload picks up new handler code without registering a second callback.
local buffs = load_mod("buffs")
local events = load_mod("events")
if events and type(events.install) == "function" then
    pcall(events.install)
end
local supplies = load_mod("supplies")
local loader = load_mod("loader")
local path_runner = load_mod("path_runner")
local modes = load_mod("modes")

if gui and supplies and type(supplies.register_gui) == "function" then
    pcall(supplies.register_gui, gui.get_menu())
end

if gui and trainer and type(trainer.register_gui) == "function" then
    pcall(trainer.register_gui, gui.get_menu())
end
if gui and equip and type(equip.register_gui) == "function" then
    pcall(equip.register_gui, gui.get_menu())
end

local racials = load_mod("racials")
if gui and racials and type(racials.register_gui) == "function" then
    pcall(racials.register_gui, gui.get_menu())
end
if gui and rotation and type(rotation.register_gui) == "function" then
    pcall(function()
        rotation.register_gui(gui.get_menu())
    end)
end

local nav_halted = false
local move_debug_on = false

local function halt_bot_movement()
    if nav_halted then
        return
    end
    nav_halted = true
    if path_runner then
        path_runner.stop()
    end
    if movement then
        movement.halt()
    end
end

local function allow_bot_movement()
    nav_halted = false
end

local function pause_path_for_combat()
    if type(path_runner.is_paused) ~= "function" or path_runner.is_paused() ~= true then
        path_runner.pause()
    end
end

local function rotation_yards(player)
    local yards = 30
    if rotation and type(rotation.combat_range) == "function" then
        yards = rotation.combat_range(player)
    end
    if type(yards) ~= "number" or yards < 5 then
        yards = 30
    end
    return yards
end

--- How far out to look for something to fight.
---
--- The class decides: melee scans tighter than a caster, because melee has to
--- close the distance and then stand still, and every extra mob inside the
--- scan is one more thing arriving during that. The path may ask for a wider
--- scan through its `pull` value, and that still wins - a route author who
--- says "pull from 50 yards here" knows the terrain better than the class
--- default does.
local function scan_yards(player)
    local yards = 30
    if rotation and type(rotation.scan_range) == "function" then
        local ok, n = pcall(rotation.scan_range, player)
        if ok and type(n) == "number" and n >= 5 then
            yards = n
        end
    end
    local current = path_runner.current_path and path_runner.current_path() or nil
    local pull = current and tonumber(current.pull)
    if type(pull) == "number" and pull > yards then
        yards = pull
    end
    if yards > 80 then
        yards = 80
    end
    return yards
end

local function unit_has_los(player, unit)
    local los = safe(function() return player:los_to(unit) end)
    if los == true then
        return true
    end
    if type(izi.is_los) == "function" then
        local izi_los = safe(function() return izi.is_los(player, unit) end)
        if izi_los == true then
            return true
        end
        if izi_los == false then
            return false
        end
    end
    return los ~= false
end

local function in_rotation_range(player, unit, yards)
    if not player or not unit then
        return false
    end
    yards = yards or rotation_yards(player)
    local in_range = safe(function() return unit:is_in_range(yards) end)
    if in_range ~= true then
        local d = safe(function() return player:distance_to(unit) end)
        if type(d) ~= "number" or d > yards then
            return false
        end
    end
    return unit_has_los(player, unit)
end

local function closest_in_range(player, lists, yards)
    local found = {}
    if type(lists) ~= "table" then
        return nil
    end
    for i = 1, #lists do
        local list = lists[i]
        if type(list) == "table" then
            for j = 1, #list do
                local u = list[j]
                if u and in_rotation_range(player, u, yards) then
                    found[#found + 1] = u
                end
            end
        end
    end
    return targeting.nearest(player, found)
end

local function path_fight(player, unit, scan_range)
    if movement.needs_rejoin() == true then
        -- Getting back on the recorded line outranks fighting from off it, so
        -- hand movement back to navigation before asking for the rejoin hop -
        -- otherwise combat ownership would refuse it until the fight ended.
        movement.combat_release()
        if movement.is_moving() then
            movement.nav_stop()
        else
            movement.rejoin_path()
        end
        targeting.set_current(unit, "kill")
        targeting.start_auto_attack(player, unit)
        state.set_note("Path", "Rejoin path")
        return true
    end
    pause_path_for_combat()
    targeting.set_current(unit, "kill")
    pcall(function()
        core.input.set_target(unit)
    end)
    targeting.start_auto_attack(player, unit)

    -- Combat movement owns the player from here: it faces the target, holds the
    -- rotation's range band and kites when the class profile asks for it. The
    -- path leash keeps every combat hop within PATH_LEASH of the recorded line,
    -- so the bot fights from the path instead of wandering off it.
    local yards = rotation_yards(player)
    movement.combat_engage(player, unit, yards)

    local pack = targeting.combat_scan(player, scan_range)
    state.set_note("Path", "Combat")
    rotation.tick(player, unit, { enemies = pack, no_move = true })
    return true
end

local function path_handle_combat(player)
    if not player or not targeting or not rotation or not path_runner then
        return false
    end
    if healing and type(healing.is_resting) == "function" and healing.is_resting() then
        pause_path_for_combat()
        if movement and type(movement.is_moving) == "function" and movement.is_moving() then
            movement.nav_stop()
        end
        pcall(function()
            core.input.stop_attack()
        end)
        return true
    end
    local want_pull = gui.is_on("path_combat")
    local want_back = gui.is_on("fight_back")
    if want_pull ~= true and want_back ~= true then
        if path_runner.is_paused() then
            path_runner.resume()
        end
        return false
    end

    -- The class sets the scan; combat_range is a floor, because a scan
    -- narrower than the range the rotation actually fights at would mean
    -- walking past things it could already hit.
    local range = scan_yards(player)
    local yards = rotation_yards(player)
    if range < yards then
        range = yards
    end
    local now = izi.now()
    local unit = state.target.unit
    if unit and safe(function() return unit:is_valid() end) == true then
        if now > (state.grind.black_until or 0) and state.target.kind == "kill" then
            state.mark_killed(state.target.guid)
            state.reset_target()
            unit = nil
        end
    else
        unit = nil
        if state.target.unit then
            state.reset_target()
        end
    end

    if unit then
        if safe(function() return unit:is_dead_or_ghost() end) == true or safe(function() return unit:is_dead() end) == true then
            state.mark_killed(state.target.guid or safe(function() return unit:get_guid() end))
            movement.nav_stop()
            if type(movement.combat_release) == "function" then
                movement.combat_release()
            end
            state.reset_target()
            unit = nil
        else
            if not in_rotation_range(player, unit, yards) then
                state.reset_target()
                unit = nil
            end
        end
    end

    local pack = targeting.combat_scan(player, range)
    local pull = {}
    if want_pull == true then
        local current = path_runner.current_path and path_runner.current_path() or nil
        local mobs = current and current.mobs or nil
        pull = targeting.find_mobs(player, mobs, range, true, { skip_reach = true })
    elseif want_back == true then
        local in_combat = safe(function() return player:is_in_combat() end) == true
        if in_combat ~= true then
            if path_runner.is_paused() then
                if not movement.in_combat_movement() then
                    if type(movement.combat_release) == "function" then
                        movement.combat_release()
                    end
                    if movement.can_navigate() then
                        path_runner.resume()
                    end
                end
            end
            return false
        end
    end

    local target = closest_in_range(player, { pack, pull }, yards)
    if not target and unit and in_rotation_range(player, unit, yards) then
        target = unit
    end
    if target then
        state.grind.black_until = now + gui.slider("max_kill", 60)
        if movement.sentinel_active and movement.sentinel_active() then
            movement.nav_stop()
        end
        return path_fight(player, target, range)
    end

    if path_runner.is_paused() then
        if movement.can_navigate() then
            if type(movement.combat_release) == "function" then
                movement.combat_release()
            end
            path_runner.resume()
        elseif not movement.in_combat_movement() then
            path_runner.resume()
        end
    end
    return false
end

local function tick_rotation_only(player)
    if not player or not rotation then
        return
    end
    local target = safe(function() return player:get_target() end)
    if not target or safe(function() return target:is_valid() end) ~= true then
        state.set_note("Rotation", "Rotation Only - select a target")
        return
    end
    if safe(function() return target:is_dead_or_ghost() end) == true or safe(function() return target:is_dead() end) == true then
        state.set_note("Rotation", "Rotation Only - target dead")
        return
    end
    pcall(function()
        core.input.set_target(target)
    end)
    local pack = {}
    if targeting then
        pack = targeting.combat_scan(player, scan_yards(player))
    end
    state.set_note("Rotation", "Rotation Only")
    rotation.tick(player, target, { enemies = pack, no_move = true })
end

local function player_is_busy(player)
    if not player then
        return false
    end
    if safe(function() return player:is_channeling_or_casting() end) == true then
        return true
    end
    if safe(function() return player:is_casting_spell() end) == true then
        return true
    end
    if safe(function() return player:is_casting() end) == true then
        return true
    end
    if safe(function() return player:is_channeling() end) == true then
        return true
    end
    return false
end

local function on_update()
    if is_stale() then
        return
    end
    pcall(function()
        izi.on_update()
    end)
    if not gui then
        return
    end
    gui.process_keybinds()
    if movement then
        local want_debug = gui.is_on("move_debug") == true
        if want_debug ~= move_debug_on then
            move_debug_on = want_debug
            movement.set_debug(want_debug)
        end
        -- The movement state machine ticks before anything else reads its state,
        -- so every consumer this frame sees one consistent owner and state.
        pcall(movement.pulse)
    end

    local player = safe(function() return izi.me() end)
    if not player or safe(function() return player:is_valid() end) ~= true then
        return
    end
    gui.sync_player(player)
    if targeting then
        targeting.cache_player(player)
    end

    if spellbook then
        spellbook.tick()
        if not spellbook.ready() then
            local left = spellbook.wait_left()
            if state then
                state.set_note("Load", string.format("Waiting for spellbook  %.1fs", left))
            end
            return
        end
    end

    if gui.is_on("rotation_only") then
        halt_bot_movement()
        if vendor then
            vendor.reset()
        end
        tick_rotation_only(player)
        return
    end

    if not gui.is_started() then
        halt_bot_movement()
        if vendor then
            vendor.reset()
        end
        if combat then
            combat.reset()
        end
        return
    end
    allow_bot_movement()
    if not state or not movement or not death or not rotation or not healing then
        return
    end

    if death.tick(player) then
        return
    end
    -- Rest outranks looting. Looting used to come first, and because
    -- loot.tick returns true on every tick while a lootable corpse is in
    -- range, healing.tick was never reached - the bot would sit at 30% mana
    -- working through corpses and never drink. Resting also hard-locks
    -- movement, so loot.tick below cannot walk off mid-drink.
    if healing.tick(player) then
        return
    end
    if loot and loot.tick(player) then
        return
    end
    -- Self-buff upkeep. Sits with the class buffs because it answers the
    -- same question, and after healing.tick so a rest is never interrupted
    -- to refresh something.
    if buffs and type(buffs.tick) == "function" and buffs.tick(player) then
        return
    end
    if rotation.buffs_ooc(player) then
        return
    end
    if player_is_busy(player) then
        state.set_note("Wait", "Casting")
        return
    end

    -- Ahead of the vendor trip on purpose: both want the gossip frame, and
    -- selecting the trainer option replaces whatever is open. Training is the
    -- rarer opportunity, and vendor.tick re-opens the merchant by itself.
    if trainer and type(trainer.tick) == "function" and trainer.tick(player) then
        return
    end
    if vendor and vendor.tick(player) then
        return
    end

    -- After vendor on purpose: equipping and selling are the same underlying
    -- call (use_container_item), so this must be unreachable while a merchant
    -- window is open or an upgrade gets sold instead of worn.
    if equip and type(equip.tick) == "function" and equip.tick(player) then
        return
    end

    if path_runner then
        path_runner.stop()
    end

    local mode = gui.mode()
    if mode == modes.QUEST then
        local quest = loader and loader.ensure_quest() or nil
        if not quest then
            state.set_note("Quest", "Quest pack failed to load")
            return
        end
        if quest.is_ready(player) then
            quest.tick(player)
        else
            state.set_note("Quest", "No starter quests for this race")
        end
        return
    end

    if mode == modes.GRIND then
        local grind = loader and loader.ensure_grind() or nil
        if not grind then
            state.set_note("Grind", "Grind pack failed to load")
            return
        end
        grind.tick(player)
        return
    end
end

local function on_render()
    if movement then
        pcall(movement.on_render)
    end
    if is_stale() then
        return
    end
    if gui and gui.is_on("draw_path") and path_runner and type(path_runner.draw) == "function" then
        pcall(function()
            path_runner.draw()
        end)
    end
end

core.register_on_update_callback(on_update)
core.register_on_render_callback(on_render)

core.log(string.format("[Master Farmer - Grindbot] v%s loaded by %s", identity.version, identity.authors))

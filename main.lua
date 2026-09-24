-- ============================================================================
-- Master Farmer - Grindbot
-- Main — update cascade
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.39
-- Folder: Master_Farmer_Grindbot_v1.3.39
-- Standalone IZI. Simple Movement owns out-of-combat travel; Movement Handler owns combat face/pause. No Sentinel. No FB_Nexus. No NavLib.
-- Tick: teleport -> death -> loot -> heal -> buffs -> vendor -> grind XOR quest (Start gated)
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
    "config",
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
    core.log_error("[Master Farmer - Grindbot] GUI module failed — window will not appear.")
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
local loader = load_mod("loader")
local path_runner = load_mod("path_runner")
local modes = load_mod("modes")

if gui and rotation and type(rotation.register_gui) == "function" then
    pcall(function()
        rotation.register_gui(gui.get_menu())
    end)
end

local nav_halted = false

local function halt_bot_movement()
    if nav_halted then
        return
    end
    nav_halted = true
    if path_runner then
        path_runner.stop()
    end
    if movement then
        movement.stop()
        if type(movement.release) == "function" then
            movement.release()
        end
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

local function path_scan_range()
    local yards = 50
    if gui and type(gui.slider) == "function" then
        yards = gui.slider("path_combat_yards", 50)
    end
    local current = path_runner.current_path and path_runner.current_path() or nil
    local pull = current and tonumber(current.pull)
    if type(pull) == "number" and pull > yards then
        yards = pull
    end
    if type(yards) ~= "number" or yards < 10 then
        yards = 50
    end
    if yards > 80 then
        yards = 80
    end
    return yards
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
    if movement.needs_rejoin and movement.needs_rejoin() == true then
        if movement.is_moving() then
            movement.stop()
        elseif type(movement.rejoin_path) == "function" then
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
    movement.face_combat(unit)
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
            movement.stop()
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

    local range = path_scan_range()
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
            movement.stop_if_moving()
            if type(movement.end_engage) == "function" then
                movement.end_engage()
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
                if not (movement.patrol_blocked and movement.patrol_blocked()) then
                    if type(movement.end_engage) == "function" then
                        movement.end_engage()
                    end
                    if not movement.patrol_ready or movement.patrol_ready() then
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
            movement.stop()
        end
        return path_fight(player, target, range)
    end

    if path_runner.is_paused() then
        if movement.patrol_ready and movement.patrol_ready() then
            if type(movement.end_engage) == "function" then
                movement.end_engage()
            end
            path_runner.resume()
        elseif not (movement.patrol_blocked and movement.patrol_blocked()) then
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
        state.set_note("Rotation", "Rotation Only — select a target")
        return
    end
    if safe(function() return target:is_dead_or_ghost() end) == true or safe(function() return target:is_dead() end) == true then
        state.set_note("Rotation", "Rotation Only — target dead")
        return
    end
    pcall(function()
        core.input.set_target(target)
    end)
    local pack = {}
    if targeting then
        pack = targeting.combat_scan(player, gui.slider("path_combat_yards", 30))
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

local function teleport_halt(player, pos)
    if not gui or not state or not movement or not death then
        return false
    end
    if not gui.is_on("teleport") or not pos then
        state.teleport.x = pos and pos.x or 0
        state.teleport.y = pos and pos.y or 0
        state.teleport.z = pos and pos.z or 0
        return false
    end
    if state.teleport.x == 0 and state.teleport.y == 0 and state.teleport.z == 0 then
        state.teleport.x = pos.x
        state.teleport.y = pos.y
        state.teleport.z = pos.z
        return false
    end
    local dx = pos.x - state.teleport.x
    local dy = pos.y - state.teleport.y
    local dz = pos.z - state.teleport.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local limit = gui.slider("teleport_yards", 80)
    if d > limit and not death.is_down(player) then
        if state.teleport.alarm_until == 0 then
            state.teleport.alarm_until = izi.now() + 90
            core.log_warning("[Master Farmer - Grindbot] Teleport detected — pausing 90s")
        end
        if izi.now() < state.teleport.alarm_until then
            movement.stop()
            state.set_note("Teleport", "Paused after large move")
            return true
        end
        state.teleport.alarm_until = 0
    end
    state.teleport.x = pos.x
    state.teleport.y = pos.y
    state.teleport.z = pos.z
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
    if movement and type(movement.pulse) == "function" then
        pcall(function()
            movement.pulse()
        end)
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

    local pos = state.cached_pos
    if teleport_halt(player, pos) then
        return
    end
    if death.tick(player) then
        return
    end
    if loot and loot.tick(player) then
        return
    end
    if healing.tick(player) then
        return
    end
    if rotation.buffs_ooc(player) then
        return
    end
    if player_is_busy(player) then
        state.set_note("Wait", "Casting")
        return
    end

    if vendor and vendor.tick(player) then
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
    if movement and type(movement.on_render) == "function" then
        pcall(function()
            movement.on_render()
        end)
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

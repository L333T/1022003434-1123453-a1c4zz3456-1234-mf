-- ============================================================================
-- Master Farmer - Grindbot
-- Quest engine — starter slice from quest/data only. Never runs grind.
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ASSUMPTIONS: Undertaker Mordo=1568, Sarvis=1569, Kaltunk=10176, Gornek=3143
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local gui = require("gui")
local modes = require("modes")
local state = require("state")
local npc = require("quest/npc")
local rotation = require("rotation")
local targeting = require("targeting")
local movement = require("movement")
local healing = require("healing")

local DATA = {}
local DATA_MOD = {}

local quest = {}
local current = nil

local EMPTY_QUEST = "(no starter quests)"
local HUNT_SCAN = 0.8
local HUNT_KILL = 60.0
local HUNT_ARRIVE = 2.0

local hunt_move = 1
local hunt_scan_until = 0
local hunt_kill_until = 0
local hunt_quest_id = nil

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function list_for(player)
    local race_id = safe(function() return player:get_race_id() end)
    local key = modes.race_key(race_id)
    if not key then
        return nil, race_id, nil
    end
    local list = DATA[key]
    if type(list) == "table" then
        return list, race_id, key
    end
    for old_key, mod in pairs(DATA_MOD) do
        if old_key ~= key then
            DATA[old_key] = nil
            DATA_MOD[old_key] = nil
            package.loaded[mod] = nil
        end
    end
    local mod = "quest/data/" .. key
    local ok, data = pcall(require, mod)
    if not ok or type(data) ~= "table" then
        return nil, race_id, key
    end
    DATA[key] = data
    DATA_MOD[key] = mod
    pcall(collectgarbage, "step", 200)
    return data, race_id, key
end

local function skipped_id(id)
    if type(id) ~= "number" then
        return false
    end
    local bag = state.quest.skipped
    return type(bag) == "table" and bag[id] == true
end

local function quest_done(id)
    if type(id) ~= "number" then
        return false
    end
    return safe(function()
        return core.quests.is_quest_flagged_completed(id)
    end) == true
end

local function hunt_text(row)
    if type(row) ~= "table" or type(row.hunt) ~= "table" then
        return "Talk / travel"
    end
    local mobs = row.hunt.mobs
    if type(mobs) ~= "table" or #mobs == 0 then
        return "Talk / travel"
    end
    local parts = {}
    for i = 1, #mobs do
        parts[#parts + 1] = tostring(mobs[i])
    end
    return "Kill " .. table.concat(parts, ", ")
end

local function npc_line(player, npc_id)
    if type(npc_id) ~= "number" or npc_id <= 0 then
        return "-"
    end
    local name = npc.name_of(player, npc_id)
    if type(name) == "string" and name ~= "" then
        return string.format("%s (%d)", name, npc_id)
    end
    return tostring(npc_id)
end

local function leave_hunt()
    hunt_kill_until = 0
    if state.target and state.target.kind == "kill" then
        if movement and type(movement.combat_release) == "function" then
            movement.combat_release()
        end
        state.reset_target()
    end
end

local function combat_yards(player)
    local yards = 30
    if type(rotation.combat_range) == "function" then
        yards = rotation.combat_range(player)
    end
    if type(yards) ~= "number" or yards < 5 then
        yards = 30
    end
    return yards
end

local function fight_unit(player, unit, note)
    local now = izi.now()
    if not unit or safe(function() return unit:is_valid() end) ~= true then
        if movement and type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
        if movement and type(movement.combat_release) == "function" then
            movement.combat_release()
        end
        state.reset_target()
        return false
    end
    if hunt_kill_until > 0 and now > hunt_kill_until and state.target.kind == "kill" then
        state.mark_killed(state.target.guid)
        if movement and type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
        if movement and type(movement.combat_release) == "function" then
            movement.combat_release()
        end
        state.reset_target()
        return false
    end
    if safe(function() return unit:is_dead_or_ghost() end) == true or safe(function() return unit:is_dead() end) == true then
        state.mark_killed(state.target.guid or safe(function() return unit:get_guid() end))
        if movement and type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
        if movement and type(movement.combat_release) == "function" then
            movement.combat_release()
        end
        state.reset_target()
        return false
    end
    local dist = safe(function() return player:distance_to(unit) end) or 99
    if dist > 1000 then
        if movement and type(movement.combat_release) == "function" then
            movement.combat_release()
        end
        state.reset_target()
        return false
    end
    pcall(function()
        core.input.set_target(unit)
    end)
    local yards = combat_yards(player)
    targeting.start_auto_attack(player, unit)
    if not movement.combat_engage(player, unit, yards) then
        if state.is_unreachable and state.is_unreachable(state.target.guid) then
            if movement and type(movement.combat_release) == "function" then
                movement.combat_release()
            end
            state.reset_target()
            state.set_note("Quest", "Skip unreachable")
            return false
        end
        movement.face(unit)
        state.set_note("Quest", note or "Closing")
        rotation.tick(player, unit, { enemies = targeting.combat_scan(player, yards), no_move = true })
        return true
    end
    movement.face(unit)
    state.set_note("Quest", note or "Killing")
    rotation.tick(player, unit, { enemies = targeting.combat_scan(player, yards), no_move = true })
    return true
end

--- Walk hunt.coords and kill hunt.mobs from the quest data file. No grind zones.
local function hunt_tick(player, row)
    local hunt = row.hunt
    if type(hunt) ~= "table" then
        return
    end
    if hunt_quest_id ~= row.id then
        hunt_quest_id = row.id
        hunt_move = 1
        hunt_scan_until = 0
        hunt_kill_until = 0
        if movement and type(movement.combat_release) == "function" then
            movement.combat_release()
        end
        state.reset_target()
    end
    if healing and type(healing.is_resting) == "function" and healing.is_resting() then
        if movement and type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
        pcall(function()
            core.input.stop_attack()
        end)
        return
    end

    local now = izi.now()
    local unit = state.target.unit
    if unit and state.target.kind == "kill" then
        if fight_unit(player, unit, "Kill for " .. (row.name or tostring(row.id))) then
            return
        end
    end

    local pull = 50
    if type(hunt.pull) == "number" and hunt.pull > 0 then
        pull = hunt.pull
    end

    local enemies = targeting.find_mobs(player, hunt.mobs, pull, true)
    local next_unit = targeting.nearest(player, enemies)
    if not next_unit and now >= hunt_scan_until then
        hunt_scan_until = now + HUNT_SCAN
        local in_combat = safe(function() return player:is_in_combat() end) == true
        if in_combat then
            local pack = targeting.combat_scan(player, pull)
            next_unit = targeting.nearest(player, pack)
        end
    end
    if next_unit then
        targeting.set_current(next_unit, "kill")
        hunt_kill_until = now + HUNT_KILL
        fight_unit(player, next_unit, "Kill for " .. (row.name or tostring(row.id)))
        return
    end

    local coords = hunt.coords
    if type(coords) ~= "table" or #coords < 1 then
        state.set_note("Quest", "Waiting for objectives")
        return
    end
    local n = #coords
    if hunt_move > n then
        hunt_move = 1
    end
    local pos = coords[hunt_move]
    if not pos then
        hunt_move = hunt_move + 1
        return
    end
    if movement.arrived(pos, HUNT_ARRIVE) then
        hunt_move = hunt_move + 1
        if hunt_move > n then
            hunt_move = 1
        end
        return
    end
    if movement.is_blocked(pos) or movement.last_fail_offmesh() then
        hunt_move = hunt_move + 1
        if hunt_move > n then
            hunt_move = 1
        end
        movement.clear_fail()
        return
    end
    if movement.is_quiet() or movement.in_combat_movement() then
        state.set_note("Quest", "Nav settle")
        return
    end
    if movement.is_moving() then
        state.set_note("Quest", "Kill for " .. (row.name or tostring(row.id)))
        return
    end
    state.set_note("Quest", "Kill for " .. (row.name or tostring(row.id)))
    movement.nav_to(pos, true)
end

function quest.is_ready(player)
    if gui.mode() ~= modes.QUEST then
        return false
    end
    if not player then
        return false
    end
    if not rotation.supported(safe(function() return player:get_class() end)) then
        return false
    end
    local race_id = safe(function() return player:get_race_id() end)
    return modes.race_has_starter_quests(race_id)
end

function quest.status_text()
    if current then
        return string.format("%s (%d)", current.name or "Quest", current.id or 0)
    end
    return "No starter quest"
end

function quest.current()
    return current
end

function quest.catalog(player)
    local list = list_for(player)
    if type(list) == "table" then
        return list
    end
    return {}
end

function quest.labels(player)
    local list = quest.catalog(player)
    local labels = {}
    if #list == 0 then
        labels[1] = EMPTY_QUEST
        return labels
    end
    for i = 1, #list do
        local row = list[i]
        local name = row.name or ("Quest " .. tostring(row.id or 0))
        local mark = ""
        if skipped_id(row.id) then
            mark = " [skip]"
        elseif quest_done(row.id) then
            mark = " [done]"
        end
        labels[i] = string.format("%s (%d)%s", name, row.id or 0, mark)
    end
    return labels
end

function quest.row_at(player, index)
    local list = quest.catalog(player)
    if type(index) ~= "number" or index < 1 or index > #list then
        return nil
    end
    return list[index]
end

local function pick(player)
    local list = list_for(player)
    if type(list) ~= "table" then
        return nil
    end
    local level = safe(function() return player:get_level() end) or 1
    if gui.is_on("quest_force") == true then
        local row = quest.row_at(player, gui.quest_index())
        if row and not quest_done(row.id) and not skipped_id(row.id) then
            return row
        end
    end
    for i = 1, #list do
        local row = list[i]
        if not quest_done(row.id) and not skipped_id(row.id) then
            if level >= (row.min_level or 1) and level <= (row.max_level or 60) then
                return row
            end
        end
    end
    return nil
end

function quest.snapshot(player)
    local list, race_id, key = list_for(player)
    if type(list) ~= "table" then
        list = {}
    end
    local labels = quest.labels(player)
    local index = 1
    if gui and type(gui.quest_index) == "function" then
        index = gui.quest_index()
    end
    if index < 1 then
        index = 1
    end
    if index > #labels then
        index = #labels
    end
    local selected = list[index]
    local start_npc = selected and selected.start_npc or nil
    local end_npc = selected and selected.end_npc or nil
    local on_it = false
    if selected and selected.id then
        on_it = safe(function() return core.quests.is_on_quest(selected.id) end) == true
    end
    local complete = false
    if selected and selected.id and on_it then
        complete = npc.is_complete(selected.id, selected.name) == true
    end
    local phase = "-"
    if selected then
        if skipped_id(selected.id) then
            phase = "Skipped"
        elseif quest_done(selected.id) then
            phase = "Completed"
        elseif not on_it then
            phase = "Accept at start NPC"
        elseif complete then
            phase = "Turn in at end NPC"
        elseif selected.hunt then
            phase = "Hunt"
        else
            phase = "Travel to end NPC"
        end
    end
    return {
        race_id = race_id,
        race_key = key,
        race_label = modes.race_label(race_id) or "Unknown",
        race_ok = modes.race_has_starter_quests(race_id) == true,
        count = #list,
        labels = labels,
        index = index,
        selected = selected,
        current = current,
        status = quest.status_text(),
        note = state.note or "",
        phase = phase,
        start_npc = start_npc,
        end_npc = end_npc,
        start_name = npc_line(player, start_npc),
        end_name = npc_line(player, end_npc),
        hunt = hunt_text(selected),
        min_level = selected and selected.min_level or nil,
        max_level = selected and selected.max_level or nil,
        map_id = selected and selected.start and selected.start.map_id or nil,
        done = selected and quest_done(selected.id) or false,
        skipped = selected and skipped_id(selected.id) or false,
        on_quest = on_it,
    }
end

function quest.tick(player)
    current = pick(player)
    if not current then
        leave_hunt()
        hunt_quest_id = nil
        state.set_note("Quest", "Starters complete")
        return
    end
    state.quest.id = current.id
    local on_it = safe(function() return core.quests.is_on_quest(current.id) end) == true
    if not on_it then
        leave_hunt()
        state.set_note("Quest", "Accept " .. (current.name or tostring(current.id)))
        if npc.at_npc(player, current.start_npc, current.start) then
            npc.accept(player, current.id, current.name, current.start_npc)
        end
        return
    end
    if npc.is_complete(current.id, current.name) then
        leave_hunt()
        state.set_note("Quest", "Turn in " .. (current.name or tostring(current.id)))
        if npc.at_npc(player, current.end_npc, current.finish) then
            npc.turn_in(player, current.id, current.name, current.end_npc)
        end
        return
    end
    if current.hunt then
        hunt_tick(player, current)
        return
    end
    leave_hunt()
    state.set_note("Quest", "Travel " .. (current.name or tostring(current.id)))
    npc.at_npc(player, current.end_npc, current.finish)
end

return quest

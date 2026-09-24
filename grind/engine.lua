-- ============================================================================
-- Master Farmer - Grindbot
-- Patrol / kill / loot machine
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local gui = require("gui")
local state = require("state")
local targeting = require("targeting")
local movement = require("movement")
local rotation = require("rotation")
local healing = require("healing")
local grind_zones = require("grind/zone_lookup")

local grind = {}

local hunt = nil
local profile = nil
local SCAN_GAP = 0.8
local AREA_YARDS = 80.0
local OFF_PATH = 8.0

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function row_xyz(row)
    if type(row) ~= "table" then
        return nil
    end
    local x, y, z = row.x, row.y, row.z
    if type(x) ~= "number" then
        x, y, z = row[1], row[2], row[3]
    end
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil
    end
    return x, y, z
end

local function dist_here(here, row)
    if not here then
        return nil
    end
    local x, y, z = row_xyz(row)
    if not x then
        return nil
    end
    local dx = here.x - x
    local dy = here.y - y
    local dz = (here.z or 0) - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function grind.set_hunt(spec)
    hunt = spec
end

function grind.clear_hunt()
    hunt = nil
end

function grind.set_profile(path)
    profile = path
    hunt = nil
end

function grind.clear_profile()
    profile = nil
    hunt = nil
end

--- Turn a loaded grind path into the zone shape the engine walks.
---
--- `mobs` is deliberately allowed to be nil. The zone tables name specific npc
--- ids because they describe a camp; a PathTool route describes a LOOP through
--- an area and should engage whatever is on it. targeting.id_wanted treats a
--- nil or empty list as "any npc", and the level band, tap rules and
--- reachability checks still apply - so a route with no mob list is not
--- unfiltered, it is just not restricted to a hand-listed set.
local function path_to_zone(path)
    if type(path) ~= "table" or type(path.waypoints) ~= "table" or #path.waypoints < 1 then
        return nil
    end
    return {
        coords = path.waypoints,
        mobs = path.mobs,
        pull = path.pull or 50,
        merchant = path.merchant,
        map_id = path.map_id,
        name = path.name,
    }
end

local function current_zone(player)
    if hunt then
        return hunt
    end
    if profile then
        local zone = path_to_zone(profile)
        if zone then
            return zone
        end
    end
    if not player then
        return nil
    end
    local race_id = safe(function() return player:get_race_id() end)
    local level = safe(function() return player:get_level() end) or 1
    return grind_zones.lookup(race_id, level)
end

local function node_row(zone, index)
    if not zone or type(zone.coords) ~= "table" then
        return nil
    end
    local n = #zone.coords
    if n < 1 then
        return nil
    end
    if index > n then
        index = 1
        state.grind.move = 1
    end
    return zone.coords[index], n
end

local function snap_grind_node(zone, n, here)
    if not zone or not here or type(n) ~= "number" or n < 1 then
        return
    end
    local best_i = state.grind.move
    local best_d = 1e9
    for i = 1, n do
        local d = dist_here(here, zone.coords[i])
        if type(d) == "number" and d < best_d then
            best_d = d
            best_i = i
        end
    end
    if type(best_d) ~= "number" or best_d > AREA_YARDS then
        return
    end
    local cur_d = dist_here(here, zone.coords[state.grind.move])
    if type(cur_d) ~= "number" or cur_d > OFF_PATH or best_d + 4.0 < cur_d then
        if best_i ~= state.grind.move then
            state.grind.move = best_i
        end
    end
end

function grind.kill_mobs(player)
    if not player then
        return
    end
    if healing and type(healing.is_resting) == "function" and healing.is_resting() then
        if movement and type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
        return
    end
    local zone = current_zone(player)
    local mobs = zone and zone.mobs or nil
    local pull = 50
    if zone and type(zone.pull) == "number" and zone.pull > 0 then
        pull = zone.pull
    end
    local enemies = targeting.find_mobs(player, mobs, pull, true)
    local unit = targeting.nearest(player, enemies)
    if unit then
        targeting.set_current(unit, "kill")
        state.grind.step = 2
        state.grind.black_until = izi.now() + gui.slider("max_kill", 60)
        state.set_note("Grind", "Closing")
        return
    end
    if not zone or type(zone.coords) ~= "table" then
        state.set_note("Grind", "No grind path for this race/level")
        return
    end
    local coords = zone.coords
    if type(movement.plan_grind_route) == "function" then
        movement.plan_grind_route(coords)
    end

    local order = nil
    if type(movement.grind_visit_order) == "function" then
        order = movement.grind_visit_order()
    end
    local using_order = type(order) == "table" and #order > 0
    local n
    local pos
    if using_order then
        n = #order
        if state.grind.move > n then
            state.grind.move = 1
        end
        local coord_i = order[state.grind.move]
        if type(coord_i) == "number" then
            pos = coords[coord_i]
        end
        if not pos then
            pos, n = node_row(zone, state.grind.move)
            using_order = false
        end
    else
        pos, n = node_row(zone, state.grind.move)
        if not pos then
            state.set_note("Grind", "No grind path for this race/level")
            return
        end
        snap_grind_node(zone, n, state.cached_pos)
        pos, n = node_row(zone, state.grind.move)
    end
    if not pos then
        return
    end
    local function skip_node(why)
        core.log_warning("[Master Farmer - Grindbot] Grind skip node " .. tostring(state.grind.move) .. " (" .. tostring(why) .. ")")
        state.grind.move = state.grind.move + 1
        if state.grind.move > n then
            state.grind.move = 1
        end
        movement.clear_fail()
    end
    if movement.arrived(pos, 2) then
        if gui.is_on("random_path") and n > 2 then
            if math.random(1, 10) > 5 then
                state.grind.move = state.grind.move + 1
            else
                state.grind.move = state.grind.move + 2
            end
        else
            state.grind.move = state.grind.move + 1
        end
        if state.grind.move > n then
            state.grind.move = 1
        end
        return
    end
    if type(movement.node_reachable) == "function" and movement.node_reachable(pos, state.grind.move) == false then
        skip_node("unreachable")
        return
    end
    if movement.is_blocked(pos) or movement.last_fail_offmesh() then
        skip_node(movement.last_fail_reason() or "blacklist")
        return
    end
    if movement.is_quiet() or movement.in_combat_movement() then
        state.set_note("Grind", "Nav settle")
        return
    end
    if movement.is_moving() then
        state.set_note("Grind", string.format("%s  node %d / %d", tostring(zone.name or "Patrol"), state.grind.move, n))
        return
    end
    state.set_note("Grind", string.format("%s  node %d / %d", tostring(zone.name or "Patrol"), state.grind.move, n))
    movement.nav_to(pos, true)
end

function grind.tick(player)
    if not player then
        return
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

    if state.grind.step == 1 then
        if now < state.grind.scan_until then
            grind.kill_mobs(player)
            return
        end
        state.grind.scan_until = now + SCAN_GAP
        local in_combat = safe(function() return player:is_in_combat() end) == true
        local hp = safe(function() return player:get_health_percentage() end) or 100
        local want_back = in_combat
            or (gui.is_on("fight_back") and hp <= gui.slider("fight_back_hp", 70))
        if want_back then
            local pack = targeting.combat_scan(player, gui.slider("fight_back_yards", 30))
            local unit = targeting.nearest(player, pack)
            if unit then
                targeting.set_current(unit, "kill")
                state.grind.step = 2
                state.grind.black_until = now + gui.slider("max_kill", 60)
                state.set_note("Grind", "Fight back")
                return
            end
        end
        grind.kill_mobs(player)
        return
    end

    local unit = state.target.unit
    if not unit or safe(function() return unit:is_valid() end) ~= true then
        movement.nav_stop()
        movement.combat_release()
        state.reset_target()
        state.grind.step = 1
        return
    end
    if now > state.grind.black_until and state.target.kind == "kill" then
        state.mark_killed(state.target.guid)
        movement.nav_stop()
        movement.combat_release()
        state.reset_target()
        state.grind.step = 1
        return
    end
    if safe(function() return unit:is_dead_or_ghost() end) == true or safe(function() return unit:is_dead() end) == true then
        state.mark_killed(state.target.guid or safe(function() return unit:get_guid() end))
        movement.nav_stop()
        movement.combat_release()
        state.reset_target()
        state.grind.step = 1
        return
    end

    local dist = safe(function() return player:distance_to(unit) end) or 99
    if dist > 1000 then
        movement.combat_release()
        state.reset_target()
        state.grind.step = 1
        return
    end
    pcall(function()
        core.input.set_target(unit)
    end)
    local yards = 30
    if type(rotation.combat_range) == "function" then
        yards = rotation.combat_range(player)
    end
    if type(yards) ~= "number" or yards < 5 then
        yards = 30
    end
    targeting.start_auto_attack(player, unit)
    if not movement.combat_engage(player, unit, yards) then
        if state.is_unreachable and state.is_unreachable(state.target.guid) then
            movement.combat_release()
            state.reset_target()
            state.grind.step = 1
            state.set_note("Grind", "Skip unreachable")
            return
        end
        movement.face(unit)
        state.set_note("Grind", "Closing")
        rotation.tick(player, unit, { enemies = targeting.combat_scan(player, yards), no_move = true })
        return
    end
    movement.face(unit)
    local pack = targeting.combat_scan(player, yards)
    state.set_note("Grind", "Killing")
    rotation.tick(player, unit, { enemies = pack, no_move = true })
end

return grind

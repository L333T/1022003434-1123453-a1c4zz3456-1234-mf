-- ============================================================================
-- Master Farmer - Grindbot
-- Death run — release, path graveyard to corpse, retrieve
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type vec3
local vec3 = require("common/geometry/vector_3")

---@type unit_helper
local unit_helper = require("common/utility/unit_helper")

local gui = require("gui")
local movement = require("movement")
local state = require("state")

local death = {}

local RELEASE_GAP = 3.0
local RETRIEVE_RANGE = 32.0
local HOSTILE_RANGE = 8.0
local SAFE_OFFSET = 10.0
local RETRIEVE_GAP = 1.5

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function pause_path()
    local ok, path_runner = pcall(require, "path_runner")
    if ok and path_runner and type(path_runner.pause) == "function" then
        path_runner.pause()
    end
end

local function resume_path()
    local ok, path_runner = pcall(require, "path_runner")
    if ok and path_runner and type(path_runner.resume) == "function" then
        path_runner.resume()
    end
end

local function as_vec3(pos)
    if type(pos) ~= "table" then
        return nil
    end
    local x, y, z = pos.x, pos.y, pos.z
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil
    end
    if x == 0 and y == 0 and z == 0 then
        return nil
    end
    return vec3.new(x, y, z)
end

local function corpse_position()
    local raw = safe(function()
        return core.game_ui.get_corpse_position()
    end)
    local vec = as_vec3(raw)
    if vec then
        state.dead.corpse = vec
        return vec
    end
    return as_vec3(state.dead.corpse)
end

local function dist_to(pos)
    local here = state.cached_pos
    if not here or not pos then
        return nil
    end
    local dx = here.x - pos.x
    local dy = here.y - pos.y
    local dz = (here.z or 0) - (pos.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function hostiles_near(pos, yards)
    if not pos then
        return false
    end
    local list = safe(function()
        return unit_helper:get_enemy_list_around(pos, yards, true, false, false, false)
    end)
    if type(list) ~= "table" then
        return false
    end
    for i = 1, #list do
        local u = list[i]
        if u and safe(function() return u:is_valid() end) == true then
            if safe(function() return u:is_dead_or_ghost() end) ~= true then
                if safe(function() return u:is_player() end) ~= true then
                    if safe(function() return u:is_dummy() end) ~= true then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function safe_retrieve_pos(corpse)
    if not corpse then
        return nil
    end
    if not hostiles_near(corpse, HOSTILE_RANGE) then
        return corpse
    end
    local offsets = {
        { SAFE_OFFSET, SAFE_OFFSET },
        { -SAFE_OFFSET, SAFE_OFFSET },
        { -SAFE_OFFSET, -SAFE_OFFSET },
        { SAFE_OFFSET, -SAFE_OFFSET },
    }
    for i = 1, #offsets do
        local candidate = vec3.new(corpse.x + offsets[i][1], corpse.y + offsets[i][2], corpse.z)
        if not hostiles_near(candidate, HOSTILE_RANGE) then
            return candidate
        end
    end
    return corpse
end

local function run_to(dest)
    if not dest then
        return
    end
    if movement.last_fail_offmesh() then
        movement.move_direct(dest)
        movement.clear_fail()
        return
    end
    movement.move_to(dest)
end

function death.is_down(player)
    if not player then
        return false
    end
    if safe(function() return player:is_dead_or_ghost() end) == true then
        return true
    end
    if safe(function() return player:is_dead() end) == true then
        return true
    end
    if safe(function() return player:is_ghost() end) == true then
        return true
    end
    return false
end

local function begin_death()
    if state.dead.waiting then
        return
    end
    state.dead.waiting = true
    state.dead.corpse = nil
    state.dead.retrieve_at = 0
    state.grind.step = 1
    state.reset_target()
    if type(movement.set_resting) == "function" then
        movement.set_resting(false)
    end
    pause_path()
    movement.stop()
end

local function end_death()
    if not state.dead.waiting then
        return
    end
    state.dead.waiting = false
    state.dead.corpse = nil
    resume_path()
end

function death.tick(player)
    if not gui.is_started() then
        return false
    end
    if not death.is_down(player) then
        end_death()
        return false
    end

    begin_death()

    local now = izi.now()
    local is_ghost = safe(function() return player:is_ghost() end) == true
    if not is_ghost then
        if (now - (state.dead.released_at or 0)) >= RELEASE_GAP then
            state.dead.released_at = now
            pcall(function()
                core.input.release_spirit()
            end)
        end
        state.set_note("Death", "Releasing spirit")
        return true
    end

    local corpse = corpse_position()
    if not corpse then
        state.set_note("Death", "Waiting for corpse position")
        return true
    end

    local dest = safe_retrieve_pos(corpse)
    local d = dist_to(dest) or dist_to(corpse)
    if type(d) ~= "number" then
        run_to(dest)
        state.set_note("Death", "Running to corpse")
        return true
    end

    if d > RETRIEVE_RANGE then
        run_to(dest)
        state.set_note("Death", string.format("Corpse  %.0f yd", d))
        return true
    end

    movement.stop()
    local delay = safe(function()
        return core.game_ui.get_resurrect_corpse_delay()
    end) or 0
    if type(delay) == "number" and delay > 0 then
        state.set_note("Death", string.format("Retrieve in %.0fs", delay))
        return true
    end
    if (now - (state.dead.retrieve_at or 0)) >= RETRIEVE_GAP then
        state.dead.retrieve_at = now
        pcall(function()
            core.input.resurrect_corpse()
        end)
    end
    state.set_note("Death", "Retrieving corpse")
    return true
end

return death

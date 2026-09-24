-- ============================================================================
-- Master Farmer - Grindbot
-- Corpse loot after a kill (IZI: enemies_if, can_be_looted, has_loot, loot_object)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type inventory_helper
local inventory_helper = require("common/utility/inventory_helper")

local gui = require("gui")
local state = require("state")
local targeting = require("targeting")
local movement = require("movement")

local loot = {}

local INTERACT_YARDS = 5
local NEAR_SCAN_YARDS = 10
local KILL_SCAN_YARDS = 40
local PAUSE_SEC = 0.5
local ATTEMPT3_GAP = 0.02
local CYCLE_COOLDOWN = 0.4
local MAX_CYCLES = 6
local STATE_CAP = 48

-- guid -> { cycle_attempt, last_attempt, blocked_until, cycles }
local looted_units = {}
local loot_order = {}

local function guid_of(unit)
    if not unit then
        return nil
    end
    local ok, guid = pcall(unit.get_guid, unit)
    if ok and type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

local function prune_states()
    if #loot_order <= STATE_CAP then
        return
    end
    while #loot_order > STATE_CAP do
        local old = table.remove(loot_order, 1)
        if old then
            looted_units[old] = nil
        end
    end
end

local function unit_state(guid)
    local st = looted_units[guid]
    if st then
        return st
    end
    st = {
        cycle_attempt = 0,
        last_attempt = 0,
        blocked_until = 0,
        cycles = 0,
    }
    looted_units[guid] = st
    loot_order[#loot_order + 1] = guid
    prune_states()
    return st
end

local function bags_too_full()
    if not inventory_helper or type(inventory_helper.get_total_free_slots) ~= "function" then
        return false
    end
    local ok, free = pcall(inventory_helper.get_total_free_slots, inventory_helper)
    if not ok or type(free) ~= "number" then
        return false
    end
    return free <= 1
end

local function is_lootable(corpse)
    if not corpse then
        return false
    end
    local ok_valid, valid = pcall(corpse.is_valid, corpse)
    if not ok_valid or valid ~= true then
        return false
    end
    local ok_can, can = pcall(corpse.can_be_looted, corpse)
    local ok_has, has = pcall(corpse.has_loot, corpse)
    return ok_can == true and can == true and ok_has == true and has == true
end

local function fire_loot(corpse)
    if core.input and type(core.input.loot_object) == "function" then
        pcall(core.input.loot_object, corpse, true)
    end
    if movement and type(movement.pause_for_loot) == "function" then
        movement.pause_for_loot(PAUSE_SEC)
    elseif movement and type(movement.nav_stop) == "function" then
        movement.nav_stop()
    end
end

-- Attempt 1 instant, attempt 2 next frame, attempt 3 after 20ms, then 400ms cooldown.
-- Returns "fired", "wait", or "skip".
local function attempt_loot(corpse, now)
    local guid = guid_of(corpse)
    if not guid then
        return "skip"
    end
    local st = unit_state(guid)
    if st.cycles >= MAX_CYCLES then
        return "skip"
    end
    if st.blocked_until > 0 and now < st.blocked_until then
        return "wait"
    end
    if st.blocked_until > 0 and now >= st.blocked_until and st.cycle_attempt ~= 0 then
        st.cycle_attempt = 0
        st.blocked_until = 0
    end

    local attempt = st.cycle_attempt or 0
    if attempt == 0 or attempt == 1 then
        st.cycle_attempt = attempt + 1
        st.last_attempt = now
        fire_loot(corpse)
        return "fired"
    end
    if attempt == 2 then
        if now - (st.last_attempt or 0) < ATTEMPT3_GAP then
            return "wait"
        end
        st.cycle_attempt = 0
        st.last_attempt = now
        st.blocked_until = now + CYCLE_COOLDOWN
        st.cycles = (st.cycles or 0) + 1
        fire_loot(corpse)
        return "fired"
    end
    st.cycle_attempt = 0
    st.blocked_until = 0
    return "wait"
end

local function pick_corpse(player, mine_only)
    local current = state.target and state.target.unit or nil
    if current then
        local ok_dead, dead = pcall(current.is_dead, current)
        if ok_dead == true and dead == true and is_lootable(current) then
            local ok_d, dist = pcall(player.distance_to, player, current)
            if ok_d and type(dist) == "number" then
                return current, dist
            end
        end
    end

    local scan = mine_only and KILL_SCAN_YARDS or NEAR_SCAN_YARDS
    local list = targeting.find_corpses(player, scan)
    if type(list) ~= "table" or #list == 0 then
        return nil, 99
    end
    local best = nil
    local best_d = 9999
    for i = 1, #list do
        local corpse = list[i]
        if is_lootable(corpse) then
            local allow = true
            if mine_only then
                local guid = guid_of(corpse)
                allow = guid and state.was_killed(guid) == true
            end
            if allow then
                local ok_d, dist = pcall(player.distance_to, player, corpse)
                if ok_d and type(dist) == "number" and dist < best_d then
                    best = corpse
                    best_d = dist
                end
            end
        end
    end
    return best, best_d
end

function loot.tick(player)
    -- Defence in depth for the cascade order in main.lua. Walking to a corpse
    -- cancels eating and drinking, so looting never runs during a rest even if
    -- that ordering is changed later. Required lazily: healing.lua requires
    -- rotation, so a top-level require here would close a cycle.
    do
        local ok_h, healing = pcall(require, "healing")
        if ok_h and healing and type(healing.is_resting) == "function" then
            if healing.is_resting() == true then
                return false
            end
        end
    end
    if not gui or not gui.is_on("loot") then
        return false
    end
    if not player then
        return false
    end
    local ok_valid, valid = pcall(player.is_valid, player)
    if not ok_valid or valid ~= true then
        return false
    end
    local ok_dead, dead = pcall(player.is_dead, player)
    if ok_dead and dead == true then
        return false
    end
    if state.vendor and state.vendor.active then
        return false
    end
    if bags_too_full() then
        return false
    end

    local mine_only = gui.is_on("loot_mine") == true
    local corpse, dist = pick_corpse(player, mine_only)
    if not corpse then
        return false
    end

    if dist > INTERACT_YARDS then
        local ok_pos, pos = pcall(corpse.get_position, corpse)
        -- Only claim the tick when movement actually accepted the walk. If the
        -- combat controller owns the player, nav_to is refused - returning true
        -- there would swallow the tick and starve the combat rotation.
        if ok_pos and pos and movement and movement.nav_to(pos) then
            state.set_note("Loot", "Walking to corpse")
            return true
        end
        return false
    end

    local now = izi.now()
    local result = attempt_loot(corpse, now)
    if result == "fired" then
        state.set_note("Loot", "Looting")
        return true
    end
    if result == "wait" then
        if movement and type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
        state.set_note("Loot", "Looting")
        return true
    end
    return false
end

return loot

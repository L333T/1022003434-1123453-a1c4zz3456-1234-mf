-- ============================================================================
-- Master Farmer - Grindbot
-- Quest NPC interact / gossip / accept / turn-in
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local movement = require("movement")
local targeting = require("targeting")
local state = require("state")

local npc = {}

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function gossip_open()
    if izi.gossip and type(izi.gossip.is_open) == "function" then
        if safe(function() return izi.gossip.is_open() end) == true then
            return true
        end
    end
    return safe(function() return core.quests.is_gossip_frame_shown() end) == true
end

local function gossip_close()
    if izi.gossip and type(izi.gossip.close) == "function" then
        pcall(function()
            izi.gossip.close()
        end)
    end
    pcall(function()
        core.quests.close_gossip()
    end)
end

function npc.name_of(player, npc_id)
    if not player or not npc_id then
        return nil
    end
    local unit = targeting.find_npc(player, npc_id, 80)
    if not unit then
        return nil
    end
    local name = safe(function() return unit:get_name() end)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

function npc.go_and_interact(player, npc_id, dest)
    local unit = targeting.find_npc(player, npc_id, 80)
    if unit then
        local d = safe(function() return player:distance_to(unit) end) or 99
        if d > 4 then
            local p = safe(function() return unit:get_position() end) or dest
            movement.move_to(p)
            return false
        end
        movement.stop()
        if izi.now() < state.quest.interact_until then
            return false
        end
        state.quest.interact_until = izi.now() + 1.2
        pcall(function()
            core.input.interact_with_object(unit)
        end)
        return true
    end
    if dest then
        if movement.arrived(dest, 4) then
            return false
        end
        movement.move_to(dest)
    end
    return false
end

function npc.accept(quest_id)
    if gossip_open() then
        local list = safe(function() return core.quests.get_gossip_available_quests() end)
        if type(list) == "table" then
            for i = 1, #list do
                if list[i].quest_id == quest_id then
                    pcall(function()
                        core.quests.select_gossip_available_quest(quest_id)
                    end)
                    break
                end
            end
        end
    end
    pcall(function()
        core.quests.accept_quest()
    end)
end

function npc.turn_in(quest_id)
    if gossip_open() then
        pcall(function()
            core.quests.select_gossip_active_quest(quest_id)
        end)
    end
    pcall(function()
        core.quests.complete_quest()
    end)
    pcall(function()
        core.quests.get_quest_reward(0)
    end)
end

function npc.close()
    pcall(function()
        core.quests.close_quest()
    end)
    gossip_close()
end

function npc.is_complete(quest_id)
    pcall(function()
        core.quests.expand_quest_header(0)
    end)
    local n = safe(function() return core.quests.get_num_quest_log_entries() end) or 0
    for i = 1, n do
        local entry = safe(function() return core.quests.get_quest_log_title(i) end)
        if type(entry) == "table" and entry.quest_id == quest_id then
            if entry.is_complete == 1 then
                return true
            end
            local boards = safe(function() return core.quests.get_num_quest_leader_boards(i) end) or 0
            if boards > 0 then
                local all = true
                for b = 1, boards do
                    local obj = safe(function() return core.quests.get_quest_log_leader_board(b, i) end)
                    if not (type(obj) == "table" and obj.is_completed == true) then
                        all = false
                    end
                end
                return all
            end
            return false
        end
    end
    local gossip = safe(function() return core.quests.get_gossip_active_quests() end)
    if type(gossip) == "table" then
        for i = 1, #gossip do
            if gossip[i].quest_id == quest_id and gossip[i].is_complete == true then
                return true
            end
        end
    end
    return false
end

return npc

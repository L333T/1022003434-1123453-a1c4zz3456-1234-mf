-- ============================================================================
-- Master Farmer - Grindbot
-- Shared runtime state (no leaked globals)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

local state = {
    note = "",
    note_head = "",
    cached_pos = nil,
    cached_now = 0,
    last_action = "Idle",
}

state.grind = {
    step = 1,
    move = 1,
    scan_until = 0,
    black_until = 0,
    killed = {},
    killed_order = {},
    killed_reset = 0,
}

state.target = {
    unit = nil,
    guid = nil,
    x = nil,
    y = nil,
    z = nil,
    kind = nil,
}

state.dead = {
    released_at = 0,
    waiting = false,
    corpse = nil,
    retrieve_at = 0,
}

state.combat = {
    -- kiting is owned by movement.lua's combat controller, not by the rotation
    nova_at = 0,
    face_at = 0,
    unreachable = {},
}

state.quest = {
    id = nil,
    step = 1,
    interact_until = 0,
    skipped = {},
}

state.vendor = {
    active = false,
    repaired = false,
    sold = 0,
    interact_until = 0,
    done_until = 0,
    lack_gold = 0,
    wait_npc = 0,
    tries = 0,
}

function state.set_note(head, text)
    state.note_head = head or ""
    state.note = text or ""
end

function state.reset_target()
    state.target.unit = nil
    state.target.guid = nil
    state.target.x = nil
    state.target.y = nil
    state.target.z = nil
    state.target.kind = nil
end

local KILLED_MAX = 48

local function guid_key(guid)
    if guid == nil then
        return nil
    end
    local t = type(guid)
    if t == "string" then
        if guid == "" then
            return nil
        end
        return guid
    end
    if t == "number" then
        return tostring(guid)
    end
    local ok, text = pcall(tostring, guid)
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

function state.mark_killed(guid)
    local key = guid_key(guid)
    if not key then
        return
    end
    local killed = state.grind.killed
    if killed[key] then
        return
    end
    killed[key] = true
    local order = state.grind.killed_order
    if type(order) ~= "table" then
        order = {}
        state.grind.killed_order = order
    end
    order[#order + 1] = key
    while #order > KILLED_MAX do
        local old = table.remove(order, 1)
        if old then
            killed[old] = nil
        end
    end
end

function state.was_killed(guid)
    local key = guid_key(guid)
    if not key then
        return false
    end
    return state.grind.killed[key] == true
end

local UNREACH_TTL = 45.0

local function now_s()
    local ok, t = pcall(function()
        return core.time()
    end)
    if ok and type(t) == "number" then
        return t
    end
    return 0
end

function state.mark_unreachable(guid)
    local key = guid_key(guid)
    if not key then
        return
    end
    if type(state.combat.unreachable) ~= "table" then
        state.combat.unreachable = {}
    end
    state.combat.unreachable[key] = now_s()
end

function state.is_unreachable(guid)
    local key = guid_key(guid)
    if not key then
        return false
    end
    local bag = state.combat.unreachable
    if type(bag) ~= "table" then
        return false
    end
    local stamped = bag[key]
    if type(stamped) ~= "number" then
        return false
    end
    if (now_s() - stamped) > UNREACH_TTL then
        bag[key] = nil
        return false
    end
    return true
end

return state

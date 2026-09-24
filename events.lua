-- ============================================================================
-- Master Farmer - Grindbot
-- Game events - the confirmations the client holds open until answered
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- WHY THIS FILE EXISTS
--   Four game events are not notifications. They report an action the engine
--   has WITHHELD and is holding open until something answers it. Nothing times
--   them out. A plugin that never registers them simply stalls at the point
--   the client asked a question.
--
--   The bot was answering one of the four and ignoring the rest:
--
--     AUTOEQUIP_BIND_CONFIRM  answered already, by polling
--     EQUIP_BIND_CONFIRM      answered already, by polling
--     LOOT_BIND_CONFIRM       NOT ANSWERED - see below
--     CONFIRM_BINDER          not answered, never fired either
--
-- THE ONE THAT COST SOMETHING
--   Looting a bind-on-pickup item raises LOOT_BIND_CONFIRM and holds that slot
--   open. The bot never answered, so the slot never completed: every BoP drop
--   was left on the corpse while loot.lua burned its three attempts and gave
--   up. On a levelling grind bot that is precisely the loot worth having -
--   greens, blues, quest items.
--
--   The equip pair is different: core.game_ui.get_pending_equip_slot() latches
--   the value, so equip.lua could answer it by polling and does. There is NO
--   equivalent reader for the loot slot. The event is the only place the slot
--   number exists, which is why this file has to exist rather than being a
--   nicety.
--
-- THE OFF-BY-ONE
--   LOOT_BIND_CONFIRM reports WoW's 1-BASED loot slot. confirm_loot_slot takes
--   the 0-BASED index that loot_item and every get_loot_* reader use. Passing
--   args[1] straight through confirms the slot AFTER the one that asked - so a
--   naive forward is not a no-op, it accepts the wrong item.
--
-- WHAT IS DELIBERATELY NOT REGISTERED
--   The cast and aura families, and the combat log. The documentation is
--   explicit that a rotation should ask game_object what a unit is casting
--   right now rather than track edges, and every rotation here already polls.
--   Registering UNIT_SPELLCAST_* would fire for every nameplate in the zone to
--   answer a question nothing is asking.
--
-- REGISTERING ONCE
--   "Each plugin has a maximum number of callbacks; exceeding it raises a Lua
--   error, so register once." This plugin hot-reloads by clearing
--   package.loaded, which re-runs every module - so a module-local guard would
--   reset on each reload and register again until the cap blew. The guard
--   lives on _G.MasterFarmer_Grindbot, which survives a reload, and the
--   handler table is re-read through it so a reload still picks up new code.
-- ============================================================================

local events = {}

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- HANDLERS
-- ----------------------------------------------------------------------------
-- One function per event name, the dispatch shape the documentation uses.
local handlers = {}

--- A bind-on-pickup item is waiting on us. Answer it, or it stays on the corpse.
function handlers.LOOT_BIND_CONFIRM(args)
    local slot = args and args[1]
    if type(slot) ~= "number" then
        return
    end
    -- 1-based from the event, 0-based into the call. See the note above.
    local zero_based = slot - 1
    if zero_based < 0 then
        return
    end
    core.log(string.format(
        "[Master Farmer - Grindbot] Confirming bind-on-pickup loot, slot %d.", slot))
    safe(function() return core.input.confirm_loot_slot(zero_based) end)
end

--- The equip confirms. equip.lua also answers these by polling the latched
--- slot; answering on the edge as well just means the upgrade goes on a frame
--- earlier, and equip_pending_item on an already-answered slot is harmless.
local function confirm_equip(args)
    local slot = args and args[1]
    if type(slot) ~= "number" or slot < 0 then
        return
    end
    safe(function() return core.input.equip_pending_item(slot) end)
end

handlers.AUTOEQUIP_BIND_CONFIRM = confirm_equip
handlers.EQUIP_BIND_CONFIRM = confirm_equip

--- Never fires for this bot, which sets no hearthstone. One line so that if it
--- ever does, the client is not left waiting for an answer nobody sends.
function handlers.CONFIRM_BINDER(args)
    core.log("[Master Farmer - Grindbot] Confirming binder: " .. tostring(args and args[1]))
    safe(function() return core.input.confirm_binder() end)
end

events.handlers = handlers

-- ----------------------------------------------------------------------------
-- REGISTRATION
-- ----------------------------------------------------------------------------
_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot

--- Dispatch one event. Reads the handler table off the namespace rather than
--- the upvalue, so the callback registered by an earlier load still runs the
--- CURRENT code after a hot reload.
local function dispatch(event_name, args)
    local live = NS.event_handlers
    if type(live) ~= "table" then
        return
    end
    local handler = live[event_name]
    if not handler then
        return
    end
    local ok, err = pcall(handler, args)
    if not ok then
        core.log_error("[Master Farmer - Grindbot] game event " .. tostring(event_name)
            .. ": " .. tostring(err))
    end
end

--- Register once per session, however many times the plugin reloads.
function events.install()
    NS.event_handlers = handlers

    if NS.events_registered == true then
        return false
    end
    if type(core.register_on_game_event_callback) ~= "function" then
        core.log_warning("[Master Farmer - Grindbot] core.register_on_game_event_callback "
            .. "is not available; bind-on-pickup loot will not be confirmed.")
        return false
    end

    local ok = pcall(core.register_on_game_event_callback, dispatch)
    if not ok then
        core.log_error("[Master Farmer - Grindbot] failed to register the game event callback.")
        return false
    end

    NS.events_registered = true
    core.log("[Master Farmer - Grindbot] Game events armed (loot and equip bind confirms).")
    return true
end

return events

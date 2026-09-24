-- ============================================================================
-- Master Farmer - Grindbot
-- Quest NPC interact / gossip / accept / turn-in
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- TWO FRAMES, NOT ONE
--   An NPC with quests shows either a GOSSIP frame (get_gossip_*_quests, keyed
--   by quest id) or a QUEST GREETING frame (get_available_title / get_active_
--   title, keyed by a 1-based INDEX). Only the gossip path existed before, so a
--   greeting-frame NPC fell through to a bare accept_quest() with nothing
--   selected and the bot stalled. Both paths are handled here.
--
-- COMPLETE vs GET_QUEST_REWARD ARE ALTERNATIVES
--   complete_quest() is for a quest with no reward choice. get_quest_reward(i)
--   SELECTS choice i AND completes the quest. They were being called one after
--   the other, which meant a quest offering a choice of rewards could never be
--   handed in: complete_quest() is refused while a choice is pending, and the
--   follow-up passed index 0, which is the "no choice" sentinel.
--
-- GREY QUESTS ARE SKIPPED, NOT DECLINED (1.6.0)
--   A gossip row carries is_trivial, which is the client's own answer to "is
--   this grey for me". When it is, the quest goes into the same skip bag the
--   GUI's manual skip uses and the engine moves on to the next one. It is not
--   declined: decline_quest dismisses the offer for this frame only, so the
--   bot would walk back and be offered the same quest on the next pass.
--
-- GOSSIP quest_id IS NOT A QUEST ID ON TBC (1.5.2)
--   On Classic Era and TBC Classic the legacy client sends no quest id with a
--   gossip list, so get_gossip_*_quests fills quest_id with the 1-BASED ROW
--   INDEX instead. It looks like an id and it round-trips back to the matching
--   selector, which is exactly what makes it dangerous: comparing it against a
--   real quest id never matches, and passing a real quest id to the selector
--   addresses a row that does not exist.
--
--   Both mistakes were here. The gossip path therefore never selected anything
--   on TBC - it only ever worked when the quest detail frame happened to be up
--   already. Quests are now matched on TITLE, and the opaque value from the
--   same frame is handed straight back to the selector, which is correct on
--   every version. Only the QUEST LOG carries a real quest id, so is_on_quest,
--   is_quest_flagged_completed and get_quest_log_title keep using ids.
--
-- INTERACTING IS NOT FREE (1.5.1)
--   go_and_interact re-issued interact_with_object every 1.2s for as long as
--   the bot stood at the NPC, and the dialog steps only ran on the tick that
--   fired. Re-interacting TEARS DOWN the open frame and opens a fresh one, so
--   the reward frame never lived long enough for get_quest_item_link to see a
--   choice - the hand-in fell through to complete_quest every time and a quest
--   with a reward choice could never finish. Walking to the NPC (npc.at_npc)
--   and driving the dialog (npc.accept / npc.turn_in) are now separate, and
--   the dialog is a state machine that interacts ONCE and then leaves the
--   frame alone while it reads it.
--
-- ESCORTS NEED A SECOND YES
--   accept_quest() is not enough for an auto-accept / escort quest; the client
--   raises a confirmation popup that confirm_accept_quest() answers.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local gui = require("gui")
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

-- Walk an indexed NPC-frame list until the titles run out. There is no
-- get_num_* for these, and an index past the end returns an empty string.
local MAX_FRAME_QUESTS = 32

local function frame_titles(getter)
    local out = {}
    for i = 1, MAX_FRAME_QUESTS do
        local title = safe(function() return getter(i) end)
        if type(title) ~= "string" or title == "" then
            break
        end
        out[i] = title
    end
    return out
end

--- Index of `want` in `titles`, or nil.
---
--- Quest names in the data files are English and the client may not be, so an
--- exact match is tried first, then a case-insensitive one. A single-entry list
--- needs no match at all - there is only one thing it can be, which keeps the
--- common case working in every locale.
local function index_of_title(titles, want)
    local n = 0
    for _ in pairs(titles) do n = n + 1 end
    if n == 0 then
        return nil
    end
    if n == 1 then
        return 1
    end
    if type(want) ~= "string" or want == "" then
        return nil
    end
    for i, t in pairs(titles) do
        if t == want then return i end
    end
    local lower = want:lower()
    for i, t in pairs(titles) do
        if t:lower() == lower then return i end
    end
    return nil
end

local warned_frame = {}
local function warn_once(key, fmt, ...)
    if warned_frame[key] then return end
    warned_frame[key] = true
    core.log_warning(string.format("[Master Farmer - Grindbot] " .. fmt, ...))
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

--- Walk to `npc_id`. Returns true once the bot is standing at it - every tick,
--- and WITHOUT interacting. The dialog state machines below decide when to
--- interact, because re-interacting closes whatever frame they are reading.
function npc.at_npc(player, npc_id, dest)
    local unit = targeting.find_npc(player, npc_id, 80)
    if unit then
        local d = safe(function() return player:distance_to(unit) end) or 99
        if d > 4 then
            local p = safe(function() return unit:get_position() end) or dest
            movement.nav_to(p)
            return false
        end
        movement.nav_stop()
        return true
    end
    if dest then
        if not movement.arrived(dest, 4) then
            movement.nav_to(dest)
        end
    end
    return false
end

--- Open the NPC's dialog. Called once per state-machine attempt, never on a
--- timer: every call replaces the frame that is currently open.
local function interact_once(player, npc_id)
    local unit = targeting.find_npc(player, npc_id, 10)
    if not unit then
        return false
    end
    state.quest.interact_until = izi.now() + 1.2
    pcall(function()
        core.input.interact_with_object(unit)
    end)
    return true
end

-- ----------------------------------------------------------------------------
-- DIALOG STATE MACHINE
-- ----------------------------------------------------------------------------
-- Each step gets its own tick. The client needs a frame or two to open a
-- window, and every step here reads a window the previous step opened.
local STEP_GAP    = 0.5   -- seconds between steps
local FRAME_WAIT  = 2.0   -- how long to let the reward frame appear
local RETRY_GAP   = 8.0   -- restart a stalled dialog after this
local MAX_TRIES   = 3

local dlg = { key = nil, stage = nil, t = -1e9, tries = 0, picked = nil }

local function dlg_reset(key)
    dlg.key, dlg.stage, dlg.t, dlg.tries, dlg.picked = key, "interact", -1e9, 0, nil
end

local function dlg_to(stage, now)
    dlg.stage, dlg.t = stage, now
end

local function quest_debug(fmt, ...)
    if gui.is_on("quest_debug") ~= true then
        return
    end
    core.log("[Master Farmer - Grindbot] quest: " .. string.format(fmt, ...))
end

--- Find a quest in a gossip list.
---
--- Title first, because on TBC the quest_id field is only a row index and can
--- never equal a real quest id. The id comparison is kept for retail, where it
--- is a real id and is the more reliable of the two.
local function gossip_row(list, quest_id, quest_name)
    if type(quest_name) == "string" and quest_name ~= "" then
        for i = 1, #list do
            if list[i].title == quest_name then
                return list[i]
            end
        end
        local lower = quest_name:lower()
        for i = 1, #list do
            if type(list[i].title) == "string" and list[i].title:lower() == lower then
                return list[i]
            end
        end
    end
    -- Retail: quest_id really is the quest id.
    for i = 1, #list do
        if list[i].quest_id == quest_id then
            return list[i]
        end
    end
    -- One quest and nothing matched: it can only be this one.
    if #list == 1 then
        return list[1]
    end
    return nil
end

--- Is this quest grey for us?
---
--- is_trivial is the client's own verdict but only appears on a gossip row, so
--- a greeting-frame NPC falls back to the quest level that frame reports. The
--- gap is deliberately conservative: TBC greys a quest around five levels below
--- the character, and skipping one that still pays is worse than running one
--- that does not.
local TRIVIAL_GAP = 5

local function is_trivial_quest(player, quest_id, quest_name)
    if gui.is_on("skip_trivial") ~= true then
        return false
    end

    if gossip_open() then
        local list = safe(function() return core.quests.get_gossip_available_quests() end)
        if type(list) == "table" and #list > 0 then
            local row = gossip_row(list, quest_id, quest_name)
            if row then
                return row.is_trivial == true
            end
        end
        return false
    end

    -- Greeting frame: no is_trivial, but it does report the quest level.
    local titles = frame_titles(function(i) return core.quests.get_available_title(i) end)
    local idx = index_of_title(titles, quest_name)
    if not idx then
        return false
    end
    local qlevel = safe(function() return core.quests.get_available_level(idx) end)
    local plevel = safe(function() return player:get_level() end)
    if type(qlevel) ~= "number" or type(plevel) ~= "number" or qlevel <= 0 then
        return false
    end
    return (plevel - qlevel) >= TRIVIAL_GAP
end

--- Put the quest in the same bag the GUI's manual skip uses, so `pick` in
--- quest/engine.lua moves on to the next one.
local function mark_skipped(quest_id, quest_name)
    if type(state.quest.skipped) ~= "table" then
        state.quest.skipped = {}
    end
    state.quest.skipped[quest_id] = true
    core.log(string.format(
        "[Master Farmer - Grindbot] Skipping grey quest %s.", tostring(quest_name or quest_id)))
end

--- Select `quest_id` at the NPC, whichever frame it is showing.
local function select_quest(quest_id, quest_name, kind)
    local gossip_list, gossip_pick, frame_title, frame_pick
    if kind == "available" then
        gossip_list = function() return core.quests.get_gossip_available_quests() end
        gossip_pick = function(id) core.quests.select_gossip_available_quest(id) end
        frame_title = function(i) return core.quests.get_available_title(i) end
        frame_pick  = function(i) core.quests.select_available_quest(i) end
    else
        gossip_list = function() return core.quests.get_gossip_active_quests() end
        gossip_pick = function(id) core.quests.select_gossip_active_quest(id) end
        frame_title = function(i) return core.quests.get_active_title(i) end
        frame_pick  = function(i) core.quests.select_active_quest(i) end
    end

    if gossip_open() then
        local list = safe(gossip_list)
        if type(list) == "table" and #list > 0 then
            local row = gossip_row(list, quest_id, quest_name)
            if row then
                -- `row.quest_id` is opaque: a real id on retail, the row index
                -- on TBC. It is only valid in this frame, so it goes straight
                -- back to the selector and is never stored or compared.
                local handle = row.quest_id
                pcall(function() gossip_pick(handle) end)
                quest_debug("selected %s quest '%s' in the gossip frame (handle %s)",
                    kind, tostring(row.title), tostring(handle))
                return true
            end
            -- A list came back and this quest is not in it. Selecting a row at
            -- random would pick up the wrong quest, so do nothing.
            quest_debug("%s quest '%s' is not in this NPC's gossip list of %d",
                kind, tostring(quest_name or quest_id), #list)
            return false
        end
        -- Frame open but no list: a single-quest NPC goes straight to detail.
        return true
    end

    local titles = frame_titles(frame_title)
    local idx = index_of_title(titles, quest_name)
    if idx then
        pcall(function() frame_pick(idx) end)
        quest_debug("selected %s quest at greeting-frame index %d (%s)", kind, idx, tostring(titles[idx]))
        return true
    end
    if next(titles) ~= nil then
        warn_once(kind .. ":" .. tostring(quest_id),
            "Quest %s is not among the quests this NPC lists by that name - "
            .. "the quest data name may not match the client's locale.",
            tostring(quest_name or quest_id))
        return false
    end
    -- No list at all: the quest detail frame is already up.
    return true
end

-- ----------------------------------------------------------------------------
-- REWARD CHOICE
-- ----------------------------------------------------------------------------
local MAX_REWARD_CHOICES = 10

--- The reward choices currently on offer, as { index, link } pairs.
--- An index past the last choice returns "", which ends the list.
local function reward_choices()
    local out = {}
    for i = 1, MAX_REWARD_CHOICES do
        local link = safe(function() return core.quests.get_quest_item_link("choice", i) end)
        if type(link) ~= "string" or link == "" then
            break
        end
        out[#out + 1] = { index = i, link = link }
    end
    return out
end

--- Best choice index for this character, or nil when nothing is on offer.
---
--- Ranked by equip.rate: a usable upgrade beats a usable item, which beats
--- something not equippable at all, which beats an item this class cannot use.
--- Vendor price only breaks ties. Picking blind - which is what index 0 did -
--- routinely took a plate chest on a Mage.
local function best_choice(player)
    local choices = reward_choices()
    if #choices == 0 then
        return nil, 0
    end

    local ok_equip, equip = pcall(require, "equip")
    local best_idx, best_rating, best_name = nil, nil, nil

    for i = 1, #choices do
        local c = choices[i]
        local rating, name
        if ok_equip and equip and type(equip.info_of) == "function" then
            local info = equip.info_of(c.link)
            if info then
                rating = equip.rate(player, info)
                name = info.name or c.link
            end
        end
        if rating then
            quest_debug("  choice %d: %s - tier %d (%s) ilvl %d q%d %dc",
                c.index, tostring(name), rating.tier, tostring(rating.reason),
                rating.item_level, rating.quality, rating.sell_price)
            if equip.rating_beats(rating, best_rating) then
                best_idx, best_rating, best_name = c.index, rating, name
            end
        elseif best_idx == nil then
            -- No item info on this build: take the first rather than none.
            best_idx, best_name = c.index, c.link
        end
    end

    if best_idx then
        quest_debug("taking choice %d (%s)", best_idx, tostring(best_name))
    end
    return best_idx, #choices
end

-- ----------------------------------------------------------------------------
-- ACCEPT
-- ----------------------------------------------------------------------------
--- Accept `quest_id`. Call every tick while standing at the NPC.
function npc.accept(player, quest_id, quest_name, npc_id)
    local key = "accept:" .. tostring(quest_id)
    if dlg.key ~= key then
        dlg_reset(key)
    end
    local now = izi.now()
    if (now - dlg.t) < STEP_GAP then
        return
    end

    if dlg.stage == "interact" then
        if dlg.tries >= MAX_TRIES then
            return
        end
        dlg.tries = dlg.tries + 1
        interact_once(player, npc_id)
        quest_debug("accept %s: opened the dialog (try %d)", tostring(quest_name or quest_id), dlg.tries)
        dlg_to("select", now)
        return
    end

    if dlg.stage == "select" then
        if is_trivial_quest(player, quest_id, quest_name) then
            mark_skipped(quest_id, quest_name)
            dlg.stage = "done"
            return
        end
        select_quest(quest_id, quest_name, "available")
        dlg_to("accept", now)
        return
    end

    if dlg.stage == "accept" then
        pcall(function() core.quests.accept_quest() end)
        -- Escort and other auto-accept quests raise a second confirmation
        -- popup; without this they sit on screen and never start.
        pcall(function() core.quests.confirm_accept_quest() end)
        quest_debug("accept %s: accepted", tostring(quest_name or quest_id))
        dlg_to("verify", now)
        return
    end

    if dlg.stage == "verify" then
        if safe(function() return core.quests.is_on_quest(quest_id) end) == true then
            dlg.stage = "done"
            return
        end
        if (now - dlg.t) >= RETRY_GAP then
            quest_debug("accept %s: still not on the quest, retrying", tostring(quest_name or quest_id))
            dlg_to("interact", now)
        end
    end
end

-- ----------------------------------------------------------------------------
-- TURN IN
-- ----------------------------------------------------------------------------
--- Hand in `quest_id`. Call every tick while standing at the NPC.
function npc.turn_in(player, quest_id, quest_name, npc_id)
    local key = "turnin:" .. tostring(quest_id)
    if dlg.key ~= key then
        dlg_reset(key)
    end
    local now = izi.now()
    if (now - dlg.t) < STEP_GAP then
        return
    end

    if dlg.stage == "interact" then
        if dlg.tries >= MAX_TRIES then
            warn_once("turnin_giveup:" .. tostring(quest_id),
                "Gave up handing in quest %s after %d attempts.",
                tostring(quest_name or quest_id), MAX_TRIES)
            return
        end
        dlg.tries = dlg.tries + 1
        interact_once(player, npc_id)
        quest_debug("turn in %s: opened the dialog (try %d)", tostring(quest_name or quest_id), dlg.tries)
        dlg_to("select", now)
        return
    end

    if dlg.stage == "select" then
        select_quest(quest_id, quest_name, "active")
        dlg_to("wait", now)
        return
    end

    -- Wait for the reward frame. This is the step that never used to happen:
    -- the choices were read in the same tick as the selection, before the
    -- frame existed, so every quest looked as though it had no choice.
    if dlg.stage == "wait" then
        local idx, count = best_choice(player)
        if idx then
            dlg.picked = idx
            dlg_to("reward", now)
            return
        end
        if count > 0 then
            return  -- choices are there but not rated yet; look again next tick
        end
        if (now - dlg.t) >= FRAME_WAIT then
            quest_debug("turn in %s: no reward choice offered, completing", tostring(quest_name or quest_id))
            pcall(function() core.quests.complete_quest() end)
            dlg_to("verify", now)
        end
        return
    end

    if dlg.stage == "reward" then
        local idx = dlg.picked
        -- get_quest_reward SELECTS the choice and completes the quest.
        -- complete_quest is not called as well: they are alternatives.
        pcall(function() core.quests.get_quest_reward(idx) end)
        quest_debug("turn in %s: took reward choice %d", tostring(quest_name or quest_id), idx or -1)
        dlg_to("verify", now)
        return
    end

    if dlg.stage == "verify" then
        if safe(function() return core.quests.is_on_quest(quest_id) end) ~= true then
            dlg.stage = "done"
            quest_debug("turn in %s: complete", tostring(quest_name or quest_id))
            return
        end
        if (now - dlg.t) >= RETRY_GAP then
            quest_debug("turn in %s: still in the log, retrying", tostring(quest_name or quest_id))
            dlg_to("interact", now)
        end
    end
end

function npc.close()
    dlg.key, dlg.stage = nil, nil
    pcall(function()
        core.quests.close_quest()
    end)
    gossip_close()
end

--- Is `quest_id` ready to hand in?
--- `quest_name` is only needed for the gossip fallback, where TBC exposes no
--- real quest id (see the header).
function npc.is_complete(quest_id, quest_name)
    pcall(function()
        core.quests.expand_quest_header(0)
    end)
    local n = safe(function() return core.quests.get_num_quest_log_entries() end) or 0
    for i = 1, n do
        local entry = safe(function() return core.quests.get_quest_log_title(i) end)
        if type(entry) == "table" and entry.quest_id == quest_id then
            -- Builds disagree on this field: the reference declares it as an
            -- integer (1 complete, -1 failed) and the documentation as a
            -- boolean. Accept either rather than pick a side.
            if entry.is_complete == true or entry.is_complete == 1 then
                return true
            end
            if entry.is_complete == -1 then
                return false  -- failed, not completable
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
    -- Not in the log we could read. The NPC's own active list knows whether it
    -- will take the quest back right now - matched on title, because the
    -- quest_id in a gossip row is a row index on TBC.
    local gossip = safe(function() return core.quests.get_gossip_active_quests() end)
    if type(gossip) == "table" and #gossip > 0 then
        local row = gossip_row(gossip, quest_id, quest_name)
        if row and row.is_complete == true then
            return true
        end
    end
    return false
end

return npc

-- ============================================================================
-- Master Farmer - Grindbot
-- Class trainer - buy trainable spell ranks
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- IT DOES NOT TRAVEL, AND THAT IS DELIBERATE
--   There is no trainer location data in this project. The zone tables carry a
--   `merchant` record (name plus coordinates) and nothing else, and inventing
--   class-trainer coordinates for every race, zone and class would be guessing
--   at data the bot would then walk into a lake to reach.
--
--   So this trains OPPORTUNISTICALLY: whenever a gossip frame is open in front
--   of the bot for any reason - a quest giver, the zone merchant, anything -
--   and that NPC offers a trainer option, it trains before anything else gets
--   to use the frame. It never opens a dialog of its own and never changes
--   where the bot walks.
--
--   To make it travel, add `trainer = { name = ..., x/y/z }` beside `merchant`
--   in grind/zones/*.lua and the vendor trip pattern can be reused directly.
--
-- WHAT IT BUYS
--   Class spell ranks only: services whose talent_cost and profession_cost are
--   both zero. Talent and profession purchases are irreversible choices that
--   belong to the player, not to a bot.
--
--   Cheapest first, so a level's worth of gold buys the most ranks, and never
--   below the gold reserve so a trip does not leave the character unable to
--   repair or restock.
--
-- WHY IT LATCHES
--   Reading the service list is cheap but selecting the trainer gossip option
--   is not: it replaces whatever frame is open. Once a trainer has been worked
--   through, it is not touched again until the character levels or gets
--   meaningfully richer - the only two things that can produce new affordable
--   ranks.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local gui = require("gui")
local state = require("state")

local trainer = {}

local ACT_GAP = 0.6          -- seconds between purchases
local GOLD_STEP = 10000      -- 1g more than last time counts as "richer"
local MAX_SERVICES = 200     -- sanity bound on the service list

local last_act = -1e9
local tried_level = nil
local tried_gold = nil

-- Spells bought while this trainer window has been open.
--
-- A learned spell normally leaves the service list, but nothing here can rely
-- on that: if the list lags a frame, or buy_trainer_service quietly fails, the
-- cheapest entry stays cheapest and the bot buys it again every tick until the
-- purse is empty. Keyed on the spell name rather than the index, because
-- indices shift as entries are removed.
local bought = {}

local function forget_bought()
    bought = {}
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function gold()
    local c = safe(function() return core.inventory.get_gold() end)
    if type(c) == "number" then
        return c
    end
    return 0
end

local function reserve()
    local g = gui.slider("train_reserve", 0)
    if type(g) ~= "number" or g ~= g or g < 0 then
        g = 0
    end
    return g * 10000    -- the slider is in gold, everything else is copper
end

-- ----------------------------------------------------------------------------
-- LATCH
-- ----------------------------------------------------------------------------
--- Have we already worked this trainer over at this level and this much gold?
local function already_tried(player)
    local level = safe(function() return player:get_level() end) or 0
    if tried_level ~= level then
        return false
    end
    if type(tried_gold) == "number" and (gold() - tried_gold) >= GOLD_STEP then
        return false
    end
    return true
end

local function mark_tried(player)
    tried_level = safe(function() return player:get_level() end) or 0
    tried_gold = gold()
end

--- Let the next level or a decent purse re-open the question.
function trainer.reset()
    tried_level, tried_gold = nil, nil
    forget_bought()
end

-- ----------------------------------------------------------------------------
-- SERVICES
-- ----------------------------------------------------------------------------
local function service_count()
    local n = safe(function() return core.quests.get_num_trainer_services() end)
    if type(n) ~= "number" or n < 0 then
        return 0
    end
    if n > MAX_SERVICES then
        return MAX_SERVICES
    end
    return n
end

--- The cheapest service this character may buy right now, or nil.
---
--- Returns (index, name, cost). Only class spells are considered: a service
--- carrying a talent or profession cost is a player decision, not a bot one.
local function cheapest_affordable()
    local budget = gold() - reserve()
    if budget <= 0 then
        return nil
    end

    local best_idx, best_cost, best_name = nil, nil, nil
    for i = 1, service_count() do
        local cost = safe(function() return core.quests.get_trainer_service_cost(i) end)
        if type(cost) == "table" then
            local service = cost.service_cost
            local talent = cost.talent_cost or 0
            local profession = cost.profession_cost or 0
            if type(service) == "number" and service > 0
                and talent == 0 and profession == 0
                and service <= budget
                and (best_cost == nil or service < best_cost) then
                local info = safe(function() return core.quests.get_trainer_service_info(i) end)
                local name = (type(info) == "table" and info.spell_name) or nil
                -- A row with no spell name is a category header, not a spell.
                if type(name) == "string" and name ~= "" then
                    if type(info.rank) == "string" and info.rank ~= "" then
                        name = name .. " (" .. info.rank .. ")"
                    end
                    if not bought[name] then
                        best_idx, best_cost, best_name = i, service, name
                    end
                end
            end
        end
    end
    return best_idx, best_name, best_cost
end

-- ----------------------------------------------------------------------------
-- GOSSIP
-- ----------------------------------------------------------------------------
local function gossip_open()
    return safe(function() return core.quests.is_gossip_frame_shown() end) == true
end

--- The trainer option in the open gossip frame, or nil.
---
--- Matched on gossip_type, never on list position: the documentation is
--- explicit that the order is not stable. The id is opaque and is handed
--- straight back to the selector in the same frame.
local function trainer_option()
    local options = safe(function() return core.quests.get_gossip_options() end)
    if type(options) ~= "table" then
        return nil
    end
    for i = 1, #options do
        local opt = options[i]
        if type(opt) == "table" and type(opt.gossip_type) == "string"
            and string.lower(opt.gossip_type) == "trainer" then
            local id = opt.gossip_option_id
            if type(id) ~= "number" or id == 0 then
                id = i
            end
            return id
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- TICK
-- ----------------------------------------------------------------------------
--- Returns true when it acted, so the caller holds the rest of the cascade.
function trainer.tick(player)
    if not player or gui.is_on("train") ~= true then
        return false
    end

    local now = izi.now()
    if (now - last_act) < ACT_GAP then
        -- Still true while a trainer window is open, so nothing else grabs it.
        return service_count() > 0
    end

    -- 1. A trainer window is open: spend.
    if service_count() > 0 then
        local idx, name, cost = cheapest_affordable()
        if idx then
            last_act = now
            state.set_note("Trainer", string.format("Training %s", tostring(name)))
            core.log(string.format(
                "[Master Farmer - Grindbot] Training %s for %d.%02dg",
                tostring(name), math.floor(cost / 10000), math.floor((cost % 10000) / 100)))
            bought[name] = true
            pcall(function() core.quests.buy_trainer_service(idx) end)
            return true
        end

        -- Nothing left we can afford. Close up and leave it alone until the
        -- character levels or gets richer.
        mark_tried(player)
        forget_bought()
        last_act = now
        pcall(function() core.quests.close_gossip() end)
        return false
    end

    -- 2. A gossip frame is open in front of us. If this NPC trains, open it.
    if not gossip_open() then
        return false
    end
    if already_tried(player) then
        return false
    end
    local option = trainer_option()
    if not option then
        return false
    end

    last_act = now
    forget_bought()
    state.set_note("Trainer", "Opening trainer")
    pcall(function() core.quests.select_gossip_option(option) end)
    return true
end

function trainer.register_gui(menu)
    menu:checkbox("mfg_train", false, {
        label = "Train Spells",
        tab = "settings",
        tooltip = "When a gossip frame is open at an NPC that trains this class, "
            .. "buy every spell rank the character can afford, cheapest first. "
            .. "Class spells only - talents and professions are never bought. "
            .. "It does not walk to a trainer: there is no trainer location data, "
            .. "so it trains at trainers the bot already happens to be talking to.",
    })
    menu:slider_int("mfg_train_reserve", 0, 100, 0, {
        label = "Keep Gold Reserve",
        tab = "settings",
        tooltip = "Gold to leave unspent, so training cannot empty the purse "
            .. "and strand the character without repair or vendor money.",
    })
end

return trainer

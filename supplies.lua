-- ============================================================================
-- Master Farmer - Grindbot
-- supplies.lua - restock food and drink at the merchant
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Ported from the reference bot's Buy_Food_Drinks.
--
-- This was reported as unimplementable in v1.4.3. That was wrong: the search
-- covered only the calls this project already made, not the runtime. The
-- reflected API reference confirms all three needed calls exist -
--   core.game_ui.get_vendor_item_count()
--   core.game_ui.get_vendor_item_info(index)
--   core.input.buy_item(index, quantity)
--
-- WHAT THE SOURCE GETS WRONG, AND WHAT IS DONE INSTEAD
--
--   1. The source compares GetMerchantItemInfo's first return against an item
--      NAME from GetItemInfo. Names are localised, so on any non-English
--      client nothing ever matches and the bot silently buys nothing. Here the
--      match is on item id, which is locale-proof - the same reason
--      rotations/*.lua key spells by id.
--
--   2. The source picks the highest-level food it can use, then buys 5 of it
--      with one BuyMerchantItem call. A vendor stack is usually 1, so "5" is
--      five stacks only if the vendor sells them that way - it does not check.
--      Here the wanted count is tracked against what is actually in the bags
--      and the purchase repeats across ticks until the target is met.
--
--   3. The source sets Lack_Money on ANY failure, including "vendor does not
--      stock this", and then gives up on food entirely. Gold and stock are
--      separated here so an unstocked vendor does not look like poverty.
--
-- ONE THING STILL UNVERIFIED
--   get_vendor_item_info's return shape is not reflected - the dump states
--   "Return types are never reflected". field_of() therefore probes the
--   plausible key names and vendor_debug prints the real table once. Until
--   that is confirmed on a live merchant, treat buying as best-effort: it
--   fails closed (buys nothing) rather than buying the wrong thing.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local consumables = require("data/consumables")
local gui = require("gui")
local state = require("state")

local supplies = {}

local BUY_GAP = 0.8          -- seconds between buy_item calls
local MAX_PER_TRIP = 40      -- hard stop so a bad probe cannot drain the purse

local last_buy = -1e9
local bought_this_trip = 0
local debug_done = false

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- VENDOR ITEM INFO
-- ----------------------------------------------------------------------------
--- Read a field from a vendor entry under any of its plausible names.
--- The return shape is not reflected in the API dump, so guessing a single
--- name would read nil and silently match nothing.
local function field_of(entry, names)
    if type(entry) ~= "table" then
        return nil
    end
    for i = 1, #names do
        local v = entry[names[i]]
        if v ~= nil then
            return v
        end
    end
    return nil
end

local ID_KEYS    = { "item_id", "id", "itemId", "item" }
local PRICE_KEYS = { "price", "cost", "money", "buy_price", "item_price" }
local STACK_KEYS = { "stack_count", "stack", "quantity", "count", "item_stack" }

local function vendor_entry(index)
    return safe(function() return core.game_ui.get_vendor_item_info(index) end)
end

local function vendor_count()
    local n = safe(function() return core.game_ui.get_vendor_item_count() end)
    if type(n) == "number" and n > 0 then
        return n
    end
    return 0
end

-- ----------------------------------------------------------------------------
-- DIAGNOSTIC
-- ----------------------------------------------------------------------------
local function debug_dump(entry, index)
    if debug_done or not gui.is_on("vendor_debug") then
        return
    end
    debug_done = true
    core.log("[Master Farmer - Grindbot] get_vendor_item_info(" .. tostring(index) .. ") fields:")
    if type(entry) ~= "table" then
        core.log("    returned a " .. type(entry) .. ", not a table - buying cannot work on this build")
        return
    end
    local keys = {}
    for k in pairs(entry) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for i = 1, #keys do
        local v = entry[keys[i]]
        local ty = type(v)
        if ty == "string" or ty == "number" or ty == "boolean" then
            core.log(string.format("    %-16s %s = %s", keys[i], ty, tostring(v)))
        else
            core.log(string.format("    %-16s %s", keys[i], ty))
        end
    end
    core.log("    id field resolved:    " .. tostring(field_of(entry, ID_KEYS)))
    core.log("    price field resolved: " .. tostring(field_of(entry, PRICE_KEYS)))
end

-- ----------------------------------------------------------------------------
-- BAG COUNTS
-- ----------------------------------------------------------------------------
--- How many of any id in `ids` we are carrying.
local function carried(ids)
    local want = {}
    for i = 1, #ids do want[ids[i]] = true end

    local total = 0
    for bag = 0, 4 do
        local items = safe(function() return core.inventory.get_items_in_bag(bag) end)
        if type(items) == "table" then
            for i = 1, #items do
                local entry = items[i]
                if type(entry) == "table" and entry.object then
                    local id = safe(function() return entry.object:get_item_id() end)
                    if id and want[id] then
                        local n = safe(function() return entry.object:get_item_stack_count() end)
                        total = total + ((type(n) == "number" and n > 0) and n or 1)
                    end
                end
            end
        end
    end
    return total
end

-- ----------------------------------------------------------------------------
-- SELECTION
-- ----------------------------------------------------------------------------
--- Best vendor index stocking anything in `ids`, preferring the entry earliest
--- in the ranked list (data/consumables.lua is ordered best-first, so the first
--- match is the best item the vendor actually stocks).
local function find_on_vendor(ids)
    local rank = {}
    for i = 1, #ids do
        if rank[ids[i]] == nil then rank[ids[i]] = i end
    end

    local n = vendor_count()
    local best_index, best_rank, best_price = nil, nil, nil
    for index = 1, n do
        local entry = vendor_entry(index)
        debug_dump(entry, index)
        local id = field_of(entry, ID_KEYS)
        if type(id) == "number" and rank[id] then
            local r = rank[id]
            if not best_rank or r < best_rank then
                best_index, best_rank = index, r
                best_price = field_of(entry, PRICE_KEYS)
            end
        end
    end
    return best_index, best_price
end

-- ----------------------------------------------------------------------------
-- BUY
-- ----------------------------------------------------------------------------
--- Buy one lot of `ids` if we are short.
--- Returns acted, failure - where failure is nil, "stock" or "gold".
--- The caller needs the distinction: running out of gold is terminal for the
--- whole trip, while an unstocked item only rules out that one line.
local function restock(ids, target, reason)
    if type(ids) ~= "table" or #ids == 0 or target <= 0 then
        return false
    end

    local have = carried(ids)
    if have >= target then
        return false
    end

    local index, price = find_on_vendor(ids)
    if not index then
        state.set_note("Vendor", "No " .. reason .. " stocked here")
        return false, "stock"
    end

    -- Gold and stock are separate failures. Reporting "out of money" for an
    -- unstocked vendor, as the source does, sends the operator hunting the
    -- wrong problem.
    if type(price) == "number" and price > 0 then
        local gold = safe(function() return core.inventory.get_gold() end)
        if type(gold) == "number" and gold < price then
            state.set_note("Vendor", "Not enough gold for " .. reason)
            return false, "gold"
        end
    end

    bought_this_trip = bought_this_trip + 1
    last_buy = izi.now()
    state.set_note("Vendor", string.format("Buying %s (%d/%d)", reason, have, target))
    pcall(function() core.input.buy_item(index, 1) end)
    return true
end

-- ----------------------------------------------------------------------------
-- PUBLIC
-- ----------------------------------------------------------------------------
--- Call while the merchant window is open, from vendor.lua's trip.
--- Returns true when it acted this tick (the caller should hold the cascade).
function supplies.tick(player)
    if not player or not gui.is_on("buy_supplies") then
        return false
    end
    if bought_this_trip >= MAX_PER_TRIP then
        return false
    end
    if (izi.now() - last_buy) < BUY_GAP then
        return true
    end

    local food_target = gui.slider("food_target", 20) or 20
    local acted, failure = restock(consumables.FOOD_ITEM_IDS, food_target, "food")
    if acted then
        return true
    end
    -- Out of gold is terminal: trying drink next would only overwrite the note
    -- with a stock message and hide the real reason from the operator.
    if failure == "gold" then
        return false
    end

    -- Warriors and Rogues have no mana, so drink is dead weight for them.
    local class_id = safe(function() return player:get_class() end)
    local no_mana = (class_id == 1) or (class_id == 4)   -- WARRIOR, ROGUE
    if not no_mana then
        local drink_target = gui.slider("drink_target", 20) or 20
        if restock(consumables.WATER_ITEM_IDS, drink_target, "drink") then
            return true
        end
    end

    return false
end

--- Reset the per-trip cap. vendor.lua calls this when a trip starts or ends.
function supplies.reset()
    bought_this_trip = 0
    last_buy = -1e9
end

function supplies.register_gui(menu)
    menu:checkbox("mfg_buy_supplies", false, {
        label = "Buy Food / Drink",
        tab = "vendor",
        tooltip = "Restock food and water during a vendor trip, up to the counts below.",
    })
    menu:slider_int("mfg_food_target", 0, 60, 20, {
        label = "Keep Food",
        tab = "vendor",
    })
    menu:slider_int("mfg_drink_target", 0, 60, 20, {
        label = "Keep Drink",
        tab = "vendor",
        tooltip = "Ignored for Warriors and Rogues.",
    })
    menu:checkbox("mfg_vendor_debug", false, {
        label = "Log vendor item fields",
        tab = "vendor",
        tooltip = "Prints once what get_vendor_item_info actually returns. Run this at a "
            .. "merchant before trusting automatic buying.",
    })
end

return supplies

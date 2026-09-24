-- ============================================================================
-- Master Farmer - Grindbot
-- Vendor sell + repair (Grind_Information merchants)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- Sell via core.input.use_container_item while a merchant is open.
-- Quality from core.quests.get_item_info. No is_vendor invent.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type inventory_helper
local inventory_helper = require("common/utility/inventory_helper")

---@type vec3
local vec3 = require("common/geometry/vector_3")

local consumables = require("data/consumables")
local gui = require("gui")
local state = require("state")
local targeting = require("targeting")
local movement = require("movement")
local rotation = require("rotation")

local vendor = {}

-- ASSUMPTIONS:
-- core.quests.get_item_info().class_id carries Blizzard's item class ID, where 0
-- is Consumable. The stub documents the field but not its values, so the English
-- item_type string is checked as a fallback before anything is sold.
local ITEM_CLASS_CONSUMABLE = 0

local HEARTHSTONE = 6948
local SELL_GAP = 0.40
local INTERACT_GAP = 1.20
local DONE_COOLDOWN = 90.0
local ARRIVE = 5.0
local FIND_RANGE = 12.0
local REPAIR_GAP = 0.60
local REPAIR_PASSES = 2
local BUY_QTY = 5
local MAX_BUYS = 12
local COUNT_GAP = 1.0
local NO_STOCK_COOLDOWN = 300.0

local function id_set(list)
    local set = {}
    if type(list) ~= "table" then
        return set
    end
    for i = 1, #list do
        if type(list[i]) == "number" then
            set[list[i]] = true
        end
    end
    return set
end

local FOOD_SET = id_set(consumables.FOOD_ITEM_IDS)
local DRINK_SET = id_set(consumables.WATER_ITEM_IDS)

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function merchant_pos(info)
    if type(info) ~= "table" then
        return nil
    end
    if type(info.x) ~= "number" or type(info.y) ~= "number" or type(info.z) ~= "number" then
        return nil
    end
    return vec3.new(info.x, info.y, info.z)
end

local function current_merchant(player)
    local okz, grind_zones = pcall(require, "grind/zone_lookup")
    if not okz or type(grind_zones) ~= "table" or type(grind_zones.lookup) ~= "function" then
        return nil
    end
    local race_id = safe(function() return player:get_race_id() end)
    local level = safe(function() return player:get_level() end) or 1
    local zone = grind_zones.lookup(race_id, level)
    if type(zone) ~= "table" then
        return nil
    end
    local info = zone.merchant
    if type(info) ~= "table" then
        return nil
    end
    return info
end

local function backpack_free()
    local slots = safe(function() return core.inventory.get_num_bag_slots(0) end) or 16
    if type(slots) ~= "number" or slots < 1 then
        slots = 16
    end
    local items = safe(function() return core.inventory.get_items_in_bag(0) end)
    local used = 0
    if type(items) == "table" then
        used = #items
    end
    local left = slots - used
    if left < 0 then
        return 0
    end
    return left
end

local function bag_free()
    local helper_free = safe(function()
        return inventory_helper:get_total_free_slots()
    end)
    if type(helper_free) == "number" and helper_free >= 0 then
        return helper_free + backpack_free()
    end
    local free = backpack_free()
    for bag = 1, 4 do
        local slots = safe(function() return core.inventory.get_num_bag_slots(bag) end) or 0
        if type(slots) == "number" and slots > 0 then
            local items = safe(function() return core.inventory.get_items_in_bag(bag) end)
            local used = 0
            if type(items) == "table" then
                used = #items
            end
            local left = slots - used
            if left > 0 then
                free = free + left
            end
        end
    end
    return free
end

local function worst_durability()
    local worst = 1
    local broken = false
    for slot = 1, 19 do
        local d = safe(function() return core.inventory.get_item_durability(slot) end)
        if type(d) == "table" then
            local maxd = d.max
            local cur = d.current
            if type(maxd) == "number" and maxd > 0 and type(cur) == "number" then
                local ratio = cur / maxd
                if ratio < worst then
                    worst = ratio
                end
                if cur <= 0 then
                    broken = true
                end
            end
        end
    end
    return worst, broken
end

local count_cache = {}

local function bag_total(set)
    local now = izi.now()
    local cached = count_cache[set]
    if cached and (now - cached.at) < COUNT_GAP then
        return cached.value
    end
    local total = 0
    for bag = 0, 4 do
        local items = safe(function() return core.inventory.get_items_in_bag(bag) end)
        if type(items) == "table" then
            for i = 1, #items do
                local slot = items[i]
                local obj = type(slot) == "table" and slot.object or nil
                if obj then
                    local id = safe(function() return obj:get_item_id() end)
                    if type(id) == "number" and set[id] then
                        local stack = safe(function() return obj:get_item_stack_count() end)
                        if type(stack) ~= "number" or stack < 1 then
                            stack = 1
                        end
                        total = total + stack
                    end
                end
            end
        end
    end
    count_cache[set] = { at = now, value = total }
    return total
end

local function has_mana(player)
    local maxm = safe(function() return player:mana_max() end)
    return type(maxm) == "number" and maxm > 0
end

local function wants_stock(player)
    if gui.is_on("buy_food") ~= true then
        return false, false
    end
    local need_food = bag_total(FOOD_SET) < gui.slider("food_count", 20)
    local need_drink = false
    if has_mana(player) then
        need_drink = bag_total(DRINK_SET) < gui.slider("drink_count", 20)
    end
    return need_food, need_drink
end

local function merchant_open()
    local count = safe(function() return core.game_ui.get_vendor_item_count() end) or 0
    if type(count) == "number" and count > 0 then
        return true
    end
    return safe(function() return core.inventory.can_merchant_repair() end) == true
end

local function keep_ids(player)
    local ids = { [HEARTHSTONE] = true }
    local foods = rotation.preferred_food_ids(player)
    if type(foods) == "table" then
        for i = 1, #foods do
            if type(foods[i]) == "number" then
                ids[foods[i]] = true
            end
        end
    end
    local drinks = rotation.preferred_drink_ids(player)
    if type(drinks) == "table" then
        for i = 1, #drinks do
            if type(drinks[i]) == "number" then
                ids[drinks[i]] = true
            end
        end
    end
    return ids
end

local keep_text = nil
local keep_custom = {}

local function custom_keep_ids()
    local text = safe(function() return gui.keep_items() end)
    if type(text) ~= "string" then
        text = ""
    end
    if text == keep_text then
        return keep_custom
    end
    keep_text = text
    keep_custom = {}
    for token in string.gmatch(text, "[^,%s]+") do
        local id = tonumber(token)
        if type(id) == "number" and id > 0 then
            keep_custom[math.floor(id)] = true
        end
    end
    return keep_custom
end

-- Food, drink, potions, bandages, and elixirs all share the Consumable class, so
-- the whole class is protected instead of matching item ID lists.
local function is_consumable(info)
    if type(info) ~= "table" then
        return false
    end
    if info.class_id == ITEM_CLASS_CONSUMABLE then
        return true
    end
    local kind = info.item_type
    if type(kind) == "string" and string.lower(kind) == "consumable" then
        return true
    end
    return false
end

local function quality_ok(quality)
    if type(quality) ~= "number" then
        return false
    end
    if quality == 0 then
        return gui.is_on("sell_grey")
    end
    if quality == 1 then
        return gui.is_on("sell_white")
    end
    if quality == 2 then
        return gui.is_on("sell_green")
    end
    return false
end

local function should_sell_item(player, item_id)
    if type(item_id) ~= "number" or item_id <= 0 then
        return false
    end
    local keep = keep_ids(player)
    if keep[item_id] then
        return false
    end
    if custom_keep_ids()[item_id] then
        return false
    end
    local info = safe(function() return core.quests.get_item_info(item_id) end)
    if type(info) ~= "table" then
        return false
    end
    if is_consumable(info) then
        return false
    end
    local price = info.sell_price
    if type(price) == "number" and price <= 0 then
        return false
    end
    return quality_ok(info.quality)
end

local function sell_one(player)
    for bag = 0, 4 do
        local items = safe(function() return core.inventory.get_items_in_bag(bag) end)
        if type(items) == "table" then
            for i = 1, #items do
                local slot = items[i]
                if type(slot) == "table" then
                    local obj = slot.object
                    local slot_id = slot.slot_id
                    local item_id = obj and safe(function() return obj:get_item_id() end)
                    if type(slot_id) == "number" and should_sell_item(player, item_id) then
                        pcall(function()
                            core.input.use_container_item(bag, slot_id)
                        end)
                        return true, item_id
                    end
                end
            end
        end
    end
    return false
end

-- Highest required level the player can still use is the best rank the vendor
-- carries, which mirrors picking the top GetItemInfo required level.
local function buy_best(player, set)
    local count = safe(function() return core.game_ui.get_vendor_item_count() end)
    if type(count) ~= "number" or count <= 0 then
        return false
    end
    local level = safe(function() return player:get_level() end) or 1
    local best_index, best_req, best_cost, best_name = nil, -1, 0, nil
    for i = 1, count do
        local info = safe(function() return core.game_ui.get_vendor_item_info(i) end)
        if type(info) == "table" and type(info.item_id) == "number" and set[info.item_id] then
            local item = safe(function() return core.quests.get_item_info(info.item_id) end)
            local req = 0
            if type(item) == "table" and type(item.min_level) == "number" then
                req = item.min_level
            end
            if req <= level and req > best_req then
                best_req = req
                best_index = info.vendor_item_index or i
                best_cost = type(info.cost) == "number" and info.cost or 0
                best_name = info.item_name or tostring(info.item_id)
            end
        end
    end
    if type(best_index) ~= "number" then
        return false
    end
    local total_cost = best_cost * BUY_QTY
    local gold = safe(function() return core.inventory.get_gold() end) or 0
    -- lack_gold stays reserved for repairs, which gate the trip itself.
    if total_cost > 0 and type(gold) == "number" and gold < total_cost then
        state.set_note("Vendor", "Need more gold for " .. tostring(best_name))
        return false
    end
    pcall(function()
        core.input.buy_item(best_index, BUY_QTY)
    end)
    count_cache = {}
    state.set_note("Vendor", "Bought " .. tostring(best_name) .. " x" .. tostring(BUY_QTY))
    return true
end

local function try_buy(player)
    local need_food, need_drink = wants_stock(player)
    if not need_food and not need_drink then
        return false
    end
    if (state.vendor.buys or 0) >= MAX_BUYS or bag_free() <= 0 then
        return false
    end
    local bought = false
    if need_food then
        bought = buy_best(player, FOOD_SET)
    end
    if not bought and need_drink then
        bought = buy_best(player, DRINK_SET)
    end
    if not bought then
        -- This merchant carries nothing usable, so stop coming back for a while.
        state.vendor.no_stock_until = izi.now() + NO_STOCK_COOLDOWN
        return false
    end
    state.vendor.buys = (state.vendor.buys or 0) + 1
    return true
end

local function gossip_open()
    if izi.gossip and type(izi.gossip.is_open) == "function" then
        if safe(function() return izi.gossip.is_open() end) == true then
            return true
        end
    end
    return safe(function() return core.quests.is_gossip_frame_shown() end) == true
end

local function gossip_option_id(opt)
    if type(opt) == "number" and opt ~= 0 then
        return opt
    end
    if type(opt) ~= "table" then
        return nil
    end
    if type(opt.gossip_option_id) == "number" and opt.gossip_option_id ~= 0 then
        return opt.gossip_option_id
    end
    if type(opt.id) == "number" and opt.id ~= 0 then
        return opt.id
    end
    if type(opt.index) == "number" and opt.index ~= 0 then
        return opt.index
    end
    return nil
end

local function select_vendor_gossip()
    if izi.gossip and type(izi.gossip.find_option_by_icon) == "function" then
        local icon = 1
        if type(izi.gossip.ICON) == "table" and type(izi.gossip.ICON.VENDOR) == "number" then
            icon = izi.gossip.ICON.VENDOR
        end
        local opt = safe(function()
            return izi.gossip.find_option_by_icon(icon)
        end)
        local id = nil
        if type(opt) == "table" and type(opt.gossip_option_id) == "number" and opt.gossip_option_id ~= 0 then
            id = opt.gossip_option_id
        end
        if type(id) == "number" then
            pcall(function()
                core.quests.select_gossip_option(id)
            end)
            return true
        end
    end
    local options = safe(function() return core.quests.get_gossip_options() end)
    if type(options) ~= "table" then
        return false
    end
    for i = 1, #options do
        local opt = options[i]
        if type(opt) == "table" then
            local gtype = opt.gossip_type
            if type(gtype) == "string" and string.lower(gtype) == "vendor" then
                local id = gossip_option_id(opt) or i
                pcall(function()
                    core.quests.select_gossip_option(id)
                end)
                return true
            end
        end
    end
    return false
end

local function close_vendor()
    if izi.gossip and type(izi.gossip.close) == "function" then
        pcall(function()
            izi.gossip.close()
        end)
    end
    pcall(function()
        core.quests.close_gossip()
    end)
end

local function finish_trip(note)
    state.vendor.active = false
    state.vendor.repaired = false
    state.vendor.repairs = 0
    state.vendor.buys = 0
    state.vendor.sold = 0
    state.vendor.interact_until = 0
    state.vendor.done_until = izi.now() + DONE_COOLDOWN
    state.vendor.wait_npc = 0
    state.vendor.tries = 0
    movement.stop()
    close_vendor()
    if note then
        state.set_note("Vendor", note)
    end
end

function vendor.reset()
    state.vendor.active = false
    state.vendor.repaired = false
    state.vendor.repairs = 0
    state.vendor.buys = 0
    state.vendor.no_stock_until = 0
    state.vendor.sold = 0
    state.vendor.interact_until = 0
    state.vendor.done_until = 0
    state.vendor.lack_gold = 0
    state.vendor.wait_npc = 0
    state.vendor.tries = 0
end

function vendor.needs_trip(player)
    if not player then
        return false
    end
    if not gui.is_on("sell") and not gui.is_on("repair") and not gui.is_on("buy_food") then
        return false
    end
    if izi.now() < (state.vendor.done_until or 0) and not state.vendor.active then
        return false
    end
    if izi.now() >= (state.vendor.no_stock_until or 0) then
        local need_food, need_drink = wants_stock(player)
        if need_food or need_drink then
            return true
        end
    end
    if gui.is_on("sell") then
        local need_slots = gui.slider("bag_free", 1)
        if bag_free() <= need_slots then
            return true
        end
    end
    if gui.is_on("repair") then
        local lack = state.vendor.lack_gold or 0
        local can_pay = true
        if lack > 0 then
            local gold = safe(function() return core.inventory.get_gold() end) or 0
            if type(gold) == "number" and gold >= lack then
                state.vendor.lack_gold = 0
            else
                can_pay = false
            end
        end
        if can_pay then
            local ratio, broken = worst_durability()
            local pct = gui.slider("repair_pct", 10) / 100
            if broken or ratio <= pct then
                return true
            end
        end
    end
    return false
end

function vendor.tick(player)
    if not player then
        return false
    end
    if not gui.is_on("sell") and not gui.is_on("repair") and not gui.is_on("buy_food") then
        if state.vendor.active then
            vendor.reset()
        end
        return false
    end

    local in_combat = safe(function() return player:is_in_combat() end) == true
    if in_combat and not merchant_open() then
        return false
    end

    if not state.vendor.active then
        if not vendor.needs_trip(player) then
            return false
        end
        local info = current_merchant(player)
        if not info or not merchant_pos(info) then
            state.set_note("Vendor", "No merchant for this zone")
            state.vendor.done_until = izi.now() + 30
            return false
        end
        state.vendor.active = true
        state.vendor.repaired = false
        state.vendor.repairs = 0
        state.vendor.buys = 0
        state.vendor.sold = 0
        state.vendor.wait_npc = 0
        state.vendor.tries = 0
    end

    local info = current_merchant(player)
    local dest = merchant_pos(info)
    if not dest then
        finish_trip("No merchant for this zone")
        return false
    end

    if merchant_open() then
        movement.stop()
        state.vendor.tries = 0
        local now = izi.now()
        if now < (state.vendor.interact_until or 0) then
            state.set_note("Vendor", "Selling")
            return true
        end
        if gui.is_on("sell") then
            local sold, item_id = sell_one(player)
            if sold then
                state.vendor.sold = (state.vendor.sold or 0) + 1
                state.vendor.interact_until = now + SELL_GAP
                state.set_note("Vendor", "Sold " .. tostring(item_id))
                return true
            end
        end
        if gui.is_on("repair") and not state.vendor.repaired then
            if safe(function() return core.inventory.can_merchant_repair() end) == true then
                local cost = safe(function() return core.inventory.get_total_repair_cost() end) or 0
                local gold = safe(function() return core.inventory.get_gold() end) or 0
                if type(cost) == "number" and type(gold) == "number" and cost > gold then
                    state.vendor.lack_gold = cost
                    state.vendor.repaired = true
                    state.set_note("Vendor", "Need more gold to repair")
                elseif type(cost) == "number" and cost <= 0 then
                    state.vendor.repaired = true
                else
                    pcall(function()
                        core.input.repair_all_items(false)
                    end)
                    -- A single call can miss slots, so repair runs a second pass.
                    state.vendor.repairs = (state.vendor.repairs or 0) + 1
                    if state.vendor.repairs >= REPAIR_PASSES then
                        state.vendor.repaired = true
                    end
                    state.set_note("Vendor", "Repair")
                end
            else
                state.vendor.repaired = true
            end
            state.vendor.interact_until = now + REPAIR_GAP
            return true
        end
        if try_buy(player) then
            state.vendor.interact_until = now + SELL_GAP
            return true
        end
        finish_trip("Vendor done")
        return false
    end

    if not movement.arrived(dest, ARRIVE) then
        movement.move_to(dest)
        local who = (info and info.name) or (info and info.npc_id) or "merchant"
        state.set_note("Vendor", "Travel to " .. tostring(who))
        return true
    end

    movement.stop()
    local now = izi.now()
    local unit = nil
    if info.npc_id and info.npc_id > 0 then
        unit = targeting.find_npc(player, info.npc_id, FIND_RANGE)
    end
    if not unit then
        unit = targeting.find_named(player, info.name, info.name_cn, FIND_RANGE)
    end
    if not unit then
        local started = state.vendor.wait_npc
        if type(started) ~= "number" or started <= 0 then
            started = now
            state.vendor.wait_npc = now
        end
        if now - started > 20 then
            finish_trip("Merchant not found nearby")
            return false
        end
        state.set_note("Vendor", "Merchant not found nearby")
        return true
    end
    state.vendor.wait_npc = 0

    local d = safe(function() return player:distance_to(unit) end) or 99
    if type(d) == "number" and d > 5 then
        local p = safe(function() return unit:get_position() end) or dest
        movement.move_to(p)
        return true
    end

    if now < (state.vendor.interact_until or 0) then
        return true
    end
    state.vendor.tries = (state.vendor.tries or 0) + 1
    if state.vendor.tries > 8 then
        finish_trip("Merchant did not open")
        return false
    end
    state.vendor.interact_until = now + INTERACT_GAP
    targeting.set_current(unit, "vendor")
    pcall(function()
        core.input.interact_with_object(unit)
    end)
    if gossip_open() then
        if not select_vendor_gossip() then
            close_vendor()
            state.set_note("Vendor", "No vendor gossip")
        end
    end
    state.set_note("Vendor", "Interact")
    return true
end

return vendor

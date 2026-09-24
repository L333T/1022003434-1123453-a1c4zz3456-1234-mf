-- ============================================================================
-- Master Farmer - Grindbot
-- Vendor sell + repair (Grind_Information merchants)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- Sell via core.input.use_container_item while a merchant is open.
-- Quality from core.quests.get_item_info. No is_vendor invent.
--
-- LAP VENDORING (1.6.1)
--   The Alliance 1-60 w/Vendoring routes are loops that begin and end at their
--   merchant, and they carry `vendor_each_lap`. For those, a completed lap is
--   a trip trigger in its own right, alongside the usual full-bags and broken
--   -gear ones: the bot is standing at the vendor anyway, so selling there
--   costs nothing and saves a special trip later.
--
--   Those routes give `merchant.ids` - every vendor NPC id the route's README
--   listed - because several of them pass more than one. Any of them will do,
--   so the first one actually standing nearby wins.
--
--   The merchant x/y/z on those routes is the path's FIRST WAYPOINT, not a
--   surveyed vendor position. It is only there to give the bot somewhere to
--   walk back to if a fight dragged it off the route; the npc id is what
--   identifies the merchant.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type inventory_helper
local inventory_helper = require("common/utility/inventory_helper")

---@type vec3
local vec3 = require("common/geometry/vector_3")

local gui = require("gui")
local state = require("state")
local supplies = require("supplies")
local targeting = require("targeting")
local movement = require("movement")
local rotation = require("rotation")

local vendor = {}

local HEARTHSTONE = 6948
local SELL_GAP = 0.40
local INTERACT_GAP = 1.20
local DONE_COOLDOWN = 90.0
local ARRIVE = 5.0
local FIND_RANGE = 12.0

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

--- Every vendor npc id this merchant record offers, best first.
local function merchant_ids(info)
    local out = {}
    if type(info) ~= "table" then
        return out
    end
    if type(info.npc_id) == "number" and info.npc_id > 0 then
        out[#out + 1] = info.npc_id
    end
    if type(info.ids) == "table" then
        for i = 1, #info.ids do
            local id = info.ids[i]
            if type(id) == "number" and id > 0 and id ~= info.npc_id then
                out[#out + 1] = id
            end
        end
    end
    return out
end

--- The merchant belonging to the grind path that is running right now.
--- Takes precedence over the zone table: a path that names its own vendor
--- knows better than the zone default which one it walks past.
local function path_merchant()
    local ok, runner = pcall(require, "path_runner")
    if not ok or type(runner) ~= "table" or type(runner.current_path) ~= "function" then
        return nil
    end
    local path = safe(function() return runner.current_path() end)
    if type(path) ~= "table" or type(path.merchant) ~= "table" then
        return nil
    end
    return path.merchant, path
end

local function current_merchant(player)
    local from_path = path_merchant()
    if from_path then
        return from_path
    end
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
    local info = safe(function() return core.quests.get_item_info(item_id) end)
    if type(info) ~= "table" then
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
    -- However this trip ended - sold, repaired, merchant missing, out of gold -
    -- the lap that asked for it is dealt with. Leaving the flag set would make
    -- the bot turn round and try again immediately.
    state.vendor.lap_due = false
    state.vendor.active = false
    state.vendor.repaired = false
    state.vendor.sold = 0
    state.vendor.interact_until = 0
    state.vendor.done_until = izi.now() + DONE_COOLDOWN
    state.vendor.wait_npc = 0
    state.vendor.tries = 0
    movement.nav_stop()
    close_vendor()
    if note then
        state.set_note("Vendor", note)
    end
end

function vendor.reset()
    state.vendor.active = false
    state.vendor.repaired = false
    state.vendor.sold = 0
    state.vendor.interact_until = 0
    state.vendor.done_until = 0
    state.vendor.lack_gold = 0
    state.vendor.wait_npc = 0
    state.vendor.tries = 0
    -- A lap queued a trip that is now moot: the bot has been stopped, switched
    -- to rotation only, or moved to another path. Leaving it set would send it
    -- to a merchant the new path knows nothing about.
    state.vendor.lap_due = false
end

--- Did the running path just finish a lap that should end at the vendor?
---
--- The lap is consumed whether or not the trip goes ahead, so a route whose
--- vendor cannot be reached does not queue a trip for every lap it runs.
local function lap_wants_vendor()
    local info, path = path_merchant()
    if not info or not path or path.vendor_each_lap ~= true then
        return false
    end
    if #merchant_ids(info) == 0 then
        return false
    end
    local ok, runner = pcall(require, "path_runner")
    if not ok or type(runner) ~= "table" or type(runner.take_lap) ~= "function" then
        return false
    end
    return safe(function() return runner.take_lap() end) == true
end

function vendor.needs_trip(player)
    if not player then
        return false
    end
    if not gui.is_on("sell") and not gui.is_on("repair") then
        return false
    end

    -- A completed lap on a vendoring route is a trigger by itself. Checked
    -- before the cooldown below, because the lap must be consumed on the tick
    -- it happens or it is lost.
    if gui.is_on("vendor_each_lap") and lap_wants_vendor() then
        state.vendor.lap_due = true
    end
    if state.vendor.lap_due == true then
        return true
    end
    if izi.now() < (state.vendor.done_until or 0) and not state.vendor.active then
        return false
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
    if not gui.is_on("sell") and not gui.is_on("repair") then
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
        supplies.reset()
        state.vendor.repaired = false
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
        movement.nav_stop()
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
        -- Restock before repair: repair drains gold, and arriving with no food
        -- is what forces the next trip. Buying first spends what is left over
        -- after selling instead of after repairing.
        if supplies.tick(player) then
            return true
        end

        if gui.is_on("repair") and not state.vendor.repaired then
            if safe(function() return core.inventory.can_merchant_repair() end) == true then
                local cost = safe(function() return core.inventory.get_total_repair_cost() end) or 0
                local gold = safe(function() return core.inventory.get_gold() end) or 0
                if type(cost) == "number" and type(gold) == "number" and cost > gold then
                    state.vendor.lack_gold = cost
                    state.set_note("Vendor", "Need more gold to repair")
                else
                    pcall(function()
                        core.input.repair_all_items(false)
                    end)
                    state.set_note("Vendor", "Repair")
                end
            end
            state.vendor.repaired = true
            state.vendor.interact_until = now + 0.60
            return true
        end
        finish_trip("Vendor done")
        return false
    end

    if not movement.arrived(dest, ARRIVE) then
        -- Claim the tick only if movement took the request; combat still owning
        -- the player (post-fight settle) must not stall the rest of the cascade.
        if not movement.nav_to(dest) then
            return false
        end
        local who = (info and info.name) or (info and info.npc_id) or "merchant"
        state.set_note("Vendor", "Travel to " .. tostring(who))
        return true
    end

    movement.nav_stop()
    local now = izi.now()
    local unit = nil
    local ids = merchant_ids(info)
    for i = 1, #ids do
        unit = targeting.find_npc(player, ids[i], FIND_RANGE)
        if unit then
            break
        end
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
        return movement.nav_to(p) == true
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

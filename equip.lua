-- ============================================================================
-- Master Farmer - Grindbot
-- equip.lua - auto-equip upgrades from the bags
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Ported from the reference bot's Auto_Equip / Check_Equip.
--
-- THE MECHANISM
--   core.input.use_container_item(bag, slot) is the same call vendor.lua uses
--   to sell. With a merchant open it sells; with no merchant open the client
--   equips an equippable item. So equipping needs no new API - but it does mean
--   this must NEVER run while a vendor window is open, or it sells the upgrade
--   instead of wearing it. That guard is the first thing tick() checks.
--
-- WHAT IS DELIBERATELY DIFFERENT FROM THE SOURCE
--
--   1. Armour type is a RANGE, not one type. The source matches a single
--      armour subclass per class, so a level 12 Hunter (who cannot wear Mail
--      until 40) would never equip anything. Here a class may wear its best
--      type and everything lighter, which is how levelling actually works.
--
--   2. Rings and trinkets check BOTH slots. The source only ever looked at
--      FINGER2 and TRINKET1, so it could not fill an empty finger 1 and would
--      compare against the wrong trinket.
--
--   3. Weapons are OFF by default here. The proficiency data that was missing
--      is now supplied by CLASS_WEAPONS below, keyed on the numeric
--      subclass_id that quest_item_info exposes, and equip.usable_by applies
--      it - the quest reward picker relies on exactly that. equip.tick keeps
--      the toggle off all the same: knowing a Mage MAY hold a one-handed
--      sword does not make swapping its staff for one a good idea, and that
--      judgement needs stat weights this API still does not expose.
--
--   4. It never downgrades. See `better_than` for how the comparison degrades
--      when the API does not expose an item level.
--
--   5. It confirms the bind-on-equip prompt. Equipping a BoE item raises a
--      "this will bind to you" dialog and the equip does not complete until it
--      is answered. Without that step the bot re-issues the same equip forever
--      and never wears the upgrade. core.game_ui.get_pending_equip_slot detects
--      the prompt and core.input.equip_pending_item answers it.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type enums
local enums = require("common/enums")

local gui = require("gui")
local state = require("state")

local equip = {}

local SCAN_GAP = 10.0        -- seconds between bag scans
local ACT_GAP  = 1.5         -- seconds between equip attempts

-- Far in the past, not 0: the first tick must be able to act regardless of what
-- izi.now() happens to be, instead of sitting out the gap once at startup.
local last_scan = -1e9
local last_act  = -1e9
local debug_done = false

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- SLOTS
-- ----------------------------------------------------------------------------
-- Equipment slot numbering 1-19, confirmed by targeting.lua (RANGED_SLOT = 18).
local SLOT = {
    HEAD = 1, NECK = 2, SHOULDER = 3, BODY = 4, CHEST = 5, WAIST = 6,
    LEGS = 7, FEET = 8, WRIST = 9, HAND = 10, FINGER1 = 11, FINGER2 = 12,
    TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17,
    RANGED = 18, TABARD = 19,
}

-- equip_loc -> candidate slots. More than one slot means "pick the empty one,
-- else the weaker one".
local LOC_SLOTS = {
    INVTYPE_HEAD            = { SLOT.HEAD },
    INVTYPE_NECK            = { SLOT.NECK },
    INVTYPE_SHOULDER        = { SLOT.SHOULDER },
    INVTYPE_BODY            = { SLOT.BODY },
    INVTYPE_CHEST           = { SLOT.CHEST },
    INVTYPE_ROBE            = { SLOT.CHEST },
    INVTYPE_WAIST           = { SLOT.WAIST },
    INVTYPE_LEGS            = { SLOT.LEGS },
    INVTYPE_FEET            = { SLOT.FEET },
    INVTYPE_WRIST           = { SLOT.WRIST },
    INVTYPE_HAND            = { SLOT.HAND },
    INVTYPE_FINGER          = { SLOT.FINGER1, SLOT.FINGER2 },
    INVTYPE_TRINKET         = { SLOT.TRINKET1, SLOT.TRINKET2 },
    INVTYPE_CLOAK           = { SLOT.BACK },
    INVTYPE_TABARD          = { SLOT.TABARD },
}

-- Weapon / ranged locations, gated behind the weapons toggle (see header note 3).
local WEAPON_SLOTS = {
    INVTYPE_WEAPON          = { SLOT.MAINHAND },
    INVTYPE_2HWEAPON        = { SLOT.MAINHAND },
    INVTYPE_WEAPONMAINHAND  = { SLOT.MAINHAND },
    INVTYPE_WEAPONOFFHAND   = { SLOT.OFFHAND },
    INVTYPE_SHIELD          = { SLOT.OFFHAND },
    INVTYPE_HOLDABLE        = { SLOT.OFFHAND },
    INVTYPE_RANGED          = { SLOT.RANGED },
    INVTYPE_RANGEDRIGHT     = { SLOT.RANGED },
    INVTYPE_THROWN          = { SLOT.RANGED },
}

-- ----------------------------------------------------------------------------
-- ARMOUR
-- ----------------------------------------------------------------------------
-- Heaviest armour each class may wear. A class may also wear everything
-- lighter, which is what makes levelling work - see header note 1.
local ARMOUR_RANK = { cloth = 1, leather = 2, mail = 3, plate = 4 }

local CLASS_ARMOUR = {
    [enums.class_id.MAGE]    = 1,
    [enums.class_id.WARLOCK] = 1,
    [enums.class_id.PRIEST]  = 1,
    [enums.class_id.ROGUE]   = 2,
    [enums.class_id.DRUID]   = 2,
    [enums.class_id.HUNTER]  = 3,
    [enums.class_id.SHAMAN]  = 3,
    [enums.class_id.WARRIOR] = 4,
    [enums.class_id.PALADIN] = 4,
}

-- ----------------------------------------------------------------------------
-- NUMERIC ITEM CLASSES
-- ----------------------------------------------------------------------------
-- quest_item_info carries class_id / subclass_id, which are numbers and so
-- survive a non-English client. item_sub_type is a localised string and only
-- works on an English one, so the numeric path is tried first everywhere below.
local ITEM_CLASS = { ARMOR = 4, WEAPON = 2 }

local ARMOR_SUB = { MISC = 0, CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4,
                    SHIELD = 6, LIBRAM = 7, IDOL = 8, TOTEM = 9 }

local ARMOUR_RANK_BY_SUB = {
    [ARMOR_SUB.CLOTH] = 1, [ARMOR_SUB.LEATHER] = 2,
    [ARMOR_SUB.MAIL] = 3, [ARMOR_SUB.PLATE] = 4,
}

local W = { AXE1 = 0, AXE2 = 1, BOW = 2, GUN = 3, MACE1 = 4, MACE2 = 5,
            POLEARM = 6, SWORD1 = 7, SWORD2 = 8, STAFF = 10, FIST = 13,
            MISC = 14, DAGGER = 15, THROWN = 16, CROSSBOW = 18, WAND = 19,
            FISHING = 20 }

-- What each class may train in TBC, ignoring talents. Closes header note 3:
-- the proficiency data the API does not expose is static and well known, so a
-- table is the honest way to supply it rather than guessing from the name.
local CLASS_WEAPONS = {
    [enums.class_id.WARRIOR] = { [W.AXE1]=1,[W.AXE2]=1,[W.MACE1]=1,[W.MACE2]=1,[W.SWORD1]=1,[W.SWORD2]=1,
                                 [W.POLEARM]=1,[W.STAFF]=1,[W.DAGGER]=1,[W.FIST]=1,
                                 [W.BOW]=1,[W.GUN]=1,[W.CROSSBOW]=1,[W.THROWN]=1 },
    [enums.class_id.PALADIN] = { [W.AXE1]=1,[W.AXE2]=1,[W.MACE1]=1,[W.MACE2]=1,[W.SWORD1]=1,[W.SWORD2]=1,
                                 [W.POLEARM]=1 },
    [enums.class_id.HUNTER]  = { [W.AXE1]=1,[W.AXE2]=1,[W.SWORD1]=1,[W.SWORD2]=1,[W.POLEARM]=1,
                                 [W.STAFF]=1,[W.DAGGER]=1,[W.FIST]=1,
                                 [W.BOW]=1,[W.GUN]=1,[W.CROSSBOW]=1,[W.THROWN]=1 },
    [enums.class_id.ROGUE]   = { [W.DAGGER]=1,[W.SWORD1]=1,[W.MACE1]=1,[W.FIST]=1,[W.AXE1]=1,
                                 [W.BOW]=1,[W.GUN]=1,[W.CROSSBOW]=1,[W.THROWN]=1 },
    [enums.class_id.PRIEST]  = { [W.MACE1]=1,[W.DAGGER]=1,[W.STAFF]=1,[W.WAND]=1 },
    [enums.class_id.SHAMAN]  = { [W.AXE1]=1,[W.AXE2]=1,[W.MACE1]=1,[W.MACE2]=1,[W.STAFF]=1,
                                 [W.DAGGER]=1,[W.FIST]=1 },
    [enums.class_id.MAGE]    = { [W.SWORD1]=1,[W.DAGGER]=1,[W.STAFF]=1,[W.WAND]=1 },
    [enums.class_id.WARLOCK] = { [W.SWORD1]=1,[W.DAGGER]=1,[W.STAFF]=1,[W.WAND]=1 },
    [enums.class_id.DRUID]   = { [W.MACE1]=1,[W.MACE2]=1,[W.STAFF]=1,[W.DAGGER]=1,[W.FIST]=1,[W.POLEARM]=1 },
}

-- Shields, and the class-specific relic subclasses.
local CLASS_SHIELD = {
    [enums.class_id.WARRIOR] = true, [enums.class_id.PALADIN] = true,
    [enums.class_id.SHAMAN]  = true,
}
local CLASS_RELIC = {
    [enums.class_id.PALADIN] = ARMOR_SUB.LIBRAM,
    [enums.class_id.DRUID]   = ARMOR_SUB.IDOL,
    [enums.class_id.SHAMAN]  = ARMOR_SUB.TOTEM,
}

--- Armour rank of an item, or nil when it is not armour we gate on.
--- Numeric subclass first, localised name only as a fallback.
local function armour_rank(info)
    if type(info.class_id) == "number" and info.class_id == ITEM_CLASS.ARMOR
        and type(info.subclass_id) == "number" then
        return ARMOUR_RANK_BY_SUB[info.subclass_id]
    end
    local sub = info.item_sub_type
    if type(sub) ~= "string" then
        return nil
    end
    return ARMOUR_RANK[string.lower(sub)]
end

-- ----------------------------------------------------------------------------
-- ITEM INFO
-- ----------------------------------------------------------------------------
local function item_info(item_id)
    if type(item_id) ~= "number" or item_id <= 0 then
        return nil
    end
    local info = safe(function() return core.quests.get_item_info(item_id) end)
    if type(info) ~= "table" then
        return nil
    end
    return info
end

--- Item level, if this build exposes it under any of the plausible names.
--- Returns nil when unavailable, which downgrades the comparison - see
--- `better_than`. Guessing a field name that does not exist would read nil and
--- silently compare nothing, so every candidate is checked explicitly.
local function item_level(info)
    local v = info.item_level or info.level or info.ilvl or info.item_lvl
    if type(v) == "number" and v > 0 then
        return v
    end
    return nil
end

local function required_level(info)
    local v = info.required_level or info.req_level or info.min_level
    if type(v) == "number" then
        return v
    end
    return nil
end

local function quality_of(info)
    local q = info.quality
    if type(q) == "number" then
        return q
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- COMPARISON
-- ----------------------------------------------------------------------------
--- Is `cand` a real upgrade over `cur`? `cur` nil means the slot is empty.
---
--- When the API exposes an item level this mirrors the source's rules: higher
--- level at no worse quality, or higher quality at no worse level, or a level
--- gap wide enough to outweigh a quality drop.
---
--- When it does NOT expose one, the only safe move is to fill empty slots and
--- to replace strictly on quality. Anything else risks swapping a good item for
--- a worse one every ten seconds, which is far more damaging than equipping
--- nothing at all.
local function better_than(cand, cur)
    if not cur then
        return true, "empty slot"
    end

    local cq, uq = quality_of(cand), quality_of(cur)
    local cl, ul = item_level(cand), item_level(cur)

    if not cl or not ul then
        if cq and uq and cq > uq then
            return true, "better quality (no item level available)"
        end
        return false
    end

    if cl > ul and (not cq or not uq or cq >= uq) then
        return true, "higher item level"
    end
    if cq and uq and cq > uq and cl >= ul then
        return true, "better quality"
    end
    if (cl - ul) >= 3 and cq and cq >= 1 then
        return true, "item level gap >= 3"
    end
    if (cl - ul) >= 5 then
        return true, "item level gap >= 5"
    end
    return false
end

-- ----------------------------------------------------------------------------
-- EQUIPPED STATE
-- ----------------------------------------------------------------------------
local function equipped_info(player, slot)
    local at = safe(function() return player:get_item_at_inventory_slot(slot) end)
    if type(at) ~= "table" or not at.object then
        return nil
    end
    local id = safe(function() return at.object:get_item_id() end)
    if type(id) ~= "number" or id <= 0 then
        return nil
    end
    return item_info(id)
end

--- Best target slot for a candidate: an empty one if there is any, otherwise
--- the one holding the weakest item.
local function pick_slot(player, slots)
    local weakest_slot, weakest_info = nil, nil
    for i = 1, #slots do
        local s = slots[i]
        local cur = equipped_info(player, s)
        if not cur then
            return s, nil
        end
        if not weakest_slot then
            weakest_slot, weakest_info = s, cur
        else
            local swap = better_than(weakest_info, cur)
            if swap then
                weakest_slot, weakest_info = s, cur
            end
        end
    end
    return weakest_slot, weakest_info
end

-- ----------------------------------------------------------------------------
-- DIAGNOSTIC
-- ----------------------------------------------------------------------------
-- The comparison quality depends entirely on whether get_item_info exposes an
-- item level. This prints the real keys of one item's info table, once, so that
-- can be established instead of guessed.
local function debug_dump(info, item_id)
    if debug_done or not gui.is_on("equip_debug") then
        return
    end
    debug_done = true
    core.log("[Master Farmer - Grindbot] get_item_info(" .. tostring(item_id) .. ") fields:")
    local keys = {}
    for k in pairs(info) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for i = 1, #keys do
        local v = info[keys[i]]
        local t = type(v)
        if t == "string" or t == "number" or t == "boolean" then
            core.log(string.format("    %-18s %s = %s", keys[i], t, tostring(v)))
        else
            core.log(string.format("    %-18s %s", keys[i], t))
        end
    end
    core.log("    item level readable: " .. (item_level(info) and "YES" or "NO - upgrades limited to empty slots"))
end

-- ----------------------------------------------------------------------------
-- SCAN
-- ----------------------------------------------------------------------------
--- Find the first genuine upgrade in the bags. Returns bag, slot_id, label.
local function find_upgrade(player)
    local class_id = safe(function() return player:get_class() end)
    local max_armour = CLASS_ARMOUR[class_id]
    local level = safe(function() return player:get_level() end)
    local allow_weapons = gui.is_on("equip_weapons")

    for bag = 0, 4 do
        local items = safe(function() return core.inventory.get_items_in_bag(bag) end)
        if type(items) == "table" then
            for i = 1, #items do
                local entry = items[i]
                if type(entry) == "table" and entry.object and type(entry.slot_id) == "number" then
                    local item_id = safe(function() return entry.object:get_item_id() end)
                    local info = item_info(item_id)
                    if info then
                        debug_dump(info, item_id)

                        local loc = info.equip_loc
                        local slots = nil
                        if type(loc) == "string" then
                            slots = LOC_SLOTS[loc]
                            if not slots and allow_weapons then
                                slots = WEAPON_SLOTS[loc]
                            end
                        end

                        if slots then
                            -- required level: skip anything we cannot wear yet
                            local req = required_level(info)
                            local level_ok = true
                            if req and type(level) == "number" and req > level then
                                level_ok = false
                            end

                            -- armour type: only gate items that ARE armour
                            local rank = armour_rank(info)
                            local armour_ok = true
                            if rank and max_armour and rank > max_armour then
                                armour_ok = false
                            end

                            if level_ok and armour_ok then
                                local slot, cur = pick_slot(player, slots)
                                if slot then
                                    local ok, why = better_than(info, cur)
                                    if ok then
                                        local name = info.name or ("item " .. tostring(item_id))
                                        return bag, entry.slot_id, name .. " (" .. tostring(why) .. ")"
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- PUBLIC
-- ----------------------------------------------------------------------------
--- Called from the main cascade. Returns true when it acted this tick.
function equip.tick(player)
    if not player or not gui.is_on("auto_equip") then
        return false
    end

    -- use_container_item SELLS while a merchant is open. Never scan then.
    if safe(function() return core.game_ui.get_vendor_item_count() end) then
        local n = safe(function() return core.game_ui.get_vendor_item_count() end) or 0
        if n > 0 then
            return false
        end
    end

    if safe(function() return player:is_in_combat() end) == true then
        return false
    end
    if safe(function() return player:is_mounted() end) == true then
        return false
    end
    if safe(function() return player:is_dead_or_ghost() end) == true then
        return false
    end

    local now = izi.now()

    -- A bind-on-equip item raises a confirmation prompt and the equip stalls
    -- until it is answered. Answer it before doing anything else, or every
    -- later attempt queues behind a dialog that is never dismissed.
    local pending = safe(function() return core.game_ui.get_pending_equip_slot() end)
    if type(pending) == "number" and pending >= 0 then
        state.set_note("Equip", "Confirming bind-on-equip")
        pcall(function() core.input.equip_pending_item(pending) end)
        last_act = now
        return true
    end

    if (now - last_act) < ACT_GAP then
        return true          -- an equip is still landing; hold the cascade
    end
    if (now - last_scan) < SCAN_GAP then
        return false
    end
    last_scan = now

    local bag, slot_id, label = find_upgrade(player)
    if not bag then
        return false
    end

    last_act = now
    state.set_note("Equip", "Equipping " .. tostring(label))
    core.log("[Master Farmer - Grindbot] Auto-equip: " .. tostring(label))
    pcall(function() core.input.use_container_item(bag, slot_id) end)
    return true
end

--- Force the next tick to rescan. Call after looting so an upgrade is picked up
--- without waiting out the scan gap.
-- ----------------------------------------------------------------------------
-- SHARED RATING  (used by the quest reward picker)
-- ----------------------------------------------------------------------------
--- Item info for an item id OR an item link. Quest rewards only ever hand out
--- links, and core.quests.get_item_info takes integer|string.
function equip.info_of(id_or_link)
    if type(id_or_link) == "number" then
        return item_info(id_or_link)
    end
    if type(id_or_link) ~= "string" or id_or_link == "" then
        return nil
    end
    local info = safe(function() return core.quests.get_item_info(id_or_link) end)
    if type(info) ~= "table" then
        return nil
    end
    return info
end

--- Can this character actually equip and use `info`?
---
--- Returns (usable, slots, why). `slots` is the candidate inventory slot list
--- when the item is equippable, nil otherwise. `why` explains a refusal and is
--- meant for the debug log.
function equip.usable_by(player, info)
    if type(info) ~= "table" then
        return false, nil, "no item info"
    end

    local loc = info.equip_loc
    if type(loc) ~= "string" or loc == "" or loc == "INVTYPE_NON_EQUIP" then
        return false, nil, "not equippable"
    end
    local slots = LOC_SLOTS[loc] or WEAPON_SLOTS[loc]
    if loc == "INVTYPE_RELIC" then
        slots = { SLOT.RANGED }
    end
    if not slots then
        return false, nil, "unknown equip location " .. loc
    end

    local lvl = safe(function() return player:get_level() end)
    local req = required_level(info)
    if type(lvl) == "number" and type(req) == "number" and req > lvl then
        return false, slots, string.format("needs level %d, character is %d", req, lvl)
    end

    local class_id = safe(function() return player:get_class() end)

    -- Armour: the class may wear its own weight and anything lighter.
    local rank = armour_rank(info)
    if rank then
        local max_rank = CLASS_ARMOUR[class_id]
        if max_rank and rank > max_rank then
            return false, slots, "armour too heavy for this class"
        end
        return true, slots, nil
    end

    local cls, sub = info.class_id, info.subclass_id
    if type(cls) == "number" and type(sub) == "number" then
        if cls == ITEM_CLASS.WEAPON then
            local allowed = CLASS_WEAPONS[class_id]
            if allowed and not allowed[sub] then
                return false, slots, "class cannot use this weapon type"
            end
            return true, slots, nil
        end
        if cls == ITEM_CLASS.ARMOR then
            if sub == ARMOR_SUB.SHIELD then
                if not CLASS_SHIELD[class_id] then
                    return false, slots, "class cannot use shields"
                end
                return true, slots, nil
            end
            if sub == ARMOR_SUB.LIBRAM or sub == ARMOR_SUB.IDOL or sub == ARMOR_SUB.TOTEM then
                if CLASS_RELIC[class_id] ~= sub then
                    return false, slots, "relic belongs to another class"
                end
                return true, slots, nil
            end
            -- ARMOR_SUB.MISC: rings, necks, trinkets, cloaks. Anyone may wear them.
            return true, slots, nil
        end
    end

    -- No numeric class data: it is equippable and nothing says otherwise.
    return true, slots, nil
end

--- Rate a candidate for the quest reward picker.
---
--- tier 3  a usable upgrade over what is worn
--- tier 2  usable, but not better than what is worn
--- tier 1  not equippable at all - a bag, a consumable, a stack of reagents
--- tier 0  equippable but this class cannot use it
---
--- Ties inside a tier break on item level, then quality, then vendor price, so
--- "best usable item" means the strongest thing the character can actually
--- wear, and only falls back to raw value when nothing is wearable.
function equip.rate(player, info)
    if type(info) ~= "table" then
        return nil
    end
    local usable, slots, why = equip.usable_by(player, info)
    local tier, reason

    if not slots then
        tier, reason = 1, why or "not equippable"
    elseif not usable then
        tier, reason = 0, why or "unusable"
    else
        local cur_slot = pick_slot(player, slots)
        local cur = cur_slot and equipped_info(player, cur_slot) or nil
        local better, note = better_than(info, cur)
        if better then
            tier, reason = 3, note or "upgrade"
        else
            tier, reason = 2, "usable, not an upgrade"
        end
    end

    return {
        tier = tier,
        reason = reason,
        item_level = item_level(info) or 0,
        quality = quality_of(info) or 0,
        sell_price = (type(info.sell_price) == "number" and info.sell_price) or 0,
        name = info.name,
    }
end

--- True when `a` is a strictly better reward than `b`.
function equip.rating_beats(a, b)
    if not b then return a ~= nil end
    if not a then return false end
    if a.tier ~= b.tier then return a.tier > b.tier end
    if a.item_level ~= b.item_level then return a.item_level > b.item_level end
    if a.quality ~= b.quality then return a.quality > b.quality end
    return a.sell_price > b.sell_price
end

function equip.invalidate()
    last_scan = 0
end

function equip.register_gui(menu)
    menu:checkbox("mfg_auto_equip", false, {
        label = "Auto Equip Upgrades",
        tab = "settings",
        tooltip = "Equip better armour from your bags out of combat. Never downgrades.",
    })
    menu:checkbox("mfg_equip_weapons", false, {
        label = "Auto Equip Weapons",
        tab = "settings",
        tooltip = "Off: this API exposes no class weapon proficiencies, so a usable but wrong "
            .. "weapon could be equipped and break the rotation.",
    })
    menu:checkbox("mfg_equip_debug", false, {
        label = "Log item info fields",
        tab = "settings",
        tooltip = "Prints once what get_item_info actually returns. Use this to confirm whether "
            .. "an item level is available - without one, only empty slots are filled.",
    })
end

return equip

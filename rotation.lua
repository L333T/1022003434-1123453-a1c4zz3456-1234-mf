-- ============================================================================
-- Master Farmer - Grindbot
-- Class rotation dispatcher
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- Adding a class: create rotations/<class>.lua and register it here.
-- ============================================================================

---@type enums
local enums = require("common/enums")

local mage = require("rotations/mage")
local priest = require("rotations/priest")
local druid = require("rotations/druid")
local paladin = require("rotations/paladin")
local hunter = require("rotations/hunter")
local warlock = require("rotations/warlock")
local shaman = require("rotations/shaman")
local rogue = require("rotations/rogue")
local targeting = require("targeting")
local combat = require("combat")

local by_class = {}
local function register(mod)
    if mod and type(mod.class_id) == "function" then
        local ok, id = pcall(mod.class_id)
        if ok and id ~= nil then
            by_class[id] = mod
        end
    end
end

register(mage)
register(priest)
register(druid)
register(paladin)
register(hunter)
register(warlock)
register(shaman)
register(rogue)

local rotation = {}
local last_action = "Idle"

-- ----------------------------------------------------------------------------
-- Movement is required lazily so the rotation dispatcher stays loadable even if
-- the movement module fails; `profile_mod` tracks which class's combat-movement
-- rules are currently installed so we only re-register on an actual change.
-- ----------------------------------------------------------------------------
local movement_mod = nil
local profile_mod = false          -- false = never synced, nil = cleared

local function get_movement()
    if movement_mod then return movement_mod end
    local ok, mod = pcall(require, "movement")
    if ok and type(mod) == "table" then movement_mod = mod end
    return movement_mod
end

--- Install the active class's combat-movement profile (§17). The movement
--- controller owns positioning; the class only supplies the rules.
local function sync_profile(mod)
    if mod == profile_mod then return end
    profile_mod = mod
    local movement = get_movement()
    if not movement then return end
    if mod and type(mod.combat_profile) == "function" then
        local ok, p = pcall(mod.combat_profile)
        if ok and type(p) == "table" then
            movement.set_combat_profile(p)
            return
        end
    end
    movement.clear_combat_profile()
end

-- ----------------------------------------------------------------------------
-- RESTING AND SCANNING - both are the class's to decide
-- ----------------------------------------------------------------------------
--- Sit down and eat or drink, using the active class's thresholds.
---
--- A class that defines rest() owns the decision. Anything that does not falls
--- back to the shared default, so an unsupported class still eats.
function rotation.rest(player)
    if not player then
        return false
    end
    local mod = rotation.active(player)
    if mod and type(mod.rest) == "function" then
        local ok, acted = pcall(mod.rest, player)
        if ok then
            return acted == true
        end
    end
    local ok, resting = pcall(require, "resting")
    if ok and resting and type(resting.tick) == "function" then
        return resting.tick(player, nil) == true
    end
    return false
end

--- Is the bot sitting down right now?
function rotation.is_resting()
    local ok, resting = pcall(require, "resting")
    if ok and resting and type(resting.is_resting) == "function" then
        return resting.is_resting() == true
    end
    return false
end

--- How far out this class looks for something to fight. Melee scans tighter
--- than a caster: see the note on each rotation's scan_range.
function rotation.scan_range(player)
    local mod = player and rotation.active(player) or nil
    if mod and type(mod.scan_range) == "function" then
        local ok, yards = pcall(mod.scan_range, player)
        if ok and type(yards) == "number" and yards >= 5 then
            return yards
        end
    end
    return 30
end

function rotation.supported(class_id)
    return by_class[class_id] ~= nil
end

function rotation.module_for(class_id)
    return by_class[class_id]
end

function rotation.active(player)
    if not player then
        return nil
    end
    local ok, class_id = pcall(function()
        return player:get_class()
    end)
    if not ok then
        return nil
    end
    local mod = by_class[class_id]
    sync_profile(mod)
    return mod
end

function rotation.register_gui(menu)
    for _, mod in pairs(by_class) do
        if type(mod.register_gui) == "function" then
            pcall(mod.register_gui, menu)
        end
    end
end

function rotation.buffs_ooc(player)
    -- Buff casts cancel eating and drinking exactly like combat casts do.
    local ok_h, healing = pcall(require, "healing")
    if ok_h and healing and type(healing.is_resting) == "function" then
        if healing.is_resting() == true then
            return false
        end
    end

    local mod = rotation.active(player)
    if not mod or type(mod.buffs_ooc) ~= "function" then
        return false
    end
    return mod.buffs_ooc(player) == true
end

function rotation.combat_range(player)
    local mod = rotation.active(player)
    if mod and type(mod.combat_range) == "function" then
        local yards = mod.combat_range(player)
        if type(yards) == "number" and yards > 0 then
            return yards
        end
    end
    return 30
end

function rotation.tick(player, target, ctx)
    -- Nothing in the combat routine may fire during a rest: every cast and
    -- the auto-attack start below cancels eating or drinking. main.lua already
    -- returns before this, but a grind or quest engine calling rotation.tick
    -- directly would bypass that. Lazy require - healing requires rotation.
    local ok_h, healing = pcall(require, "healing")
    if ok_h and healing and type(healing.is_resting) == "function" then
        if healing.is_resting() == true then
            return false
        end
    end

    local mod = rotation.active(player)
    if not mod or type(mod.tick) ~= "function" then
        return false
    end
    ctx = ctx or {}
    local pack = ctx.enemies
    if type(pack) ~= "table" then
        pack = nil
    end
    local resolved, scanned = combat.acquire(player, rotation.combat_range(player), target, pack)
    if not resolved then
        return false
    end
    target = resolved
    ctx.enemies = scanned
    if combat.dismount(player, target) then
        return true
    end
    if combat.assist(player, target, scanned, mod) then
        return true
    end
    if player and target and targeting and type(targeting.start_auto_attack) == "function" then
        targeting.start_auto_attack(player, target)
    end
    -- Facing is idempotent and throttled inside movement, so asserting it here
    -- is safe even when combat movement is already facing the same target. It
    -- is what keeps Rotation Only mode (no combat movement) pointed the right
    -- way. This is a facing command, never a movement command.
    if target then
        local movement = get_movement()
        if movement then
            movement.face(target)
        end
    end
    return mod.tick(player, target, ctx) == true
end

function rotation.preferred_food_ids(player)
    local mod = rotation.active(player)
    if mod and type(mod.preferred_food_ids) == "function" then
        return mod.preferred_food_ids()
    end
    return nil
end

function rotation.preferred_drink_ids(player)
    local mod = rotation.active(player)
    if mod and type(mod.preferred_drink_ids) == "function" then
        return mod.preferred_drink_ids()
    end
    return nil
end

function rotation.set_last_action(text)
    if type(text) == "string" and text ~= "" then
        last_action = text
    end
end

function rotation.last_action()
    return last_action
end

function rotation.class_labels()
    return {
        { id = enums.class_id.WARRIOR, label = "Warrior" },
        { id = enums.class_id.PALADIN, label = "Paladin" },
        { id = enums.class_id.HUNTER, label = "Hunter" },
        { id = enums.class_id.ROGUE, label = "Rogue" },
        { id = enums.class_id.PRIEST, label = "Priest" },
        { id = enums.class_id.SHAMAN, label = "Shaman" },
        { id = enums.class_id.MAGE, label = "Mage" },
        { id = enums.class_id.WARLOCK, label = "Warlock" },
        { id = enums.class_id.DRUID, label = "Druid" },
    }
end

return rotation

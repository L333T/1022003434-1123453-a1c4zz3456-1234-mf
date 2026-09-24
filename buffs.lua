-- ============================================================================
-- Master Farmer - Grindbot
-- Self-buff upkeep
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- WHEN A BUFF IS MAINTAINED
--   The bot must be doing something - rotation only, a grind profile, or a
--   quest profile - and it must not be resting. Those are the conditions the
--   request names, and each one is checked rather than assumed:
--
--     doing something   gui.is_on("rotation_only") or gui.is_started()
--     not resting       healing.is_resting() is false
--
--   Resting matters because eating and drinking break on any cast. A buff
--   refreshed mid-drink costs the whole drink, which is a worse trade than
--   the buff being a few seconds late.
--
-- WHICH BUFFS
--   Whatever is ticked in the Spells tab, which lists everything the scanner
--   filed as a buff. Nothing is hardcoded here: a Mage with Mana Shield ticked
--   gets Mana Shield kept up, and the same code keeps a Shaman's Lightning
--   Shield up, because both arrive as a buff family from the same scan.
--
-- HOW "EXPIRED" IS DECIDED
--   By asking whether the aura is on the player, not by timing the cast. A
--   timer drifts, gets cleared by a dispel it never hears about, and has to
--   guess a duration per rank. has_buff on the family's rank ids is the direct
--   question and needs no table of durations.
--
-- ONE AT A TIME
--   One buff per tick, with a gap between. A global cooldown is shared, so
--   firing five buffs in one frame just means four refusals, and the refusals
--   are silent.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local gui = require("gui")
local spellbook = require("spellbook")
local state = require("state")

local buffs = {}

local ACT_GAP = 1.2          -- seconds between buff casts
local RETRY_GAP = 6.0        -- how long before re-trying one that did not land

local last_act = -1e9
local failed_until = {}      -- name -> time before which we do not retry

-- Which buffs the player has switched on, by spell name. Kept here rather
-- than in menu elements because the spell list is discovered at runtime and
-- the menu's elements are registered at load - the same mismatch that made
-- the route index unreachable in 1.9.3.
local enabled = {}

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- TOGGLE STATE
-- ----------------------------------------------------------------------------
function buffs.is_enabled(name)
    if type(name) ~= "string" then
        return false
    end
    return enabled[name] == true
end

function buffs.set_enabled(name, on)
    if type(name) ~= "string" then
        return
    end
    enabled[name] = (on == true) or nil
    failed_until[name] = nil
end

function buffs.toggle(name)
    buffs.set_enabled(name, not buffs.is_enabled(name))
    return buffs.is_enabled(name)
end

--- How many buffs are switched on, for the tab's status line.
function buffs.enabled_count()
    local n = 0
    for _ in pairs(enabled) do
        n = n + 1
    end
    return n
end

-- ----------------------------------------------------------------------------
-- CONDITIONS
-- ----------------------------------------------------------------------------
--- Is the bot doing something that justifies keeping buffs up?
local function bot_is_working()
    if gui.is_on("rotation_only") then
        return true
    end
    if type(gui.is_started) == "function" and gui.is_started() then
        return true
    end
    return false
end

local function is_resting()
    local ok, healing = pcall(require, "healing")
    if ok and healing and type(healing.is_resting) == "function" then
        return healing.is_resting() == true
    end
    return false
end

--- Is this buff's aura on the player right now?
--- Every rank is offered, because a lower rank's aura is still the buff.
local function aura_up(player, fam)
    local ids = fam.ranks
    if type(ids) ~= "table" or #ids == 0 then
        ids = { fam.id }
    end
    if safe(function() return player:has_buff(ids) end) == true then
        return true
    end
    return safe(function() return player:has_aura(ids) end) == true
end

-- ----------------------------------------------------------------------------
-- TICK
-- ----------------------------------------------------------------------------
--- Keep the enabled buffs up. Returns true when it cast something, so the
--- caller can hold the rest of its tick.
function buffs.tick(player)
    if not player then
        return false
    end
    if not bot_is_working() then
        return false
    end
    if is_resting() then
        return false
    end

    -- Mounted or already casting: a buff now would either not go off or would
    -- cancel what is going off.
    if safe(function() return player:is_mounted() end) == true then
        return false
    end

    local now = izi.now()
    if (now - last_act) < ACT_GAP then
        return false
    end

    if type(spellbook.ready) == "function" and spellbook.ready() ~= true then
        return false
    end

    local ok_cat, cats = pcall(require, "data/spell_categories")
    local buff_key = (ok_cat and cats and cats.BUFF) or "buff"
    local list = (type(spellbook.category) == "function") and spellbook.category(buff_key) or {}

    for i = 1, #list do
        local fam = list[i]
        local name = fam.name
        if enabled[name] then
            local hold = failed_until[name] or 0
            if now >= hold and not aura_up(player, fam) then
                local spell = safe(function() return izi.spell(fam.id) end)
                local cast = false
                if spell then
                    cast = safe(function() return spell:cast_safe(player, name) end) == true
                    if not cast then
                        cast = safe(function() return spell:cast(player, name) end) == true
                    end
                end

                last_act = now
                if cast then
                    state.set_note("Buff", "Casting " .. tostring(name))
                else
                    -- Out of mana, on cooldown, or not castable here. Back off
                    -- rather than retrying every tick and burning the gap on a
                    -- spell that will not go.
                    failed_until[name] = now + RETRY_GAP
                end
                return cast
            end
        end
    end

    return false
end

--- Forget the back-off timers. Called when the bot stops.
function buffs.reset()
    failed_until = {}
end

return buffs

-- ============================================================================
-- Master Farmer - Grindbot
-- pets.lua - shared pet handling for Hunter and Warlock
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- Shared on purpose. Hunter and Warlock both need summon / revive / heal /
-- attack / stance, differing only in spell ids and in whether summoning costs a
-- reagent. Duplicating that in two rotation files is how the two copies drift.
--
-- API (confirmed present in the reflected reference):
--   unit:get_pet()                        the pet object, or nil
--   unit:is_pet()
--   core.spell_book.get_pet_happiness()   Hunter only; Warlock pets have none
--   core.input.pet_attack / set_pet_passive / set_pet_defensive / set_pet_follow
--
-- THE ORDERING RULE THAT MATTERS
--   Out of combat the pet is set PASSIVE. The reference bot does this too, and
--   it is not cosmetic: an aggressive pet wanders into neighbouring packs while
--   the bot is pathing and pulls everything. Combat sets it back to attack.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local state = require("state")

local pets = {}

local ACT_GAP = 1.5

local function safe(fn)
    local ok, r = pcall(fn)
    if ok then return r end
    return nil
end

-- ----------------------------------------------------------------------------
-- STATE
-- ----------------------------------------------------------------------------
--- The live pet object, or nil. A dead pet still returns an object, so callers
--- that need "usable pet" must also check `pets.alive`.
function pets.get(player)
    if not player then
        return nil
    end
    local pet = safe(function() return player:get_pet() end)
    if pet and safe(function() return pet:is_valid() end) == true then
        return pet
    end
    return nil
end

function pets.alive(player)
    local pet = pets.get(player)
    if not pet then
        return false
    end
    if safe(function() return pet:is_dead_or_ghost() end) == true then
        return false
    end
    if safe(function() return pet:is_dead() end) == true then
        return false
    end
    return true
end

function pets.exists(player)
    return pets.get(player) ~= nil
end

function pets.health_pct(player)
    local pet = pets.get(player)
    if not pet then
        return nil
    end
    local pct = safe(function() return pet:health_pct() end)
    if type(pct) == "number" then
        if pct >= 0 and pct <= 1.5 then
            return pct * 100
        end
        return pct
    end
    local cur = safe(function() return pet:get_health() end)
    local mx = safe(function() return pet:get_max_health() end)
    if type(cur) == "number" and type(mx) == "number" and mx > 0 then
        return (cur / mx) * 100
    end
    return nil
end

--- Hunter pet happiness, 1 unhappy .. 3 content. nil for classes without it.
function pets.happiness()
    local h = safe(function() return core.spell_book.get_pet_happiness() end)
    if type(h) == "number" then
        return h
    end
    if type(h) == "table" and type(h.happiness) == "number" then
        return h.happiness
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- CONTROL
-- ----------------------------------------------------------------------------
local last_stance = 0
local last_attack = 0

--- Park the pet. Out of combat an aggressive pet pulls packs the bot never
--- chose to fight, which is the single biggest source of unattended deaths.
function pets.passive(player)
    if not pets.alive(player) then
        return false
    end
    local now = izi.now()
    if (now - last_stance) < ACT_GAP then
        return false
    end
    last_stance = now
    pcall(function() core.input.set_pet_passive() end)
    pcall(function() core.input.set_pet_follow() end)
    return true
end

--- Send the pet at the current target.
function pets.attack(player, target)
    if not target or not pets.alive(player) then
        return false
    end
    local now = izi.now()
    if (now - last_attack) < ACT_GAP then
        return false
    end

    -- Only re-issue when the pet is not already on this target: pet_attack
    -- resets its swing timer, so spamming it every tick lowers pet damage.
    local pet = pets.get(player)
    local pet_target = safe(function() return pet:get_target() end)
    if pet_target then
        local a = safe(function() return pet_target:get_guid() end)
        local b = safe(function() return target:get_guid() end)
        if a ~= nil and a == b then
            return false
        end
    end

    last_attack = now
    pcall(function() core.input.set_pet_defensive() end)
    -- core.input.pet_attack(target) takes the target. It was being called with
    -- no argument, inside a pcall, so the pet was never actually sent in and
    -- nothing said so - it only fought what hit it first.
    pcall(function() core.input.pet_attack(target) end)
    return true
end

-- ----------------------------------------------------------------------------
-- MAINTENANCE
-- ----------------------------------------------------------------------------
--- Out-of-combat pet upkeep shared by both classes.
---
--- `spec` supplies the class's spells and rules:
---   summon        spell   cast when there is no pet
---   revive        spell   cast when the pet is dead        (Hunter)
---   heal          spell   cast below heal_pct              (Mend Pet / Health Funnel)
---   heal_ids      table   buff ids proving the heal is already ticking
---   heal_pct      number  threshold, default 50
---   can_summon    fun()   extra gate, e.g. Warlock soul shard check
---   learned       fun(sp) spell-known test from the calling rotation
---   cast_self     fun(sp,label) cast helper from the calling rotation
---   min_level     number  do not try below this (Hunter pets start at 10)
---
--- Returns true when it acted, so the rotation can hold the cascade.
function pets.maintain(player, spec)
    if not player or type(spec) ~= "table" then
        return false
    end
    local learned = spec.learned
    local cast_self = spec.cast_self
    if type(learned) ~= "function" or type(cast_self) ~= "function" then
        return false
    end

    if type(spec.min_level) == "number" then
        local lvl = safe(function() return player:get_level() end)
        if type(lvl) == "number" and lvl < spec.min_level then
            return false
        end
    end

    local exists = pets.exists(player)
    local alive = pets.alive(player)

    -- 1. dead pet -> revive (Hunter). A Warlock has no revive; it re-summons.
    if exists and not alive then
        if spec.revive and learned(spec.revive) then
            state.set_note("Pet", "Reviving pet")
            return cast_self(spec.revive, player, "Revive Pet")
        end
    end

    -- 2. no pet at all -> summon
    if not exists or not alive then
        if spec.summon and learned(spec.summon) then
            if type(spec.can_summon) == "function" and spec.can_summon() ~= true then
                return false
            end
            state.set_note("Pet", "Summoning pet")
            return cast_self(spec.summon, player, spec.summon_label or "Summon Pet")
        end
        return false
    end

    -- 3. wounded pet -> heal, but only if the heal is not already running.
    --    Re-casting a channelled pet heal clips it for no gain.
    if spec.heal and learned(spec.heal) then
        local pct = pets.health_pct(player)
        local threshold = spec.heal_pct or 50
        if type(pct) == "number" and pct < threshold then
            local pet = pets.get(player)
            local ticking = false
            if spec.heal_ids and pet then
                ticking = safe(function() return pet:has_buff(spec.heal_ids) end) == true
            end
            if not ticking then
                state.set_note("Pet", "Healing pet")
                return cast_self(spec.heal, player, spec.heal_label or "Mend Pet")
            end
        end
    end

    return false
end

return pets

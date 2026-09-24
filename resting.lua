-- ============================================================================
-- Master Farmer - Grindbot
-- resting.lua - the eat / drink implementation every rotation drives
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- WHY THIS IS SHARED AND NOT COPIED NINE TIMES
--   Each class owns its resting decision - when to sit down, and at what
--   percentage - but the machinery underneath is identical for all of them and
--   has been wrong three times already: the aura-latency double-drink (1.4.6),
--   the use counter that never reset (1.4.8), and the global cooldown refusing
--   consumables silently (1.4.9). Nine copies means nine places for the next
--   one to hide, so the rules live here and the rotations supply the policy:
--
--       function mage.rest(player)
--           return resting.tick(player, { eat_pct = 30, drink_pct = 30 })
--       end
--
--   A class that wants to rest earlier, later, or not at all changes its own
--   numbers; nothing else has to move.
--
-- WHAT IT GUARANTEES  (carried over unchanged, each one earned)
--   * one consumable at a time, with a 5s commit window covering the delay
--     between using an item and its aura appearing
--   * separate food and drink timers, because both auras run at once in TBC
--   * a per-rest use cap that RE-ARMS when the rest ends
--   * skip_gcd on the item use, because food and drink do not use the global
--     cooldown but use_self_safe gates on it by default
--   * every refusal is reported once per rest instead of stalling in silence
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local consumables = require("data/consumables")
local gui = require("gui")
-- rotation is required LAZILY and deliberately.
--
-- rotation.lua requires the nine class rotations, each of which requires this
-- module, so a top-level require here would close the loop: Lua only records a
-- module in package.loaded after its chunk returns, so a circular require
-- re-enters the half-built chunk instead of getting the finished table.
local rotation_mod = nil

local function get_rotation()
    if rotation_mod then
        return rotation_mod
    end
    local ok, mod = pcall(require, "rotation")
    if ok and type(mod) == "table" then
        rotation_mod = mod
    end
    return rotation_mod
end

--- The class's preferred consumable ids, or nil when it has no opinion.
local function preferred(which, player)
    local rotation = get_rotation()
    if not rotation or type(rotation[which]) ~= "function" then
        return nil
    end
    local ok, ids = pcall(rotation[which], player)
    if ok then
        return ids
    end
    return nil
end
local movement = require("movement")
local state = require("state")

local resting_mod = {}

local FOOD_AURAS = consumables.FOOD_AURA_IDS
local DRINK_AURAS = consumables.DRINK_AURA_IDS
local FOOD_ITEM_RANK = consumables.FOOD_ITEM_IDS
local WATER_ITEM_RANK = consumables.WATER_ITEM_IDS

-- Rest at or below this, unless the rotation says otherwise.
local REST_DEFAULT = 30
local REST_DONE = 100

-- Seconds a use is committed for before another of the same kind is considered.
-- Covers the delay between using the item and its aura becoming visible.
-- Measured against the worst case, not the typical one: a 3s window still
-- double-consumed when the aura took 4.5s to register.
local USE_COMMIT = 5.0
-- Worst-case bound per rest session if aura detection is broken entirely.
local MAX_USES = 8

-- Gates use_self_safe applies by default, and why one of them is turned off.
--
-- use_self_safe refuses while the global cooldown is running. Food and drink
-- do not trigger or respect the GCD in TBC, so that gate is simply wrong for a
-- consumable - and it bites constantly, because a rest is entered the moment a
-- kill finishes, while the rotation's last cast still has the GCD spinning.
--
-- The other gates (usable, cooldown, moving, mounted, casting, channelling)
-- are left on: halt_for_rest has already stopped the bot, and they are real.
local USE_OPTS = { skip_gcd = true }

local food_state  = { last = -1e9, uses = 0, pending = false, warned = false }
local drink_state = { last = -1e9, uses = 0, pending = false, warned = false }
local rest_eat = false
local rest_drink = false
local resting = false
local miss_logged = false
local item_by_id = {}
local path_runner_mod = nil

-- ----------------------------------------------------------------------------
-- DIAGNOSTIC
-- ----------------------------------------------------------------------------
-- Every gate below this point can stop a rest, and most of them were silent.
-- mfg_rest_debug names the one that is actually holding, once per second and
-- only when it changes, so a stalled rest can be read straight off the log
-- instead of guessed at.
local dbg_last_msg, dbg_last_t = nil, -1e9

local function rest_debug(fmt, ...)
    if gui.is_on("rest_debug") ~= true then
        return
    end
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    local t = 0
    local ok, now = pcall(function() return izi.now() end)
    if ok and type(now) == "number" then t = now end
    if msg == dbg_last_msg and (t - dbg_last_t) < 1.0 then
        return
    end
    dbg_last_msg, dbg_last_t = msg, t
    core.log("[Master Farmer - Grindbot] rest: " .. msg)
end

local function pcall_item(id)
    local ok, item = pcall(function() return izi.item(id) end)
    if ok then return item end
    return nil
end

local function item_of(id)
    if type(id) ~= "number" then
        return nil
    end
    local cached = item_by_id[id]
    if cached then
        return cached
    end
    local item = pcall_item(id)
    if item then
        item_by_id[id] = item
    end
    return item
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

-- Prewarm the item cache. Every call is guarded: this runs at module load over
-- ~250 ids, and an unguarded throw on any one of them would abort the whole
-- chunk. main.lua bails out entirely when `healing` is missing, so one bad id
-- would take the whole bot down rather than just one food.
local function prewarm(list)
    for i = 1, #list do
        local id = list[i]
        local item = safe(function() return izi.item(id) end)
        if item then
            item_by_id[id] = item
        end
    end
end
prewarm(FOOD_ITEM_RANK)
prewarm(WATER_ITEM_RANK)

local function as_percent(value, current, maximum)
    if type(value) == "number" then
        if value >= 0 and value <= 1.5 then
            return value * 100
        end
        return value
    end
    if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
        return (current / maximum) * 100
    end
    return 100
end

local function health_pct(player)
    local pct = safe(function() return player:get_health_percentage() end)
    local cur = safe(function() return player:get_health() end)
    local maxh = safe(function() return player:max_health() end)
    return as_percent(pct, cur, maxh)
end

local function mana_pct(player)
    local maxm = safe(function() return player:mana_max() end)
    if type(maxm) == "number" and maxm <= 0 then
        return 100
    end
    local pct = safe(function() return player:mana_pct() end)
    local cur = safe(function() return player:mana_current() end)
    return as_percent(pct, cur, maxm)
end

local function has_any_aura(player, ids)
    if not player then
        return false
    end
    if safe(function() return player:has_buff(ids) end) == true then
        return true
    end
    if safe(function() return player:has_aura(ids) end) == true then
        return true
    end
    return false
end

local function ranked_ids(base, extra)
    local seen = {}
    local out = {}
    local function add(id)
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for i = 1, #base do
        add(base[i])
    end
    if type(extra) == "table" then
        for i = 1, #extra do
            add(extra[i])
        end
    end
    return out
end

local function food_ids(player)
    return ranked_ids(FOOD_ITEM_RANK, preferred("preferred_food_ids", player))
end

local function water_ids(player)
    return ranked_ids(WATER_ITEM_RANK, preferred("preferred_drink_ids", player))
end

local function has_usable(ids)
    if type(ids) ~= "table" then
        return false
    end
    for i = 1, #ids do
        local item = item_of(ids[i])
        if item then
            local count = safe(function() return item:count() end) or 0
            local ready = safe(function() return item:cooldown_up() end) == true
            if count > 0 and ready then
                return true
            end
        end
    end
    return false
end

--- Use the best consumable in `ids`.
---
--- Returns (true) on success, or (false, reason) so the caller can say what
--- went wrong. Before 1.4.9 a refused use returned a bare false and the bot sat
--- in the rest state consuming nothing and logging nothing, for ever - which is
--- indistinguishable from "eating and drinking do not run at all".
local function use_first(ids)
    if type(ids) ~= "table" then
        return false, "no id list"
    end
    local held = 0
    local refused = nil
    for i = 1, #ids do
        local item = item_of(ids[i])
        if item then
            local count = safe(function() return item:count() end) or 0
            local ready = safe(function() return item:cooldown_up() end) == true
            if count > 0 and ready then
                held = held + 1
                local ok = safe(function()
                    return item:use_self_safe("Consume", USE_OPTS)
                end)
                if ok ~= true then
                    -- The guarded call still said no. By this point the bot is
                    -- stationary, unmounted, out of combat and not swimming, so
                    -- the remaining guards have nothing left to protect - try
                    -- the plain use rather than stall the whole rest.
                    ok = safe(function() return item:use_self("Consume") end)
                end
                if ok == true then
                    return true
                end
                refused = refused or (safe(function() return item:name() end) or ids[i])
            end
        end
    end
    if held > 0 then
        return false, string.format("%s is in the bags but the client refused to use it", tostring(refused))
    end
    return false, "nothing usable in the bags"
end

local function get_path_runner()
    if path_runner_mod == false then
        return nil
    end
    if type(path_runner_mod) == "table" then
        return path_runner_mod
    end
    local ok, mod = pcall(require, "path_runner")
    if ok and type(mod) == "table" then
        path_runner_mod = mod
        return path_runner_mod
    end
    path_runner_mod = false
    return nil
end

local function is_moving_now(player)
    if movement and type(movement.is_moving) == "function" and movement.is_moving() then
        return true
    end
    return safe(function() return player:is_moving() end) == true
end

local function halt_for_rest(player)
    pcall(function()
        core.input.stop_attack()
    end)
    pcall(function()
        if type(izi.is_sequence_active) == "function" and izi.is_sequence_active() ~= true then
            return
        end
        if izi.sequence and type(izi.sequence.cancel_all) == "function" then
            izi.sequence:cancel_all()
            return
        end
        if type(izi.cancel_sequence) == "function" then
            izi.cancel_sequence()
        end
    end)
    if movement and type(movement.set_resting) == "function" then
        movement.set_resting(true)
    end
    local pr = get_path_runner()
    if pr and type(pr.is_active) == "function" and pr.is_active() == true then
        if type(pr.pause) == "function" then
            pr.pause()
        end
    end
    if movement and type(movement.nav_stop) == "function" then
        if is_moving_now(player) then
            movement.nav_stop()
        elseif type(movement.nav_stop) == "function" then
            movement.nav_stop()
        end
    end
end

--- One rest of this kind is over: clear its per-rest use budget.
---
--- MAX_USES caps how many consumables a SINGLE rest may burn while waiting for
--- an aura to appear. It is not a lifetime allowance, so it has to be cleared
--- every time the latch drops - on reaching full, on running out of food, and
--- on a hard reset. Before 1.4.8 only the hard reset cleared it, so the counter
--- accumulated across rests and the bot stopped eating and drinking for good
--- after eight consumables.
local function end_kind(st)
    st.uses = 0
    st.pending = false
    st.warned = false
    st.use_failed = nil
end

local function reset_use_state()
    end_kind(food_state)
    end_kind(drink_state)
end

local function clear_rest()
    rest_eat = false
    rest_drink = false
    resting = false
    reset_use_state()
    if movement and type(movement.set_resting) == "function" then
        movement.set_resting(false)
    end
end

local function resource_full(pct)
    return pct >= REST_DONE
end

--- Threshold for this kind, as a percentage.
---
--- Supplied by the calling rotation rather than read from a slider, so a class
--- can rest earlier or later than the default without a second GUI control.
--- Clamped so a bad profile cannot make the bot rest at 0% or at full health.
local function start_pct(opts, key, fallback)
    local n = opts and opts[key]
    if type(n) ~= "number" or n ~= n then
        n = fallback
    end
    if n < 5 then
        n = 5
    end
    if n > 95 then
        n = 95
    end
    return n
end

local function latch_rest(hp, mana, has_mana, eat_at, drink_at)
    if hp <= eat_at then
        rest_eat = true
    elseif resource_full(hp) then
        if rest_eat == true then end_kind(food_state) end
        rest_eat = false
    end
    if has_mana == true and mana <= drink_at then
        rest_drink = true
    elseif resource_full(mana) then
        if rest_drink == true then end_kind(drink_state) end
        rest_drink = false
    end
end

--- Use exactly one consumable of this kind, then leave it alone.
---
--- Order matters. The aura check comes first so a working consumable is never
--- stacked; the commit window comes second so a consumable that is working but
--- has not registered yet is not stacked either. Only when both say "nothing is
--- happening" does another get used.
local function consume_one(st, kind, ids, aura_up, now, aura_list)
    -- 1. It is working. Leave it.
    if aura_up == true then
        st.pending = false
        st.warned = false
        return false
    end

    -- 2. Used recently. The aura may simply not have landed yet.
    if (now - st.last) < USE_COMMIT then
        return false
    end

    -- 3. Committed, waited, and still no aura: the aura ids do not cover this
    --    item. Say so once - silently working through the whole stack at one
    --    item per tick is what this guard exists to prevent.
    if st.pending and not st.warned then
        st.warned = true
        core.log_warning(string.format(
            "[Master Farmer - Grindbot] Used %s but no %s aura appeared within %.1fs. "
            .. "consumables.%s is probably missing this item's aura id - "
            .. "capping at %d uses this rest instead of consuming the stack.",
            kind, kind, USE_COMMIT, aura_list, MAX_USES))
    end

    if st.uses >= MAX_USES then
        return false
    end

    local ok, why = use_first(ids)
    if ok then
        st.last = now
        st.uses = st.uses + 1
        st.pending = true
        rest_debug("used one %s (use %d this rest)", kind, st.uses)
        return true
    end

    -- Nothing was consumed and nothing is on cooldown or committed, so the rest
    -- is stalled. Say so - once per rest, naming the reason.
    if st.use_failed ~= why then
        st.use_failed = why
        core.log_warning(string.format(
            "[Master Farmer - Grindbot] Tried to use %s and nothing happened: %s.", kind, tostring(why)))
    end
    rest_debug("%s blocked - %s", kind, tostring(why))
    return false
end


-- ----------------------------------------------------------------------------
-- PUBLIC
-- ----------------------------------------------------------------------------
--- Is the bot sitting down right now?
function resting_mod.is_resting()
    return resting == true
end

--- Drop every latch. Called when the owner changes or the bot stops.
function resting_mod.clear()
    clear_rest()
end

--- Rest if this character needs to. Returns true while resting, so the caller
--- holds the rest of the tick.
---
--- `opts.eat_pct`   sit and eat at or below this health percentage
--- `opts.drink_pct` sit and drink at or below this mana percentage
--- Both default to REST_DEFAULT.
function resting_mod.tick(player, opts)
    if not player then
        clear_rest()
        return false
    end

    local eat_at = start_pct(opts, "eat_pct", REST_DEFAULT)
    local drink_at = start_pct(opts, "drink_pct", REST_DEFAULT)

    local hp = health_pct(player)
    local mana = mana_pct(player)
    local maxm = safe(function() return player:mana_max() end)
    local has_mana = type(maxm) == "number" and maxm > 0
    local eating = has_any_aura(player, FOOD_AURAS)
    local drinking = has_any_aura(player, DRINK_AURAS)
    local foods = food_ids(player)
    local waters = water_ids(player)
    latch_rest(hp, mana, has_mana, eat_at, drink_at)

    -- Combat ends a rest outright. Potions are handled by healing.lua, which
    -- still owns everything that happens while fighting.
    if safe(function() return player:is_in_combat() end) == true then
        rest_debug("in combat - HP %.0f MP %.0f - resting is suppressed until it ends", hp, mana)
        resting = false
        if movement and type(movement.set_resting) == "function" then
            movement.set_resting(false)
        end
        return false
    end
    if safe(function() return core.character.is_swimming() end) == true then
        rest_debug("swimming - cannot sit down to eat or drink")
        clear_rest()
        return false
    end

    if rest_eat == true and eating ~= true and hp < REST_DONE and has_usable(foods) ~= true then
        end_kind(food_state)
        rest_eat = false
        if miss_logged ~= true then
            miss_logged = true
            core.log_warning("[Master Farmer - Grindbot] Eat/drink skipped - no usable food in bags.")
        end
    end
    if rest_drink == true and drinking ~= true and mana < REST_DONE and has_usable(waters) ~= true then
        end_kind(drink_state)
        rest_drink = false
        if miss_logged ~= true then
            miss_logged = true
            core.log_warning("[Master Farmer - Grindbot] Eat/drink skipped - no usable water in bags.")
        end
    end
    if rest_eat == true or rest_drink == true then
        miss_logged = false
    end

    if rest_eat ~= true and rest_drink ~= true then
        rest_debug("no rest needed - HP %.0f (eat at %.0f) MP %.0f (drink at %.0f)",
            hp, eat_at, mana, has_mana and drink_at or 0)
        if resting then
            reset_use_state()
            if movement and type(movement.set_resting) == "function" then
                movement.set_resting(false)
            end
        end
        resting = false
        return false
    end

    resting = true
    rest_debug("resting - HP %.0f MP %.0f - eat=%s drink=%s - %d food / %d water ids known",
        hp, mana, tostring(rest_eat), tostring(rest_drink), #foods, #waters)
    halt_for_rest(player)
    state.set_note("Rest", string.format("Eating / drinking  HP %.0f  MP %.0f", hp, mana))

    if safe(function() return player:is_mounted() end) == true then
        rest_debug("mounted - dismounting first")
        pcall(function()
            core.input.dismount()
        end)
        return true
    end
    if is_moving_now(player) then
        rest_debug("still moving - waiting for the character to stop")
        return true
    end

    local now = izi.now()

    if rest_eat and hp < REST_DONE then
        consume_one(food_state, "food", foods, eating, now, "FOOD_AURA_IDS")
    end
    if rest_drink and mana < REST_DONE then
        consume_one(drink_state, "drink", waters, drinking, now, "DRINK_AURA_IDS")
    end
    return true
end

return resting_mod

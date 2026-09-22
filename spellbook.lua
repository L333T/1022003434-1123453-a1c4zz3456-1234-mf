-- ============================================================================
-- Master Farmer - Grindbot
-- Spellbook — delayed scan, then auto-rank by name to the highest known ID
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- Wait 5 seconds so the client and IZI finish loading, then scan.
-- Re-scan every 2 seconds. DEFS are rank-1 IDs; highest matching ID wins.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local spellbook = {}

local WAIT_SEC = 5.0
local SCAN_GAP = 2.0
local started_at = izi.now()
local last_scan = 0
local scanned = false
local id_known = {}
local spell_known = {}
local watched = {}
local book_count = 0
local book_ids = {}
local book_names = {}
local defs = {}
local resolved_name = {}
local best_id = {}
local all_ranks = {}
local spells = {}
local generation = 0

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function spell_name(id)
    if type(id) ~= "number" or id <= 0 then
        return nil
    end
    local name = safe(function()
        return core.spell_book.get_spell_name(id)
    end)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function mark_id(id)
    if type(id) == "number" and id > 0 then
        if not id_known[id] then
            id_known[id] = true
            book_count = book_count + 1
        end
    end
end

local function extract_ids(raw)
    local ids = {}
    local seen = {}
    if type(raw) ~= "table" then
        return ids
    end
    local key_hits, val_hits, probes = 0, 0, 0
    for k, v in pairs(raw) do
        if probes >= 12 then
            break
        end
        if type(k) == "number" and spell_name(k) then
            key_hits = key_hits + 1
        end
        if type(v) == "number" and spell_name(v) then
            val_hits = val_hits + 1
        end
        probes = probes + 1
    end
    local use_values = val_hits >= key_hits
    local function add_id(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for k, v in pairs(raw) do
        if use_values then
            add_id(v)
        else
            add_id(k)
        end
        if type(k) == "number" and type(v) == "string" then
            add_id(k)
        end
        if type(v) == "number" and type(k) == "string" then
            add_id(v)
        end
    end
    if #ids == 0 then
        for k, v in pairs(raw) do
            add_id(k)
            add_id(v)
        end
    end
    table.sort(ids)
    return ids
end

local function ingest_book(raw)
    book_ids = extract_ids(raw)
    book_names = {}
    book_count = 0
    id_known = {}
    for i = 1, #book_ids do
        local id = book_ids[i]
        mark_id(id)
        local name = spell_name(id)
        if name then
            book_names[id] = name
        end
    end
end

local function id_in_book(id)
    if type(id) ~= "number" then
        return false
    end
    if id_known[id] then
        return true
    end
    if safe(function() return core.spell_book.has_spell(id) end) == true then
        mark_id(id)
        return true
    end
    if safe(function() return core.spell_book.is_spell_learned(id) end) == true then
        mark_id(id)
        return true
    end
    if safe(function() return core.spell_book.is_spell_known(id) end) == true then
        mark_id(id)
        return true
    end
    return false
end

local function evaluate_spell(spell)
    if type(spell) ~= "table" or not scanned then
        return false
    end
    if spell_known[spell] == true then
        return true
    end
    if safe(function() return spell:is_learned() end) == true then
        spell_known[spell] = true
        return true
    end
    local ids = spell.ids
    if type(ids) == "table" then
        for i = 1, #ids do
            if id_in_book(ids[i]) then
                spell_known[spell] = true
                return true
            end
        end
    end
    local active = safe(function() return spell:id() end)
    if id_in_book(active) then
        spell_known[spell] = true
        return true
    end
    return false
end

local function rank_families()
    for key, seed in pairs(defs) do
        if not resolved_name[key] then
            local n = spell_name(seed)
            if n then
                resolved_name[key] = n
            end
        end
    end
    local changed = false
    for key, seed in pairs(defs) do
        local want = resolved_name[key]
        local ranks = {}
        local seen = {}
        local function consider(id)
            if type(id) ~= "number" or id <= 0 or seen[id] then
                return
            end
            if not id_in_book(id) then
                return
            end
            local name = book_names[id] or spell_name(id)
            local match = false
            if want and name == want then
                match = true
            else
                local base = safe(function()
                    return core.spell_book.get_base_spell_id(id)
                end)
                local seed_base = safe(function()
                    return core.spell_book.get_base_spell_id(seed)
                end)
                if type(base) == "number" and type(seed_base) == "number" and base > 0 and base == seed_base then
                    match = true
                elseif id == seed then
                    match = true
                end
            end
            if match then
                seen[id] = true
                ranks[#ranks + 1] = id
            end
        end
        for i = 1, #book_ids do
            consider(book_ids[i])
        end
        consider(seed)
        table.sort(ranks)
        all_ranks[key] = ranks
        local top = ranks[#ranks]
        if type(top) == "number" and best_id[key] ~= top then
            best_id[key] = top
            local spell = izi.spell(top)
            if spell then
                spells[key] = spell
            end
            changed = true
        end
    end
    if changed then
        generation = generation + 1
    end
end

local function run_scan()
    ingest_book(safe(function()
        return core.spell_book.get_spells()
    end))
    scanned = true
    last_scan = izi.now()
    rank_families()
    for i = 1, #watched do
        evaluate_spell(watched[i])
    end
end

function spellbook.define(map)
    if type(map) ~= "table" then
        return
    end
    for key, id in pairs(map) do
        if type(key) == "string" and type(id) == "number" and id > 0 then
            defs[key] = id
        end
    end
end

function spellbook.watch(spell)
    if type(spell) ~= "table" then
        return spell
    end
    watched[#watched + 1] = spell
    return spell
end

function spellbook.ready()
    return scanned
end

function spellbook.wait_left()
    if scanned then
        return 0
    end
    local left = WAIT_SEC - (izi.now() - started_at)
    if left < 0 then
        return 0
    end
    return left
end

function spellbook.tick()
    local now = izi.now()
    if not scanned then
        if (now - started_at) < WAIT_SEC then
            return false
        end
        run_scan()
        core.log(string.format(
            "[Master Farmer - Grindbot] Spellbook scanned (%d entries, %d rotation spells watched).",
            book_count,
            #watched
        ))
        return true
    end
    if (now - last_scan) < SCAN_GAP then
        return true
    end
    run_scan()
    return true
end

function spellbook.spell_known(spec)
    if not scanned then
        return false
    end
    if type(spec) == "string" then
        return type(best_id[spec]) == "number"
    end
    if type(spec) ~= "table" then
        return false
    end
    if spec.is_learned ~= nil or spec.ids ~= nil then
        return evaluate_spell(spec)
    end
    for i = 1, #spec do
        if evaluate_spell(spec[i]) then
            return true
        end
    end
    return false
end

function spellbook.has(key)
    return type(best_id[key]) == "number"
end

function spellbook.best_id(key)
    return best_id[key]
end

function spellbook.spell(key)
    return spells[key]
end

function spellbook.ranks(key)
    return all_ranks[key]
end

function spellbook.generation()
    return generation
end

return spellbook

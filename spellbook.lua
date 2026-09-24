-- ============================================================================
-- Master Farmer - Grindbot
-- Spellbook — delayed scan, then auto-rank by name to the highest known ID
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
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

-- Every spell the character has, grouped into rank families.
--
-- The scanner already read the whole book to answer the defined keys; it just
-- threw the rest away. Grouping it costs one pass and gives the GUI the thing
-- it actually wants: one row per spell, at the best rank, rather than eleven
-- rows of Frostbolt.
local families = {}        -- array of { id, name, ranks = { id, ... }, category }
local by_category = {}     -- category -> array of families
local families_by_name = {}
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

-- ============================================================================
-- COLLECT EVERY SPELL ID
-- ============================================================================
-- Recursive, and it takes numeric KEYS and numeric VALUES at every depth.
--
-- The previous version probed twelve entries, decided globally whether ids
-- lived in the keys or the values, and then only looked one level down. On the
-- three shapes core.spell_book.get_spells() can actually return that is not
-- enough - measured against a stub, a mixed table lost half the book and a
-- table nested by spell tab lost all of it. Whether the client groups by tab,
-- returns a flat list, or returns a set, this finds the same ids.
--
-- `visited` guards against a cyclic table, which a recursive walk would
-- otherwise follow for ever.
local function collect_ids(value, out, visited)
    if value == nil then
        return
    end

    local t = type(value)
    if t == "number" then
        if value > 0 and value == math.floor(value) then
            out[value] = true
        end
        return
    end
    if t ~= "table" then
        return
    end

    visited = visited or {}
    if visited[value] then
        return
    end
    visited[value] = true

    for k, v in pairs(value) do
        if type(k) == "number" and k > 0 and k == math.floor(k) then
            out[k] = true
        end
        collect_ids(v, out, visited)
    end
end

--- Does the client agree this number is a spell?
---
--- The recursive walk cannot tell a spell id from an array index - a flat list
--- of four spells has keys 1..4, and taking those produced four phantom
--- entries. Rather than trying to out-guess the table shape, every candidate
--- is put to the client: a name, or has_spell, or learned, or known. An id
--- with no name but which the client confirms is still kept, because that was
--- the other half of the original loss.
local function is_real_spell(id)
    if type(id) ~= "number" or id <= 0 then
        return false
    end
    if spell_name(id) then
        return true
    end
    if safe(function() return core.spell_book.has_spell(id) end) == true then
        return true
    end
    if safe(function() return core.spell_book.is_spell_learned(id) end) == true then
        return true
    end
    return safe(function() return core.spell_book.is_spell_known(id) end) == true
end

--- Every id in the book that the client confirms, sorted.
local function extract_ids(raw)
    local set = {}
    collect_ids(raw, set, nil)

    local ids = {}
    for id in pairs(set) do
        if is_real_spell(id) then
            ids[#ids + 1] = id
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

-- ============================================================================
-- Group The Whole Book Into Rank Families
-- ============================================================================
-- Ranks are grouped by base spell id, which is what the client itself uses to
-- say "these are the same spell" - Frostbolt rank 1 and rank 11 share one base
-- id. Name is the fallback for a build where get_base_spell_id is unhelpful,
-- and is also what keeps the grouping right for spells the API returns a base
-- id of 0 for.
--
-- The highest id in a family is taken as the best rank. That is the same
-- assumption rank_families already makes for defined keys, and it holds
-- because Blizzard issues ascending ids per rank within a spell.
--- Which category a family belongs to, via the registered rules.
--- Nothing is guessed from the fact that a spell exists: a family with no
--- matching rule lands in "other" and is still shown.
local function classify(fam)
    local ok, rules = pcall(require, "data/spell_categories")
    if not ok or type(rules) ~= "table" or type(rules.category_of) ~= "function" then
        return "other"
    end
    local cat = safe(function()
        return rules.category_of(fam.id, fam.name)
    end)
    if type(cat) == "string" and cat ~= "" then
        return cat
    end
    return "other"
end

local function group_families()
    families = {}
    families_by_name = {}
    by_category = {}

    local by_key = {}
    local order = {}

    for i = 1, #book_ids do
        local id = book_ids[i]
        -- An id the client will not name still gets a row, labelled by id.
        -- Hiding it is how the list came up short against the spellbook.
        local name = book_names[id] or spell_name(id) or ("Spell " .. tostring(id))
        if name then
            local base = safe(function()
                return core.spell_book.get_base_spell_id(id)
            end)

            -- Key on the base id when the client gives a usable one, on the
            -- name otherwise. Two spells sharing a name but not a base id are
            -- the same family; two sharing neither are not.
            local key
            if type(base) == "number" and base > 0 then
                key = "b" .. tostring(base)
            else
                key = "n" .. name
            end

            local fam = by_key[key]
            if not fam then
                fam = { id = id, name = name, ranks = {} }
                by_key[key] = fam
                order[#order + 1] = fam
            end
            fam.ranks[#fam.ranks + 1] = id
            if id > fam.id then
                fam.id = id
                fam.name = name
            end
        end
    end

    for i = 1, #order do
        local fam = order[i]
        table.sort(fam.ranks)
        fam.category = classify(fam)
        families[#families + 1] = fam
        families_by_name[fam.name] = fam
        local bucket = by_category[fam.category]
        if not bucket then
            bucket = {}
            by_category[fam.category] = bucket
        end
        bucket[#bucket + 1] = fam
    end

    table.sort(families, function(a, b)
        return a.name < b.name
    end)
    for _, list in pairs(by_category) do
        table.sort(list, function(a, b)
            return a.name < b.name
        end)
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
    group_families()
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

-- ============================================================================
-- The Whole Spellbook
-- ============================================================================
--- Every spell the character knows, one entry per rank family, sorted by name.
---
--- Each entry is { id = <best rank id>, name = <string>, ranks = { id, ... } }.
--- The table is rebuilt on every scan, so callers should read it rather than
--- hold it across frames; `generation` tells you when the resolved set moved.
function spellbook.all_families()
    return families
end

--- How many distinct spells the character has, as opposed to how many rank
--- rows the client reported.
function spellbook.family_count()
    return #families
end

--- One family by exact spell name, or nil.
function spellbook.family(name)
    if type(name) ~= "string" then
        return nil
    end
    return families_by_name[name]
end

--- Raw scan totals, for a status line: how many ids the client listed and how
--- many distinct spells that collapsed to.
function spellbook.counts()
    return book_count, #families
end

--- Families of one category, sorted by name.
function spellbook.category(cat)
    return by_category[cat] or {}
end

--- Every category that actually has spells in it, in the registry's order.
function spellbook.categories()
    local ok, rules = pcall(require, "data/spell_categories")
    local order = (ok and type(rules) == "table" and rules.order) or { "other" }
    local out = {}
    for i = 1, #order do
        local cat = order[i]
        local list = by_category[cat]
        if list and #list > 0 then
            out[#out + 1] = { key = cat, label = (ok and rules.label and rules.label(cat)) or cat, spells = list }
        end
    end
    local leftovers = by_category["other"]
    local named = {}
    for i = 1, #order do
        named[order[i]] = true
    end
    if leftovers and #leftovers > 0 and not named["other"] then
        out[#out + 1] = { key = "other", label = "Other", spells = leftovers }
    end
    return out
end

return spellbook

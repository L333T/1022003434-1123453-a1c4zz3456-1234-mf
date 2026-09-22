-- ============================================================================
-- Master Farmer - Grindbot
-- Path profiles — save / load / play PathTool JSON from scripts_data
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- Files live in scripts_data/mfg_profiles/*.json (do not prefix scripts_data/).
-- ============================================================================

local path_format = require("path_format")

local FOLDER = "mfg_profiles"
local SELECTED_FILE = "mfg_profiles/_selected.txt"

local path_profiles = {}

local files = {}
local view = {}
local use_view = false
local last_loaded = nil
local REGION_KEYS = { "ek", "kalimdor", "outland", "custom" }

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function looks_like_json(chunk)
    if type(chunk) ~= "string" or chunk == "" then
        return false
    end
    local i = 1
    while i <= #chunk do
        local c = chunk:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            return c == "{" or c == "["
        end
        i = i + 1
    end
    return false
end

local function join(name)
    return FOLDER .. "/" .. name
end

function path_profiles.folder()
    return FOLDER
end

function path_profiles.ensure_folder()
    pcall(function()
        core.create_data_folder(FOLDER)
    end)
end

local function is_json_name(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    if name:sub(1, 1) == "_" then
        return false
    end
    return name:match("%.json$") ~= nil
end

function path_profiles.refresh()
    files = {}
    local names = safe(function()
        return core.read_dir(FOLDER)
    end)
    if type(names) ~= "table" then
        return files
    end
    for i = 1, #names do
        local name = names[i]
        if is_json_name(name) then
            files[#files + 1] = name
        end
    end
    table.sort(files)
    return files
end

function path_profiles.region_of(filename)
    if type(filename) ~= "string" or filename == "" then
        return "custom"
    end
    local id = filename:gsub("%.json$", "")
    local ok, catalog = pcall(require, "path_catalog")
    if ok and catalog and type(catalog.region_of) == "function" then
        return catalog.region_of(id)
    end
    return "custom"
end

function path_profiles.apply_region(region_index)
    local key = REGION_KEYS[region_index] or "ek"
    view = {}
    use_view = true
    for i = 1, #files do
        if path_profiles.region_of(files[i]) == key then
            view[#view + 1] = files[i]
        end
    end
    return view
end

local function listed()
    if use_view then
        return view
    end
    return files
end

function path_profiles.list()
    return listed()
end

function path_profiles.count()
    return #listed()
end

function path_profiles.labels()
    local src = listed()
    local labels = {}
    for i = 1, #src do
        local name = src[i]
        labels[i] = name:gsub("%.json$", "")
    end
    return labels
end

function path_profiles.file_at(index)
    if type(index) ~= "number" or index < 1 then
        return nil
    end
    return listed()[index]
end

function path_profiles.index_of(filename)
    if type(filename) ~= "string" then
        return 1
    end
    local src = listed()
    for i = 1, #src do
        if src[i] == filename then
            return i
        end
    end
    return 1
end

function path_profiles.read_selected_name()
    local size = safe(function()
        return core.get_data_file_size(SELECTED_FILE)
    end)
    if type(size) ~= "number" or size <= 0 then
        return nil
    end
    local text = safe(function()
        return core.read_data_file(SELECTED_FILE)
    end)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("%s+$", ""):gsub("^%s+", "")
    if text == "" then
        return nil
    end
    return text
end

function path_profiles.set_selected(filename)
    if type(filename) ~= "string" or filename == "" then
        return
    end
    path_profiles.ensure_folder()
    pcall(function()
        core.create_data_file(SELECTED_FILE)
    end)
    pcall(function()
        core.write_data_file(SELECTED_FILE, filename)
    end)
end

function path_profiles.load_file(filename)
    if type(filename) ~= "string" or filename == "" then
        return nil, "no profile selected"
    end
    local rel = join(filename)
    local size = safe(function()
        return core.get_data_file_size(rel)
    end)
    if type(size) ~= "number" or size <= 0 then
        return nil, "profile missing: " .. filename
    end
    local header = safe(function()
        return core.read_data_file_partial(rel, 0, 64)
    end)
    if not looks_like_json(header) then
        return nil, "profile is not JSON: " .. filename
    end
    local raw = safe(function()
        return core.read_data_file(rel)
    end)
    if type(raw) ~= "string" or raw == "" then
        return nil, "failed to read " .. filename
    end
    local path, err = path_format.normalize(raw)
    if not path then
        return nil, err or ("bad path: " .. filename)
    end
    if type(path.id) ~= "string" or path.id == "" then
        path.id = filename:gsub("%.json$", "")
    end
    last_loaded = path
    path_profiles.set_selected(filename)
    return path
end

function path_profiles.save_path(path, filename, opts)
    opts = opts or {}
    local normalized, err = path_format.normalize(path)
    if not normalized then
        return false, err or "cannot save path"
    end
    if type(filename) ~= "string" or filename == "" then
        filename = (normalized.id or "path") .. ".json"
    end
    if not filename:match("%.json$") then
        filename = filename .. ".json"
    end
    filename = filename:gsub("[^%w%._%-]", "_")
    local json, enc_err = path_format.encode_json(normalized)
    if not json then
        return false, enc_err or "json encode failed"
    end
    path_profiles.ensure_folder()
    local rel = join(filename)
    pcall(function()
        core.create_data_file(rel)
    end)
    local ok = pcall(function()
        core.write_data_file(rel, json)
    end)
    if not ok then
        return false, "write failed: " .. filename
    end
    if opts.quiet ~= true then
        last_loaded = normalized
        path_profiles.set_selected(filename)
        path_profiles.refresh()
    end
    return true, filename
end

function path_profiles.last_loaded()
    return last_loaded
end

function path_profiles.remember(path)
    if type(path) == "table" then
        last_loaded = path
    end
end

local function seed_entry(entry)
    if type(entry) ~= "table" or type(entry.module) ~= "string" then
        return false
    end
    local id = entry.id or "path"
    local filename = id .. ".json"
    local rel = join(filename)
    local size = safe(function()
        return core.get_data_file_size(rel)
    end)
    if type(size) == "number" and size > 0 then
        return false
    end
    local raw, err = path_format.take_module(entry.module)
    if not raw or type(raw) ~= "table" then
        return false
    end
    local path, err = path_format.normalize(raw)
    if not path then
        core.log_warning("[Master Farmer - Grindbot] Profile seed skip " .. filename .. ": " .. tostring(err))
        return false
    end
    if type(path.id) ~= "string" or path.id == "" then
        path.id = id
    end
    local saved = path_profiles.save_path(path, filename, { quiet = true })
    return saved == true
end

function path_profiles.seed_one(entry)
    local wrote = seed_entry(entry)
    if wrote then
        path_profiles.refresh()
    end
    return wrote == true
end

function path_profiles.seed_missing()
    local ok, catalog = pcall(require, "path_catalog")
    if not ok or type(catalog) ~= "table" or type(catalog.count) ~= "function" then
        return 0
    end
    local n = catalog.count()
    local wrote = 0
    for i = 1, n do
        local entry = catalog.entry(i)
        if seed_entry(entry) then
            wrote = wrote + 1
        end
    end
    if wrote > 0 then
        core.log("[Master Farmer - Grindbot] Wrote " .. tostring(wrote) .. " path profiles to scripts_data/" .. FOLDER)
    end
    return wrote
end

function path_profiles.prepare()
    path_profiles.ensure_folder()
    path_profiles.refresh()
    return files
end

return path_profiles

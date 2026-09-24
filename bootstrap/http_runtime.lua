-- ============================================================================
-- HTTP runtime — GET the GitHub bot, cache it, compile, run
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.4.0
-- Folder: Master_Farmer_Grindbot_v1.4.0
-- Uses verified core.http_get / scripts_data write/read. Lua loadstring/load
-- compiles cached source (language compile, not a Sylvanas-invented loader).
-- ============================================================================

local json = require("json")

local TAG = "[Master Farmer - Grindbot]"
local RAW_BASE = "https://raw.githubusercontent.com/L333T/1022003434-1123453-a1c4zz3456-1234-mf/main/"
local CACHE_ROOT = "mfg_http"
local HEADERS = {
    ["User-Agent"] = "MasterFarmer-Grindbot/1.4.0",
    ["Accept"] = "application/json, text/plain, */*",
}

local runtime = {}

local STATUS_IDLE = "idle"
local STATUS_FETCH = "fetch"
local STATUS_READY = "ready"
local STATUS_RUN = "running"
local STATUS_FAIL = "failed"

local status = STATUS_IDLE
local status_text = "HTTP runner idle"
local busy = false
local started = false
local retry_at = 0
local retry_n = 0
local manifest = nil
local file_i = 1
local sources = {}
local pending_path = nil

local function now_s()
    if core.time then
        local ok, t = pcall(core.time)
        if ok and type(t) == "number" then
            return t
        end
    end
    return 0
end

local function compile_chunk(source, name)
    if type(source) ~= "string" or source == "" then
        return nil, "empty source"
    end
    local compiler = nil
    if type(_G.loadstring) == "function" then
        compiler = _G.loadstring
    elseif type(_G.load) == "function" then
        compiler = _G.load
    end
    if type(compiler) ~= "function" then
        return nil, "Lua loadstring/load is not available"
    end
    local fn, err = compiler(source, "@" .. tostring(name))
    if type(fn) ~= "function" then
        return nil, tostring(err or "compile failed")
    end
    return fn
end

local function module_name(path)
    if type(path) ~= "string" then
        return nil
    end
    local name = path
    if name:sub(-4) == ".lua" then
        name = name:sub(1, #name - 4)
    end
    return name
end

local function dirname(path)
    if type(path) ~= "string" then
        return nil
    end
    return path:match("^(.*)/[^/]+$")
end

local function ensure_dir(path)
    if type(path) ~= "string" or path == "" then
        return
    end
    local parent = dirname(path)
    if parent then
        ensure_dir(parent)
    end
    pcall(core.create_data_folder, path)
end

local function cache_path(version, rel)
    return CACHE_ROOT .. "/" .. tostring(version) .. "/" .. rel
end

local function write_cache(rel, body)
    if type(rel) ~= "string" or type(body) ~= "string" then
        return false
    end
    local version = (manifest and manifest.version) or "unknown"
    local full = cache_path(version, rel)
    local dir = dirname(full)
    pcall(core.create_data_folder, CACHE_ROOT)
    if dir then
        ensure_dir(dir)
    end
    pcall(core.create_data_file, full)
    pcall(core.write_data_file, full, body)
    return true
end

local function read_cache(version, rel)
    local full = cache_path(version, rel)
    local ok, data = pcall(core.read_data_file, full)
    if ok and type(data) == "string" and #data > 0 then
        return data
    end
    return nil
end

local function set_status(st, text)
    status = st
    status_text = text or st
    core.log(TAG .. " " .. status_text)
end

local function fail(text)
    busy = false
    pending_path = nil
    retry_n = retry_n + 1
    retry_at = now_s() + math.min(30, 4 * retry_n)
    set_status(STATUS_FAIL, text)
end

local function get_url(path)
    return RAW_BASE .. path
end

local function http_get(path, cb)
    if busy then
        return
    end
    busy = true
    pending_path = path
    local url = get_url(path)
    core.http_get(url, HEADERS, function(http_code, content_type, response_data, response_headers)
        busy = false
        pending_path = nil
        cb(http_code, content_type, response_data, response_headers)
    end)
end

local function install_preloads(version, files)
    local n = 0
    for i = 1, #files do
        local path = files[i]
        if path ~= "main.lua" and path ~= "header.lua" then
            local name = module_name(path)
            local src = sources[path] or read_cache(version, path)
            if name and src then
                sources[path] = src
                package.preload[name] = function()
                    local fn, err = compile_chunk(src, path)
                    if not fn then
                        error(err)
                    end
                    return fn()
                end
                n = n + 1
            end
        end
    end
    return n
end

local function run_entry()
    if started then
        return true
    end
    local version = manifest.version or "unknown"
    local files = manifest.files
    if type(files) ~= "table" then
        fail("Manifest has no files list")
        return false
    end
    local entry = manifest.entry or "main.lua"
    local src = sources[entry] or read_cache(version, entry)
    if not src then
        fail("Missing entry " .. entry)
        return false
    end
    local loaded = install_preloads(version, files)
    local fn, err = compile_chunk(src, entry)
    if not fn then
        fail("Compile " .. entry .. ": " .. tostring(err))
        return false
    end
    local ok, run_err = pcall(fn)
    if not ok then
        fail("Run " .. entry .. ": " .. tostring(run_err))
        return false
    end
    started = true
    set_status(STATUS_RUN, "Running GitHub bot v" .. tostring(version) .. " (" .. tostring(loaded) .. " modules)")
    return true
end

local function cache_complete(version, files)
    if type(files) ~= "table" then
        return false
    end
    for i = 1, #files do
        local src = sources[files[i]] or read_cache(version, files[i])
        if not src then
            return false
        end
        sources[files[i]] = src
    end
    return true
end

local function begin_files()
    file_i = 1
    set_status(STATUS_FETCH, "Downloading bot files")
end

local function on_manifest_body(body)
    local obj, err = json.decode(body)
    if type(obj) ~= "table" then
        fail("Bad manifest: " .. tostring(err))
        return
    end
    if type(obj.files) ~= "table" or #obj.files < 1 then
        fail("Manifest files list is empty")
        return
    end
    manifest = obj
    write_cache("manifest.json", body)
    local version = obj.version or "unknown"
    if cache_complete(version, obj.files) then
        set_status(STATUS_READY, "Cached bot v" .. tostring(version))
        run_entry()
        return
    end
    begin_files()
end

local function request_manifest()
    set_status(STATUS_FETCH, "Fetching manifest.json")
    http_get("manifest.json", function(code, _ctype, body, _headers)
        if code ~= 200 or type(body) ~= "string" or #body == 0 then
            local fallback = read_cache("1.3.39", "manifest.json")
            if type(fallback) == "string" and #fallback > 0 then
                on_manifest_body(fallback)
                return
            end
            fail("manifest.json HTTP " .. tostring(code))
            return
        end
        on_manifest_body(body)
    end)
end

local function request_next_file()
    if not manifest or type(manifest.files) ~= "table" then
        return
    end
    local files = manifest.files
    local version = manifest.version or "unknown"
    while file_i <= #files do
        local path = files[file_i]
        local cached = sources[path] or read_cache(version, path)
        if cached then
            sources[path] = cached
            file_i = file_i + 1
        else
            break
        end
    end
    if file_i > #files then
        set_status(STATUS_READY, "Download complete")
        run_entry()
        return
    end
    local path = files[file_i]
    set_status(STATUS_FETCH, string.format("Downloading %d / %d  %s", file_i, #files, path))
    http_get(path, function(code, _ctype, body, _headers)
        if code ~= 200 or type(body) ~= "string" or #body == 0 then
            fail(path .. " HTTP " .. tostring(code))
            return
        end
        sources[path] = body
        write_cache(path, body)
        file_i = file_i + 1
        retry_n = 0
    end)
end

function runtime.status()
    return status, status_text
end

function runtime.running()
    return started
end

function runtime.pulse()
    if started then
        return
    end
    if busy then
        return
    end
    local t = now_s()
    if status == STATUS_FAIL then
        if t < retry_at then
            return
        end
        status = STATUS_IDLE
    end
    if not manifest then
        local cached = read_cache("1.3.39", "manifest.json")
        if type(cached) == "string" and #cached > 0 then
            on_manifest_body(cached)
            if started then
                return
            end
        end
        request_manifest()
        return
    end
    if not started then
        request_next_file()
    end
end

return runtime

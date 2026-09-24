-- ============================================================================
-- Master Farmer - Grindbot
-- net_loader.lua - load the codebase over HTTP with core.http_get
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.0.0
-- ============================================================================
-- WHAT THIS DOES
--   Fetches a remote manifest, fetches every module it lists, compiles each one
--   with load(), and installs the compiled chunks so that a normal
--   require("movement/steer") resolves to the downloaded copy instead of the
--   file on disk.
--
-- THE ONE FACT THAT SHAPES EVERYTHING
--   core.http_get is ASYNCHRONOUS. The callback fires on some later frame, and
--   there is no way to block on it. So you cannot do this:
--
--       local src = http_get_sync(url)        -- does not exist
--       return load(src)()                    -- so this is impossible
--
--   A remote require() cannot be synchronous, which means the bootstrap has to
--   be a small state machine that runs across frames:
--
--       IDLE -> MANIFEST -> FILES -> COMPILE -> READY
--                  |           |         |
--                  +-----------+---------+-> FAILED (fall back to disk)
--
-- WHY package.preload IS THE TRICK
--   Compiling a chunk does not run it. If we compiled and immediately called
--   each chunk we would have to download and execute in dependency order, which
--   means serialising the whole fetch. Instead we install every compiled chunk
--   as a LOADER and let require() pull them in the order the code itself asks
--   for. Download order stops mattering, so all requests can fly in parallel.
--
-- WHAT THIS DOES **NOT** FIX
--   The 200-local-per-function limit. load() runs the same compiler the disk
--   loader does, so a chunk with 235 top-level locals fails identically here:
--       movement.lua: main function has more than 200 local variables
--   Splitting movement.lua was the fix for that. HTTP loading is orthogonal.
--
-- SECURITY
--   This executes code fetched from the network. The hash in the manifest is an
--   INTEGRITY check (catches truncation, proxy mangling, a half-written file on
--   the server); it is NOT an authenticity check, because the manifest travels
--   over the same channel as the files. Anyone who can serve you the manifest
--   can serve you any code they like and it will run with your client's
--   privileges. Only ever point BASE_URL at a host you control, over https.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local TAG = "[MFG/net]"

local cfg = {
    base_url      = nil,    -- e.g. "https://cdn.example.com/mfg/1.3.38/"
    manifest      = "manifest.lua",
    timeout       = 20.0,   -- seconds for the whole fetch before we give up
    retries       = 2,      -- per-file retries on transport failure / 5xx
    max_bytes     = 1024 * 1024,
    verify_hash   = true,
    headers       = nil,    -- optional { ["Authorization"] = "Bearer ..." }
}

-- ============================================================================
-- STATE
-- ============================================================================
local STATE = {
    IDLE     = "idle",
    MANIFEST = "manifest",
    FILES    = "files",
    READY    = "ready",
    FAILED   = "failed",
}

local phase      = STATE.IDLE
local sources    = {}       -- module name -> source string
local entries    = nil      -- manifest entry list
local want, got  = 0, 0
local attempts   = {}       -- module name -> tries so far
local started_t  = 0
local fail_why   = nil
local on_ready   = nil
local cache      = {}       -- module name -> value returned by the chunk

local function log(msg)  core.log(TAG .. " " .. msg) end
local function warn(msg) core.log_warning(TAG .. " " .. msg) end
local function err(msg)  core.log_error(TAG .. " " .. msg) end

-- ============================================================================
-- INTEGRITY  (Adler-32)
-- ============================================================================
-- Not cryptographic. It exists to catch a truncated body, a captive-portal HTML
-- page served with a 200, or a file that was mid-write on the origin.
--
-- Adler-32 and not FNV-1a / CRC32, deliberately:
--   * it is addition-only, so there is no xor operator to worry about. `~` is a
--     SYNTAX error on LuaJIT and 5.1, so a source file containing it will not
--     compile there at all - it cannot be guarded with a runtime check.
--   * every intermediate stays under 2^17, so it is exact in a double. FNV-1a
--     needs `hash * 16777619` with hash up to 2^32, which is 2^56 and silently
--     loses precision in Lua numbers.
--   * Python's zlib.adler32 produces the identical value, so the manifest
--     generator is a one-liner with no re-implementation to keep in sync.
--
-- Cost is one pass per file, paid once at load, spread across frames because
-- each file is hashed in its own completion callback rather than all at once.
local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

M.hash = adler32

-- ============================================================================
-- COMPILE  (5.1 / 5.2+ compatible)
-- ============================================================================
local function compile(src, chunkname)
    if loadstring then return loadstring(src, chunkname) end
    return load(src, chunkname, "t")
end

-- ============================================================================
-- MODULE INSTALLATION
-- ============================================================================
-- Two mechanisms, because a sandboxed host may not expose stock `require`:
--
--   1. package.preload[name] - stock Lua checks this BEFORE searching paths, so
--      an unmodified require() finds our chunk first. Preferred: nothing else
--      in the plugin has to change.
--   2. a require() wrapper - installed only when package.preload is missing.
--      It serves downloaded modules and delegates everything else (izi_sdk,
--      common/*) to the original require.
--
-- Either way the chunk is NOT executed here. It runs the first time something
-- requires it, which is what makes download order irrelevant.
--
-- COMPILED ON DEMAND, NOT UP FRONT (1.7.0)
--   Every file used to be compiled during install and its chunk kept in
--   package.preload for the life of the session. For the 27 grind routes that
--   is a large, permanent cost that lazy loading never touched: dropping a
--   route from package.loaded frees the waypoint TABLE, but the chunk that
--   builds it stayed resident regardless.
--
--   Measured on those 27 routes: 795 KB held as compiled chunks against 545 KB
--   held as source, so compiling on demand and letting the chunk go saves
--   250 KB and costs one compile the first time a module is required.
--
--   Every file is still compile-CHECKED during install, so a syntax error
--   still aborts the swap-over rather than surfacing hours later. The check
--   discards its chunk; only the source is kept.
local installed = false

local function install_modules()
    if installed then return true end

    local names = {}
    for name in pairs(sources) do names[#names + 1] = name end
    table.sort(names)

    -- Compile-check everything first: a syntax error should abort the swap-over
    -- rather than leave half the plugin remote and half on disk. The chunk is
    -- thrown away immediately - only the source is kept, and the real compile
    -- happens when the module is first required. See the note above.
    for i = 1, #names do
        local name = names[i]
        local chunk, cerr = compile(sources[name], "@" .. name .. ".lua")
        if not chunk then
            err("compile failed for " .. name .. ": " .. tostring(cerr))
            return false, "compile:" .. name
        end
        chunk = nil
    end
    collectgarbage("step", 400)

    --- Compile `name` from its source and run it. The chunk is local, so once
    --- this returns the only thing still referenced is whatever the module
    --- itself returned.
    local function build(name)
        local src = sources[name]
        if not src then return nil, "no source" end
        local chunk, cerr = compile(src, "@" .. name .. ".lua")
        if not chunk then
            err("compile failed for " .. name .. ": " .. tostring(cerr))
            return nil, tostring(cerr)
        end
        return chunk(name)
    end

    if type(package) == "table" and type(package.preload) == "table" then
        for i = 1, #names do
            local name = names[i]
            package.preload[name] = function()
                local value = build(name)
                if value == nil then value = true end
                return value
            end
        end
        log("installed " .. #names .. " modules into package.preload (compiled on demand)")
    else
        local base_require = require
        local function net_require(name)
            if cache[name] ~= nil then return cache[name] end
            if not sources[name] then return base_require(name) end
            local ok, value = pcall(build, name)
            if not ok then
                err("module " .. name .. " raised: " .. tostring(value))
                error(value, 0)
            end
            if value == nil then value = true end
            cache[name] = value
            return value
        end
        _G.require = net_require
        log("installed " .. #names .. " modules via require wrapper (compiled on demand)")
    end

    installed = true
    return true
end

-- ============================================================================
-- FETCH
-- ============================================================================
local function finish_ok()
    phase = STATE.READY
    log(string.format("ready: %d modules in %.1fs", got, izi.now() - started_t))
    if on_ready then
        local cb = on_ready
        on_ready = nil
        pcall(cb, true)
    end
end

local function finish_fail(why)
    if phase == STATE.FAILED then return end
    phase, fail_why = STATE.FAILED, why
    err("load failed (" .. tostring(why) .. ") - falling back to on-disk modules")
    if on_ready then
        local cb = on_ready
        on_ready = nil
        pcall(cb, false, why)
    end
end

--- Classify a completed request. Returns "ok" | "retry" | "fatal".
local function classify(http_code, content_type, body)
    -- Transport failure (DNS, TLS, refused, timeout) is reported as code 0.
    if http_code == 0 then return "retry", "transport" end
    if http_code == 429 or (http_code >= 500 and http_code <= 599) then
        return "retry", "http " .. http_code
    end
    if http_code ~= 200 then return "fatal", "http " .. http_code end
    if type(body) ~= "string" or #body == 0 then return "retry", "empty body" end
    if #body > cfg.max_bytes then return "fatal", "oversize" end
    -- A captive portal or an error page answers 200 with HTML. Lua source never
    -- starts with a doctype or a tag, so this is a cheap, reliable sanity gate.
    local head = body:sub(1, 64):lower()
    if head:find("<!doctype", 1, true) or head:find("<html", 1, true) then
        return "fatal", "html body (portal or error page?)"
    end
    if type(content_type) == "string" and content_type:lower():find("text/html", 1, true) then
        return "fatal", "content-type text/html"
    end
    return "ok"
end

local function get(url, cb)
    if type(cfg.headers) == "table" then
        core.http_get(url, cfg.headers, cb)
    else
        core.http_get(url, cb)
    end
end

local fetch_one   -- forward declaration

local function on_file(name, entry, http_code, content_type, body)
    if phase ~= STATE.FILES then return end          -- aborted or timed out

    local verdict, why = classify(http_code, content_type, body)

    if verdict == "retry" then
        attempts[name] = (attempts[name] or 0) + 1
        if attempts[name] <= cfg.retries then
            warn(name .. ": " .. why .. " - retry " .. attempts[name] .. "/" .. cfg.retries)
            fetch_one(name, entry)
            return
        end
        return finish_fail(name .. ": " .. why .. " (retries exhausted)")
    end
    if verdict == "fatal" then
        return finish_fail(name .. ": " .. why)
    end

    if cfg.verify_hash and entry.hash then
        local actual = adler32(body)
        if actual ~= entry.hash then
            return finish_fail(string.format("%s: hash %s, expected %s (corrupt or stale)",
                name, actual, entry.hash))
        end
    end

    sources[name] = body
    got = got + 1
    if got < want then return end

    local ok, iwhy = install_modules()
    if not ok then return finish_fail(iwhy) end
    finish_ok()
end

fetch_one = function(name, entry)
    local url = cfg.base_url .. entry.path
    get(url, function(http_code, content_type, body, _headers)
        on_file(name, entry, http_code, content_type, body)
    end)
end

-- ============================================================================
-- MANIFEST
-- ============================================================================
-- The manifest is a Lua chunk, not JSON, for one reason: there is no guaranteed
-- JSON decoder in this environment, and load() is already required for the
-- modules. It must `return` a table:
--
--   return {
--       version = "2.2.0",
--       files = {
--           { path = "movement/const.lua",  hash = "1a2b3c4d" },
--           { path = "movement/rt.lua",     hash = "5e6f7a8b" },
--           ...
--       },
--   }
--
-- `path` is relative to base_url; the module name is the path minus ".lua".
local function on_manifest(http_code, content_type, body)
    if phase ~= STATE.MANIFEST then return end

    local verdict, why = classify(http_code, content_type, body)
    if verdict ~= "ok" then
        return finish_fail("manifest: " .. tostring(why))
    end

    local chunk, cerr = compile(body, "@manifest.lua")
    if not chunk then return finish_fail("manifest parse: " .. tostring(cerr)) end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" or type(data.files) ~= "table" then
        return finish_fail("manifest shape")
    end

    entries = {}
    for i = 1, #data.files do
        local e = data.files[i]
        if type(e) == "table" and type(e.path) == "string" then
            -- reject traversal and absolute paths before they reach a URL
            if not e.path:find("%.%.") and not e.path:find("^[/\\]") then
                local name = e.path:gsub("%.lua$", "")
                entries[#entries + 1] = { name = name, path = e.path, hash = e.hash }
            else
                return finish_fail("manifest: bad path " .. e.path)
            end
        end
    end

    want, got = #entries, 0
    if want == 0 then return finish_fail("manifest is empty") end

    log(string.format("manifest %s: %d modules", tostring(data.version or "?"), want))
    phase = STATE.FILES

    -- Every request goes out on this frame. They complete in whatever order the
    -- network decides; package.preload makes that order irrelevant.
    for i = 1, #entries do
        local e = entries[i]
        attempts[e.name] = 0
        fetch_one(e.name, e)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================
-- Keys that may start as nil still have to be writable (base_url, headers).
local CFG_KEYS = {
    base_url    = true,
    manifest    = true,
    timeout     = true,
    retries     = true,
    max_bytes   = true,
    verify_hash = true,
    headers     = true,
}

--- Override any of: base_url, manifest, timeout, retries, max_bytes,
--- verify_hash, headers.
function M.configure(opts)
    if type(opts) ~= "table" then return end
    for k, v in pairs(opts) do
        if CFG_KEYS[k] then
            cfg[k] = v
        end
    end
end

--- Begin the fetch. `callback(ok, why)` fires once, on a later frame.
--- Returns false when the loader could not even start.
function M.start(callback)
    if phase == STATE.FILES or phase == STATE.MANIFEST then return false end
    if type(cfg.base_url) ~= "string" or cfg.base_url == "" then
        err("base_url is not configured")
        return false
    end
    if not cfg.base_url:find("^https://") then
        err("base_url must be https")
        return false
    end
    if type(core.http_get) ~= "function" then
        err("core.http_get is unavailable in this build")
        return false
    end
    if cfg.base_url:sub(-1) ~= "/" then cfg.base_url = cfg.base_url .. "/" end

    sources, attempts, cache = {}, {}, {}
    entries, fail_why, installed = nil, nil, false
    want, got = 0, 0
    on_ready = callback
    started_t = izi.now()
    phase = STATE.MANIFEST

    log("fetching " .. cfg.base_url .. cfg.manifest)
    get(cfg.base_url .. cfg.manifest, on_manifest)
    return true
end

--- Call once per frame while loading. The HTTP API has no timeout callback, so
--- a request that never completes would otherwise hang the bootstrap forever.
function M.pulse()
    if phase ~= STATE.MANIFEST and phase ~= STATE.FILES then return end
    if (izi.now() - started_t) < cfg.timeout then return end
    finish_fail(string.format("timeout after %.0fs (%d/%d modules)", cfg.timeout, got, want))
end

function M.is_ready()   return phase == STATE.READY end
function M.is_failed()  return phase == STATE.FAILED end
function M.is_loading() return phase == STATE.MANIFEST or phase == STATE.FILES end

function M.status()
    return {
        phase   = phase,
        got     = got,
        want    = want,
        elapsed = phase == STATE.IDLE and 0 or (izi.now() - started_t),
        reason  = fail_why,
    }
end

--- Source of a fetched module, for diagnostics.
function M.source(name) return sources[name] end

return M

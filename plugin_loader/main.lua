-- ============================================================================
-- Master Farmer - Grindbot  ::  HTTP PLUGIN LOADER
-- main.lua - download the bot, then hand off to its real main.lua
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Loader version: 1.1.0
-- ============================================================================
-- FLOW
--   frame 1      issue the manifest request
--   frames 2..n  pulse() enforces the deadline and re-issues queued retries
--   on success   adopt the downloaded identity, then require("main")
--   on failure   log loudly and stop ticking. There is no fallback, because
--                this folder contains no bot code to fall back to.
--
-- HOW THE HANDOFF WORKS
--   http_loader puts every downloaded module into package.preload, which stock
--   require() consults BEFORE searching the filesystem. So require("main")
--   resolves to the DOWNLOADED main.lua, not to this file. The downloaded
--   main.lua ends by registering its own update and render callbacks, so it
--   wires itself up simply by being required.
--
-- THE RECURSION HAZARD
--   If the remote main.lua were absent from the manifest, require("main") would
--   fall through to the filesystem and re-execute THIS file, starting another
--   load, forever. source("main") is checked first: it is non-nil only if the
--   module genuinely arrived, so the require is only ever issued when it is
--   guaranteed to hit the downloaded copy.
--
-- THE SESSION HANDOVER
--   The bot's main.lua guards its callbacks with is_stale(), comparing a
--   captured value against NS._sessions[identity.folder], where identity comes
--   from the bot's own version.lua. Normally the bot's header.lua bumps that
--   counter - but the bot's header.lua never runs here; this loader's header
--   runs instead.
--
--   So we bump it ourselves, reading the folder key from the DOWNLOADED
--   version.lua rather than from a hardcoded guess. Hardcoding it is what broke
--   the previous loader: the string drifted, and a drifted key breaks the guard
--   silently, leaving stale callbacks running after every reload.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local net = require("http_loader")

-- ============================================================================
-- SOURCE
-- ============================================================================
-- THE LOADER FOLLOWS THE BRANCH. IT IS NOT PINNED ANY MORE.  (2.0.1)
--
--   It used to hold a hardcoded commit SHA, which meant every new version
--   needed this file re-uploaded as well. When that did not happen the plugin
--   silently kept loading the old commit - it had been serving v1.3.38 while
--   the repository was 29 commits further on, and every reported "nothing has
--   changed" was that, not the change failing.
--
--   The reason it was pinned is still real: raw.githubusercontent caches
--   branch URLs for a few minutes and does not invalidate every path at the
--   same instant, so fetching by branch can hand back a fresh manifest.lua
--   beside a stale cached module, the hash check fails, and the load aborts.
--
--   So the branch is resolved to a commit FIRST, and every file is then
--   fetched from that immutable commit URL. One request buys both properties:
--   always current, and a consistent snapshot.
--
--   GitHub answers a commit lookup with the bare 40-character SHA when asked
--   for the sha media type, so no JSON parsing is involved.
local REPO   = "L333T/90123-12333-44a-asd32r1f324fg-3f3fqwf-mf"
-- main, because that is the repository's default branch and where the pull
-- requests from dev are merged. Merging a PR is therefore what publishes a
-- release; pushing to dev alone does not change what the game loads.
--
-- Change this to "dev" if you would rather every push go live immediately.
local BRANCH = "main"

-- Used only when the branch cannot be resolved - no network, API rate limit,
-- GitHub down. Loading a known-good older build beats loading nothing, and the
-- log says plainly that it happened.
-- Kept current deliberately. The previous value was a v1.3.38 commit, so on
-- any lookup failure the plugin quietly dropped 29 versions instead of missing
-- only the newest one.
local FALLBACK_SHA = "a8da92ce29eeb03013374e81696193dd6f3d9772"

local REF_URL = "https://api.github.com/repos/" .. REPO .. "/commits/" .. BRANCH

local function base_for(sha)
    return "https://raw.githubusercontent.com/" .. REPO .. "/" .. sha .. "/"
end

-- Resolved at load time by resolve_branch below.
local SHA = nil
local BASE = nil

-- Optional. Only needed if the repo is private; the token then ships inside
-- this file, so scope it read-only to this one repo.
--   local HEADERS = { ["Authorization"] = "Bearer github_pat_..." }
local HEADERS = nil

local TAG = "[MFG-HTTP]"

-- ============================================================================
-- SESSION GUARD  (the loader's own)
-- ============================================================================
_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot
local LOADER_KEY = (NS._loader and NS._loader.key) or "MFG_HTTP_LOADER"

NS._sessions = NS._sessions or {}
if type(NS._sessions[LOADER_KEY]) ~= "number" then
    NS._sessions[LOADER_KEY] = 1
end
local MY_SESSION = NS._sessions[LOADER_KEY]

local function is_stale()
    return NS._sessions[LOADER_KEY] ~= MY_SESSION
end

-- ============================================================================
-- STATE
-- ============================================================================
local started     = false
local handed_off  = false
local last_report = 0

-- ============================================================================
-- HANDOFF
-- ============================================================================
--- Bump the bot's own session counter using the key from the DOWNLOADED
--- version.lua, standing in for the bot's header.lua, which never ran.
local function adopt_identity()
    local ok, identity = pcall(require, "version")

    -- Be specific about which way this failed. The three causes need three
    -- different fixes, and a single vague warning sent us guessing once already.
    if not ok then
        core.log_error(TAG .. " require('version') failed: " .. tostring(identity))
        core.log_error(TAG .. " the host did not resolve a downloaded module. If the"
            .. " log above says 'require wrapper', this is a loader bug; otherwise a"
            .. " host plugin-scoped require is shadowing package.preload.")
        return nil
    end
    if type(identity) ~= "table" then
        core.log_error(TAG .. " require('version') returned a " .. type(identity)
            .. ", expected a table")
        return nil
    end
    if type(identity.folder) ~= "string" then
        core.log_error(TAG .. " require('version') returned a table with no 'folder'"
            .. " field (name=" .. tostring(identity.name) .. ", version="
            .. tostring(identity.version) .. ")")
        core.log_error(TAG .. " another plugin almost certainly has a module called"
            .. " 'version' cached in package.loaded, and it shadowed ours.")
        return nil
    end

    NS.meta = {
        name        = identity.name,
        version     = identity.version,
        author      = identity.authors or identity.author,
        description = identity.description,
    }
    NS._sessions[identity.folder] = (NS._sessions[identity.folder] or 0) + 1
    return identity
end

local function hand_off()
    if handed_off then return end

    -- Only require("main") when the downloaded copy provably exists, otherwise
    -- require would fall through to this very file and recurse.
    if not net.source("main") then
        core.log_error(TAG .. " the manifest delivered no main.lua - refusing to "
            .. "require (it would re-enter this loader)")
        handed_off = true
        return
    end

    handed_off = true

    local identity = adopt_identity()

    package.loaded["main"] = nil
    local ok, e = pcall(require, "main")
    if not ok then
        core.log_error(TAG .. " downloaded main.lua failed: " .. tostring(e))
        return
    end

    core.log(string.format("%s handed off to %s v%s", TAG,
        identity and identity.name or "the bot",
        identity and identity.version or tostring(net.status().version)))
end

-- ============================================================================
-- BRANCH RESOLUTION
-- ============================================================================
-- Asks GitHub which commit the branch points at, once, before anything is
-- downloaded. Asynchronous like every other request here, so the update tick
-- waits on `resolve_state` rather than blocking.
local resolve_state = "idle"      -- idle | asking | done | failed

local function resolve_branch(done)
    if resolve_state ~= "idle" then
        return
    end
    resolve_state = "asking"

    -- The sha media type returns the bare commit id as the body. A User-Agent
    -- is required by the GitHub API and the request is rejected without one.
    local headers = {
        ["Accept"] = "application/vnd.github.sha",
        ["User-Agent"] = "MasterFarmer-Grindbot",
    }
    if type(HEADERS) == "table" then
        for k, v in pairs(HEADERS) do
            headers[k] = v
        end
    end

    local ok = pcall(function()
        core.http_get(REF_URL, headers, function(http_code, _, body)
            local code = tonumber(http_code) or 0
            local sha = nil
            if code == 200 and type(body) == "string" then
                sha = body:match("^%s*(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x"
                    .. "%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)%s*$")
            end

            if sha then
                SHA = sha
                BASE = base_for(sha)
                resolve_state = "done"
                core.log(string.format("%s %s@%s resolves to %s", TAG, REPO, BRANCH, sha:sub(1, 8)))
            else
                SHA = FALLBACK_SHA
                BASE = base_for(FALLBACK_SHA)
                resolve_state = "failed"
                core.log_warning(string.format(
                    "%s could not resolve %s@%s (http %s); falling back to the pinned commit %s. "
                    .. "The plugin will load, but it will be whatever that commit was.",
                    TAG, REPO, BRANCH, tostring(http_code), FALLBACK_SHA:sub(1, 8)))
            end
            done()
        end)
    end)

    if not ok then
        SHA = FALLBACK_SHA
        BASE = base_for(FALLBACK_SHA)
        resolve_state = "failed"
        core.log_warning(TAG .. " branch lookup could not be sent; using the pinned commit.")
        done()
    end
end

-- ============================================================================
-- PER-FRAME
-- ============================================================================
local function on_update()
    if is_stale() then return end
    if handed_off then return end        -- the bot drives itself from here

    -- Resolve the branch before anything else. The callback re-enters this
    -- function on a later tick with BASE set.
    if resolve_state == "idle" then
        resolve_branch(function() end)
        return
    end
    if resolve_state == "asking" then
        return
    end

    if not started then
        started = true
        net.configure({
            base_url    = BASE,
            timeout     = 30.0,
            retries     = 2,
            verify_hash = true,
            headers     = HEADERS,
        })
        core.log(string.format("%s loading %s@%s from commit %s", TAG, REPO, BRANCH, SHA:sub(1, 8)))

        local ok = net.start(function(loaded, why)
            if is_stale() then return end
            if loaded then
                hand_off()
            else
                core.log_error(TAG .. " load failed: " .. tostring(why))
                core.log_error(TAG .. " the commit resolved fine, so check that "
                    .. "manifest.lua was regenerated and pushed with the rest of "
                    .. "the files on " .. BRANCH)
                handed_off = true        -- stop ticking; nothing more to try
            end
        end)

        if not ok then
            core.log_error(TAG .. " could not start the load")
            handed_off = true
        end
        return
    end

    -- Enforces the deadline (the HTTP API has no timeout callback) and
    -- re-issues queued retries.
    net.pulse()

    local t = izi.now()
    if (t - last_report) >= 2.0 then
        last_report = t
        local s = net.status()
        if s.phase == "manifest" or s.phase == "files" then
            core.log(string.format("%s %s: %d/%d (%.0fs)", TAG, s.phase, s.got, s.want, s.elapsed))
        end
    end
end

core.register_on_update_callback(on_update)

core.log(TAG .. " armed")

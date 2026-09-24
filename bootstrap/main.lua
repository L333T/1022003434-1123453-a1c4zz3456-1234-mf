-- ============================================================================
-- Master Farmer - Grindbot  ::  NETWORK BOOTSTRAP
-- main.lua - fetch the codebase from GitHub, then hand off to the real main
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- FLOW
--   frame 1      start the fetch (manifest, then all modules in parallel)
--   frames 2..n  net.pulse() enforces the deadline; progress is logged
--   on success   install compiled chunks, then require("main") -> the REAL
--                main.lua runs and registers its own callbacks
--   on failure   log loudly and go idle. There is deliberately no fallback,
--                because this folder contains no plugin code to fall back TO.
--
-- HOW THE HANDOFF ACTUALLY WORKS
--   net_loader puts every downloaded module into package.preload. Stock require
--   checks package.preload BEFORE searching the filesystem, so require("main")
--   resolves to the DOWNLOADED main.lua rather than to this file. We clear
--   package.loaded["main"] first in case the host already cached this chunk
--   under that name.
--
--   The downloaded main.lua ends with core.register_on_update_callback(...) and
--   core.register_on_render_callback(...), so it wires itself up as a side
--   effect of being required. Nothing else is needed here.
--
-- THE RECURSION HAZARD, AND THE GUARD
--   If the remote main.lua were missing from the manifest, require("main") could
--   fall through to the filesystem and re-execute THIS file, which would start
--   another fetch, and so on. `net.source("main")` is checked first: it returns
--   the downloaded source only if the module genuinely arrived, so the require
--   is only ever issued when it is guaranteed to hit the remote copy.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local net = require("net_loader")

-- ============================================================================
-- WHERE THE CODE COMES FROM
-- ============================================================================
-- Pinned to a commit SHA, not to `main`, on purpose. raw.githubusercontent
-- caches branch URLs for a few minutes and does NOT invalidate every path at
-- the same instant, so a branch URL can hand you a fresh manifest.lua alongside
-- a stale cached module - the hash check then fails and the whole load aborts.
-- A commit URL is immutable, so that mixed state is impossible.
--
-- To ship an update: push, run `git rev-parse HEAD`, paste the SHA here.
local REPO = "L333T/1022003434-1123453-a1c4zz3456-1234-mf"
local SHA  = "fd51ba60deacc652086fc1bd6cb2b09eddd67d83"

local BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. SHA .. "/"

local TAG = "[Master Farmer - Grindbot]"

-- ============================================================================
-- SESSION GUARD
-- ============================================================================
-- Same mechanism the real main.lua uses. header.lua bumped the counter; we
-- capture it here. If the plugin is reloaded, header runs again, the counter
-- moves, and THIS load's callback goes quiet instead of racing the new one.
_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot
local identity = NS._bootstrap_identity or { folder = "Master_Farmer_Grindbot_v1.3.39", version = "1.3.39" }

NS._sessions = NS._sessions or {}
if type(NS._sessions[identity.folder]) ~= "number" then
    NS._sessions[identity.folder] = 1
end
local MY_SESSION = NS._sessions[identity.folder]

local function is_stale()
    return NS._sessions[identity.folder] ~= MY_SESSION
end

-- ============================================================================
-- STATE
-- ============================================================================
local started    = false
local handed_off = false
local last_report = 0

-- ============================================================================
-- HANDOFF
-- ============================================================================
local function hand_off()
    if handed_off then return end

    -- Guard described above: only require("main") when we KNOW the remote copy
    -- was delivered, so the call cannot fall through to this file.
    if not net.source("main") then
        core.log_error(TAG .. " manifest delivered no main.lua - refusing to require (would re-enter the bootstrap)")
        handed_off = true
        return
    end

    handed_off = true
    package.loaded["main"] = nil

    local ok, e = pcall(require, "main")
    if not ok then
        core.log_error(TAG .. " remote main.lua failed: " .. tostring(e))
        return
    end
    core.log(TAG .. " handed off to remote main.lua")
end

-- ============================================================================
-- PER-FRAME
-- ============================================================================
local function on_update()
    if is_stale() then return end
    if handed_off then return end          -- the real main drives itself now

    if not started then
        started = true
        net.configure({
            base_url    = BASE,
            timeout     = 30.0,
            retries     = 2,
            verify_hash = true,
        })
        core.log(TAG .. " loading v" .. tostring(identity.version) .. " from " .. REPO .. " @ " .. SHA:sub(1, 8))
        if not net.start(function(ok, why)
            if is_stale() then return end
            if ok then
                hand_off()
            else
                core.log_error(TAG .. " network load failed: " .. tostring(why))
                core.log_error(TAG .. " plugin is idle. Check the SHA, the repo URL, and that the commit is pushed.")
            end
        end) then
            core.log_error(TAG .. " could not start the network load")
            handed_off = true              -- nothing more to do; stop ticking
        end
        return
    end

    -- Drives the load deadline. The HTTP API has no timeout callback, so a
    -- request that never completes would otherwise hang the bootstrap forever.
    net.pulse()

    -- throttled progress, so a slow link shows something instead of silence
    local t = izi.now()
    if (t - last_report) >= 2.0 then
        last_report = t
        local s = net.status()
        if s.phase == "files" or s.phase == "manifest" then
            core.log(string.format("%s fetching: %s %d/%d (%.0fs)", TAG, s.phase, s.got, s.want, s.elapsed))
        end
    end
end

core.register_on_update_callback(on_update)

core.log(TAG .. " network bootstrap armed")

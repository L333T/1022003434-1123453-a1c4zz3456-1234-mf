-- ============================================================================
-- Master Farmer - Grindbot  ::  NETWORK BOOTSTRAP
-- header.lua - load gate (local checks only)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.39
-- Folder: Master_Farmer_Grindbot_v1.3.39
-- ============================================================================
-- This is the header for the THIN LOADER plugin, not for the plugin itself.
-- Drop this folder into your Sylvanas plugins directory as its own plugin; it
-- pulls everything else from GitHub at runtime.
--
-- WHY THIS FILE CANNOT TALK TO THE NETWORK
--   Sylvanas reads `plugin.load` from the value this chunk RETURNS, which means
--   the decision has to be made synchronously, right now. core.http_get is
--   asynchronous and its callback fires on a later frame, so there is no way to
--   consult the remote from here - not with a spin-wait, not with a coroutine.
--   Every gate below is therefore a purely local check, exactly as the shipped
--   header.lua does. The remote is contacted for the first time in main.lua.
--
-- WHY THE IDENTITY IS INLINE
--   The real header.lua does `require("version")`. That is impossible here:
--   version.lua lives in the repo and has not been downloaded yet when this
--   runs. The values below MUST stay byte-identical to the remote version.lua,
--   because `folder` is the key for the session-generation guard that main.lua
--   uses to silence callbacks from a previous load. If they drift, a reload
--   leaves two live update callbacks fighting each other.
-- ============================================================================

local identity = {
    name        = "Master Farmer - Grindbot",
    short_tag   = "MFG",
    description = "Intelligent fully AFK WoW leveling bot",
    authors     = "BLIZZ - Anthonyk",
    author      = "BLIZZ - Anthonyk",
    version     = "1.3.39",
    folder      = "Master_Farmer_Grindbot_v1.3.39",
}

local plugin = {}
plugin["name"] = identity.name
plugin["short_tag"] = identity.short_tag
plugin["version"] = identity.version
plugin["author"] = identity.authors
plugin["load"] = true

local local_player = core.object_manager.get_local_player()
if not local_player or not local_player:is_valid() then
    plugin["load"] = false
    return plugin
end

if core.get_game_version() ~= "Tbc" then
    plugin["load"] = false
    return plugin
end

-- The bootstrap is useless without HTTP, so fail here rather than loading and
-- then sitting idle forever with no explanation.
if type(core.http_get) ~= "function" then
    core.log_error("[Master Farmer - Grindbot] core.http_get is unavailable - network loader cannot run.")
    plugin["load"] = false
    return plugin
end

local izi_ok, izi = pcall(require, "common/izi_sdk")
if (not izi_ok) or type(izi) ~= "table" then
    core.log_error("[Master Farmer - Grindbot] common/izi_sdk is unavailable - plugin not loaded.")
    plugin["load"] = false
    return plugin
end

local required_izi = {
    "on_update",
    "spell",
    "item",
    "enemies",
    "me",
    "now",
}
local missing = {}
for i = 1, #required_izi do
    local field = required_izi[i]
    if type(izi[field]) ~= "function" then
        missing[#missing + 1] = field
    end
end
if #missing > 0 then
    core.log_error("[Master Farmer - Grindbot] izi_sdk missing: " .. table.concat(missing, ", "))
    plugin["load"] = false
    return plugin
end

_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot
NS.meta = {
    name = identity.name,
    version = identity.version,
    author = identity.authors,
    description = identity.description,
}

-- Session generation. Bumping this is what makes the PREVIOUS load's update and
-- render callbacks go quiet (see is_stale in main.lua). The downloaded main.lua
-- reads the same counter under the same folder key, so the handed-off plugin
-- inherits the guard correctly.
NS._sessions = NS._sessions or {}
NS._sessions[identity.folder] = (NS._sessions[identity.folder] or 0) + 1

-- Handed to the bootstrap main.lua so it does not have to restate any of this.
NS._bootstrap_identity = identity

return plugin

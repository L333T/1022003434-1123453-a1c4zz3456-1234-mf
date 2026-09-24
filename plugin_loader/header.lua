-- ============================================================================
-- Master Farmer - Grindbot  ::  HTTP PLUGIN LOADER
-- header.lua - load gate
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Loader version: 1.1.0   (this is the LOADER's version, not the bot's - the
--                          bot's version is whatever the manifest reports)
-- ============================================================================
-- This is a standalone plugin whose only job is to download the real plugin.
-- Install this folder on its own; do not install it alongside a local copy of
-- the bot, or two update callbacks will drive the same character.
--
-- WHY NOTHING HERE TOUCHES THE NETWORK
--   Sylvanas reads `plugin.load` from the value this chunk RETURNS, so the
--   decision must be made synchronously. core.http_get is asynchronous and its
--   callback fires on a later frame - there is no spin-wait and no coroutine
--   trick that changes that. Every gate below is therefore local. The first
--   request is issued from main.lua.
--
-- WHY THERE IS NO INLINED COPY OF THE BOT'S IDENTITY
--   An earlier version of this loader hardcoded the bot's `folder` string so it
--   could bump the shared session counter that the bot's own main.lua uses for
--   its is_stale() guard. That string then drifted from the downloaded
--   version.lua, and a drifted key breaks the guard SILENTLY: the bot watches a
--   counter nobody increments, so on reload the previous load's callbacks never
--   go quiet and stack up instead.
--
--   So this loader keeps its own counter under its own key, and main.lua bumps
--   the bot's real key AFTER version.lua has been downloaded and can be read.
--   There is nothing left to keep in sync by hand.
-- ============================================================================

local LOADER_KEY     = "MFG_HTTP_LOADER"
local LOADER_VERSION = "1.1.0"

local plugin = {}
plugin["name"]      = "Master Farmer - Grindbot (HTTP)"
plugin["short_tag"] = "MFG-HTTP"
plugin["version"]   = LOADER_VERSION
plugin["author"]    = "BLIZZ - Anthonyk"
plugin["load"]      = true

local function refuse(msg)
    if msg then core.log_error("[MFG-HTTP] " .. msg) end
    plugin["load"] = false
    return plugin
end

local local_player = core.object_manager.get_local_player()
if not local_player or not local_player:is_valid() then
    return refuse(nil)                       -- not in world yet; silent
end

if core.get_game_version() ~= "Tbc" then
    return refuse(nil)                       -- wrong client; silent
end

-- Without HTTP this plugin can do literally nothing, so refuse here rather than
-- loading and then sitting idle with no explanation.
if type(core.http_get) ~= "function" then
    return refuse("core.http_get is unavailable in this build - cannot load over HTTP.")
end

local izi_ok, izi = pcall(require, "common/izi_sdk")
if (not izi_ok) or type(izi) ~= "table" then
    return refuse("common/izi_sdk is unavailable - plugin not loaded.")
end

local required_izi = { "on_update", "spell", "item", "enemies", "me", "now" }
local missing = {}
for i = 1, #required_izi do
    if type(izi[required_izi[i]]) ~= "function" then
        missing[#missing + 1] = required_izi[i]
    end
end
if #missing > 0 then
    return refuse("izi_sdk missing: " .. table.concat(missing, ", "))
end

_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot

-- The loader's OWN session generation. Bumping it is what makes the previous
-- load's update callback go quiet. This key is private to the loader and is
-- deliberately NOT the bot's folder key.
NS._sessions = NS._sessions or {}
NS._sessions[LOADER_KEY] = (NS._sessions[LOADER_KEY] or 0) + 1

NS._loader = {
    key     = LOADER_KEY,
    version = LOADER_VERSION,
}

return plugin

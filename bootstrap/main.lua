-- ============================================================================
-- Master Farmer - Grindbot
-- Main — HTTP runner
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.4.0
-- Folder: Master_Farmer_Grindbot_v1.4.0
-- Pulls the GitHub bot with core.http_get and runs cached main.lua.
-- ============================================================================

package.loaded["json"] = nil
package.loaded["http_runtime"] = nil
package.loaded["version"] = nil

---@type izi_api
local izi = require("common/izi_sdk")

---@type color
local color = require("common/color")

---@type vec2
local vec2 = require("common/geometry/vector_2")

---@type plugin_helper
local plugin_helper = require("common/utility/plugin_helper")

local identity = require("version")
local runtime = require("http_runtime")

_G.MasterFarmer_Grindbot = _G.MasterFarmer_Grindbot or {}
local NS = _G.MasterFarmer_Grindbot
NS.meta = NS.meta or {
    name = identity.name,
    version = identity.version,
    author = identity.authors,
}
NS._sessions = NS._sessions or {}
if type(NS._sessions[identity.folder]) ~= "number" then
    NS._sessions[identity.folder] = 1
end
local MY_SESSION = NS._sessions[identity.folder]

local function is_stale()
    return NS._sessions[identity.folder] ~= MY_SESSION
end

core.log(string.format("[Master Farmer - Grindbot] v%s HTTP runner ready", identity.version))

core.register_on_update_callback(function()
    if is_stale() then
        return
    end
    if not runtime.running() then
        pcall(function()
            izi.on_update()
        end)
        runtime.pulse()
    end
end)

core.register_on_render_callback(function()
    if is_stale() then
        return
    end
    if runtime.running() then
        return
    end
    local _, text = runtime.status()
    local screen = core.graphics.get_screen_size()
    local pos = vec2.new(24, 72)
    if screen and screen.x then
        pos = vec2.new(24, screen.y * 0.12)
    end
    plugin_helper:draw_text_message(
        tostring(text or "HTTP runner"),
        color.new(248, 226, 132, 255),
        color.new(0, 0, 0, 160),
        pos,
        vec2.new(520, 40),
        false,
        true,
        "mfg_http_runner_status",
        nil,
        true,
        3
    )
end)

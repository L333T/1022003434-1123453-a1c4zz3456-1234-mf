-- ============================================================================
-- Master Farmer - Grindbot
-- Config accessors — thin pass-through to the GUI
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================
-- This file previously also carried `config.KEY_MAP`, a table of the original
-- bot's Chinese `Easy_Data` setting names mapped onto this project's GUI keys.
-- It was string data, not logic: nothing in this codebase ever read it, no
-- module requires config.lua, and `Easy_Data` appears nowhere here.
--
-- The mapping is preserved, with an English gloss for every key, in
-- docs/SOURCE_TRANSLATION.md section 5. It is kept there rather than here
-- because the Chinese side is the *lookup key* - it cannot be translated in
-- place without destroying the only thing the table is for. If legacy Chinese
-- config files ever need importing, rebuild the table from that document.
-- ============================================================================

local gui = require("gui")

local config = {}

function config.is_on(key)
    return gui.is_on(key)
end

function config.slider(key, fallback)
    return gui.slider(key, fallback)
end

function config.mode()
    return gui.mode()
end

return config

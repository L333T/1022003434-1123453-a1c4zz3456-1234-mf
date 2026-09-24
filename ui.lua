-- ============================================================================
-- Reusable Sylvanas Menu UI
-- ============================================================================
-- Configuration-driven window framework for Project Sylvanas plugins.
-- Uses only verified core.menu.window / core.menu.* / assets_helper APIs.
-- Consuming projects supply name, logo, tabs, controls, and theme overrides.
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

---@type color
local color = require("common/color")

---@type vec2
local vec2 = require("common/geometry/vector_2")

---@type enums
local enums = require("common/enums")

---@type assets_helper
local assets_helper = require("common/utility/assets_helper")

---@type izi_api
local izi = require("common/izi_sdk")
local spellbook = require("spellbook")

-- Shared BLIZZ pack. Register once at file scope — never inside a render callback.
-- The PS zip stores files under an inner mf_assets/ folder:
--   mf_assets/logo.png
--   mf_assets/ManlineSlabs-pgPVy.otf
-- Virtual path is pack folder + zip entry. mf_assets\logo.png is NOT an entry
-- and assets_helper logs ERR "missing entry in zip pack" if we request it.
local ASSETS_FOLDER = "mf_assets"
local ASSETS_URL = "ps/1789782531580V1HQ-mf_assets.zip"
local ASSETS_ZIP_FILE = "mf_assets.zip"
local LOGO_VIRTUAL = "mf_assets\\mf_assets\\logo.png"
local FONT_VIRTUAL = "mf_assets\\mf_assets\\ManlineSlabs-pgPVy.otf"

pcall(function()
    assets_helper:register_zip_pack(ASSETS_FOLDER, ASSETS_URL, ASSETS_ZIP_FILE)
end)

local ui = {}

local WE = enums.window_enums
local FONT_SMALL = WE.font_id.FONT_SMALL
local FONT_NORMAL = WE.font_id.FONT_NORMAL
local FONT_BIG = WE.font_id.FONT_BIG

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------

local function col(r, g, b, a)
    return color.new(r, g, b, a or 255)
end

function ui.default_theme()
    return {
        bg_window        = col(10, 12, 18, 245),
        bg_header        = col(8, 10, 16, 255),
        bg_panel         = col(14, 16, 24, 230),
        bg_panel_alt     = col(18, 20, 28, 230),
        bg_nav           = col(12, 14, 22, 240),
        bg_tab           = col(20, 24, 34, 230),
        bg_tab_hover     = col(28, 34, 48, 255),
        bg_tab_active    = col(24, 52, 92, 255),
        bg_input         = col(16, 18, 26, 255),
        bg_row           = col(16, 18, 26, 180),
        bg_row_hover     = col(22, 26, 36, 220),

        border_window    = col(176, 138, 58, 230),
        border_panel     = col(132, 102, 42, 190),
        border_header    = col(204, 164, 72, 240),
        border_tab       = col(70, 90, 130, 200),

        text_primary     = col(232, 222, 196, 255),
        text_secondary   = col(168, 158, 128, 230),
        text_header      = col(248, 226, 132, 255),
        text_dim         = col(118, 112, 96, 200),
        text_on          = col(90, 210, 110, 255),
        text_off         = col(210, 78, 78, 255),

        accent           = col(64, 176, 220, 255),
        accent_active    = col(90, 198, 236, 255),
        accent_hover     = col(110, 188, 230, 255),

        button_start     = col(32, 118, 48, 255),
        button_start_hi  = col(48, 150, 64, 255),
        button_pause     = col(176, 138, 28, 255),
        button_pause_hi  = col(210, 168, 42, 255),
        button_stop      = col(156, 36, 36, 255),
        button_stop_hi   = col(190, 50, 50, 255),
        button_neutral   = col(42, 46, 58, 255),
        button_neutral_hi = col(58, 64, 80, 255),

        success          = col(80, 200, 90, 255),
        warning          = col(220, 176, 56, 255),
        danger           = col(210, 70, 70, 255),

        font             = FONT_NORMAL,
        font_small       = FONT_SMALL,
        font_big         = FONT_BIG,
        font_title       = WE.font_id.FONT_SEMI_BIG or FONT_BIG,
        font_section     = FONT_NORMAL,

        header_font_size = 18,
        section_font_size = 18,
        normal_font_size = 16,
        small_font_size  = 15,

        left_margin      = 21,
        top_margin       = 14,
        header_height    = 136,
        footer_height    = 39,
        nav_height       = 39,
        nav_width        = 147,
        panel_gap        = 16,
        control_gap      = 7,
        section_gap      = 14,
        control_width    = 368,
        row_height       = 35,
        button_height    = 39,
        border_thickness = 1.0,
        rounding         = 5.0,
    }
end

local function copy_theme(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

local function apply_theme_overrides(base, overrides)
    if type(overrides) ~= "table" then
        return base
    end
    for k, v in pairs(overrides) do
        base[k] = v
    end
    return base
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function size_of(win, text)
    local sz = safe(function()
        return win:get_text_size(text)
    end)
    if sz and type(sz.x) == "number" then
        return sz
    end
    return vec2.new(#tostring(text or "") * 7, 16)
end

local function size_of_font(win, font, font_size, text)
    if type(font_size) == "number" and font_size > 0 then
        local sz = safe(function()
            return win:get_text_size_custom(font, font_size, text)
        end)
        if sz and type(sz.x) == "number" then
            return sz
        end
    end
    return size_of(win, text)
end

local function key_display_name(code)
    if type(code) ~= "number" or code <= 0 then
        return "Unbound"
    end
    if code >= 997 and code <= 1005 then
        return "Numpad " .. tostring(code - 996)
    end
    if code == 1006 then
        return "Numpad 0"
    end
    if code >= 96 and code <= 105 then
        if code == 96 then
            return "Numpad 0"
        end
        return "Numpad " .. tostring(code - 96)
    end
    return "Key " .. tostring(code)
end

local function draw_text(win, font, pos, colr, text, font_size)
    if type(text) ~= "string" or text == "" then
        return
    end
    if type(font_size) == "number" and font_size > 0 then
        local ok = pcall(function()
            win:render_text_custom_size(font, pos, colr, font_size, text)
        end)
        if ok then
            return
        end
    end
    win:render_text(font, pos, colr, text)
end

local function draw_rect(win, pmin, pmax, fill, border, rounding, thickness)
    local r = rounding or 4.0
    win:render_rect_filled(pmin, pmax, fill, r)
    if border then
        win:render_rect(pmin, pmax, border, r, thickness or 1.0)
    end
end

local function hovered(win, pmin, pmax)
    return win:is_mouse_hovering_rect(pmin, pmax) == true
end

local function clicked(win, pmin, pmax)
    if win:is_rect_clicked(pmin, pmax) then
        pcall(function()
            win:is_mouse_hovering_rect_block_movement(pmin, pmax)
        end)
        return true
    end
    return false
end

local function block_drag(win, pmin, pmax)
    pcall(function()
        win:is_mouse_hovering_rect_block_movement(pmin, pmax)
    end)
end

local function resolve_bool(elem)
    if not elem then
        return false
    end
    local state = safe(function()
        return elem:get_state()
    end)
    if type(state) == "boolean" then
        return state
    end
    state = safe(function()
        return elem:get()
    end)
    return state == true
end

local function resolve_number(elem, fallback)
    if not elem then
        return fallback
    end
    local value = safe(function()
        return elem:get()
    end)
    if type(value) == "number" then
        return value
    end
    return fallback
end

local function resolve_text(elem)
    if not elem then
        return ""
    end
    local text = safe(function()
        return elem:get_text()
    end)
    if type(text) == "string" then
        return text
    end
    text = safe(function()
        return elem:get()
    end)
    if type(text) == "string" then
        return text
    end
    return ""
end

local function set_bool(elem, value)
    if not elem then
        return
    end
    pcall(function()
        elem:set(value == true)
    end)
end

local function call_value(value)
    if type(value) == "function" then
        local result = safe(value)
        if result == nil then
            return ""
        end
        return tostring(result)
    end
    if value == nil then
        return ""
    end
    return tostring(value)
end

-- ---------------------------------------------------------------------------
-- Custom font / logo from mf_assets ZIP (assets_helper auto-download).
-- Logo: load_local_data -> load_texture -> core.graphics.draw_texture(..., true)
-- inside window:begin. Screen-space top_left = window:get_position() + header offset.
-- Do not use draw_local_texture here — that helper draws the background layer, so
-- logo.png lands on the game screen instead of the GUI window.
-- Font: load_local_data -> core.graphics.load_font. Never cache a failed load.
-- Empty data means the ZIP is still landing — retry next frame.
-- ---------------------------------------------------------------------------

local _assets_logged = false

local function looks_like_html(data)
    if type(data) ~= "string" or data == "" then
        return false
    end
    local prefix = string.lower(string.sub(data, 1, 80))
    if string.find(prefix, "<!doctype", 1, true) then
        return true
    end
    if string.find(prefix, "<html", 1, true) then
        return true
    end
    return false
end

local function usable_bytes(data)
    if type(data) ~= "string" or data == "" then
        return false
    end
    if looks_like_html(data) then
        return false
    end
    return true
end

local function resolve_pack_path(path)
    local normalized = string.gsub(path or "", "/", "\\")
    if normalized == "mf_assets\\logo.png" then
        return LOGO_VIRTUAL
    end
    if normalized == "mf_assets\\ManlineSlabs-pgPVy.otf" then
        return FONT_VIRTUAL
    end
    if normalized == "" then
        return LOGO_VIRTUAL
    end
    return normalized
end

local function pack_path_list(path)
    return { resolve_pack_path(path) }
end

local function load_pack_bytes(path)
    local list = pack_path_list(path)
    for i = 1, #list do
        local candidate = list[i]
        local data = safe(function()
            return assets_helper:load_local_data(candidate, "")
        end)
        if usable_bytes(data) then
            return data
        end
        data = safe(function()
            return izi.load_local_data(candidate, "")
        end)
        if usable_bytes(data) then
            return data
        end
        data = safe(function()
            return core.read_data_file(candidate)
        end)
        if usable_bytes(data) then
            return data
        end
        data = safe(function()
            return core.read_data_file(string.gsub(candidate, "\\", "/"))
        end)
        if usable_bytes(data) then
            return data
        end
    end
    return nil
end

local function load_custom_font(path, size)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    if type(size) ~= "number" or size <= 0 then
        return nil
    end
    local data = load_pack_bytes(path)
    if not data then
        return nil
    end
    local font_id = safe(function()
        return core.graphics.load_font(data, size)
    end)
    if type(font_id) == "number" and font_id ~= 0 then
        return font_id
    end
    return nil
end

local function log_assets_once()
    if _assets_logged then
        return
    end
    local zip_size = safe(function()
        return core.get_data_file_size(ASSETS_ZIP_FILE)
    end) or 0
    local hashed_size = safe(function()
        return core.get_data_file_size("1789782531580V1HQ-mf_assets.zip")
    end) or 0
    local listing = safe(function()
        return core.read_dir(ASSETS_FOLDER)
    end)
    local listed = "-"
    if type(listing) == "table" then
        listed = table.concat(listing, ",")
    end
    local logo = load_pack_bytes(LOGO_VIRTUAL)
    local font = load_pack_bytes(FONT_VIRTUAL)
    if zip_size == 0 and hashed_size == 0 and not logo and not font and listed == "-" then
        return
    end
    _assets_logged = true
    core.log(string.format(
        "[MFG] assets zip=%s hashed=%s dir=%s logo=%s font=%s",
        tostring(zip_size),
        tostring(hashed_size),
        listed,
        tostring(logo and #logo or 0),
        tostring(font and #font or 0)
    ))
end

-- ---------------------------------------------------------------------------
-- Instance
-- ---------------------------------------------------------------------------

local Menu = {}
Menu.__index = Menu

function ui.new(config)
    config = config or {}
    local self = setmetatable({}, Menu)

    self.config = config
    self.id = config.id or "sylvanas_ui_window"
    self.name = config.name or "Project"
    self.version = config.version or "1.0"
    self.subtitle = config.subtitle or ""
    self.logo = config.logo or LOGO_VIRTUAL
    self.logo_width = config.logo_width or 280
    self.logo_height = config.logo_height or 64
    self.header_text = config.header_text or ""
    self.font_path = config.font or config.font_path or FONT_VIRTUAL
    self.footer = config.footer or ""
    self.nav_style = config.nav or "top"

    local size_w, size_h = 828, 621
    if type(config.size) == "table" then
        size_w = config.size.w or config.size.x or size_w
        size_h = config.size.h or config.size.y or size_h
    end
    local pos_x, pos_y = 80, 180
    if type(config.position) == "table" then
        pos_x = config.position.x or pos_x
        pos_y = config.position.y or pos_y
    end

    self.width = size_w
    self.height = size_h

    self.theme = apply_theme_overrides(copy_theme(ui.default_theme()), config.theme)
    self._font_title_id = nil
    self._font_section_id = nil
    self._next_font_try = 0
    self._logo_tex = nil
    self._next_logo_try = 0
    self._ever_open = false

    self.window = core.menu.window(self.id)
    self.window:set_initial_size(vec2.new(size_w, size_h))
    self.window:set_initial_position(vec2.new(pos_x, pos_y))
    self.window:set_visibility(true)
    pcall(function()
        self.window:set_corner_rounding(self.theme.rounding or 4.0)
    end)

    self.tab_store = core.menu.slider_int(1, 32, 1, self.id .. "_active_tab")
    self.elements = {}
    self.order = {}
    self.tabs = {}
    self.tab_draw = {}
    self.status_items = config.status or {}
    self.actions = config.actions or {}
    self.header_hints = config.header_hints or {}
    self.on_close = config.on_close
    self.visible = true
    self._closed = false
    self._tab_scroll = {}
    self._scroll_drag = nil
    self.popups = {}
    self._player_class_id = nil
    self.tools_popup_active = false
    self._dd_open = {}
    self._dd_scroll = {}

    if type(config.tabs) == "table" then
        for i = 1, #config.tabs do
            local tab = config.tabs[i]
            if type(tab) == "table" and tab.id then
                self.tabs[#self.tabs + 1] = {
                    id = tab.id,
                    label = tab.label or tab.id,
                }
            elseif type(tab) == "string" then
                self.tabs[#self.tabs + 1] = { id = tab, label = tab }
            end
        end
    end

    return self
end

function Menu:retry_font()
    if type(self.font_path) ~= "string" or self.font_path == "" then
        return
    end
    if self._font_title_id and self._font_section_id then
        return
    end
    local now = core.time()
    if type(now) == "number" and now < (self._next_font_try or 0) then
        return
    end
    self._next_font_try = (type(now) == "number" and now or 0) + 0.50

    local title_size = self.theme.header_font_size or 18
    local section_size = self.theme.section_font_size or 18
    if not self._font_title_id then
        local loaded_title = load_custom_font(self.font_path, title_size)
        if loaded_title then
            self._font_title_id = loaded_title
            self.theme.font_title = loaded_title
        end
    end
    if not self._font_section_id then
        local loaded_section = load_custom_font(self.font_path, section_size)
        if loaded_section then
            self._font_section_id = loaded_section
            self.theme.font_section = loaded_section
        end
    end
end

---Cache a GPU texture from ZIP / scripts_data bytes. Failures are not sticky.
function Menu:ensure_logo()
    if self._logo_tex and type(self._logo_tex.id) == "number" then
        return self._logo_tex
    end
    local now = core.time()
    if type(now) == "number" and now < (self._next_logo_try or 0) then
        return nil
    end
    self._next_logo_try = (type(now) == "number" and now or 0) + 0.50

    local bytes = load_pack_bytes(resolve_pack_path(self.logo))
    if type(bytes) ~= "string" then
        return nil
    end

    local tex_id, w, h = nil, nil, nil
    local ok = pcall(function()
        tex_id, w, h = core.graphics.load_texture(bytes)
    end)
    if ok and type(tex_id) == "number" then
        self._logo_tex = {
            id = tex_id,
            w = (type(w) == "number" and w > 0) and w or self.logo_width,
            h = (type(h) == "number" and h > 0) and h or self.logo_height,
        }
        return self._logo_tex
    end
    return nil
end

---Draw logo.png on the current window draw list, not the screen background.
---core.graphics.draw_texture always takes a screen-space top_left; is_for_window
---true only selects the window draw list. Header lx/ly are window-local, so they
---must be offset by win:get_position() or the PNG appears on the game screen.
function Menu:draw_logo_texture(win, lx, ly, dw, dh)
    if type(dw) ~= "number" or type(dh) ~= "number" or dw < 1 or dh < 1 then
        return false
    end
    log_assets_once()

    local logo = self:ensure_logo()
    if not logo or type(logo.id) ~= "number" then
        return false
    end

    local sx, sy = lx, ly
    local origin = safe(function()
        return win:get_position()
    end)
    if origin and type(origin.x) == "number" and type(origin.y) == "number" then
        sx = origin.x + lx
        sy = origin.y + ly
    end

    local pos = vec2.new(sx, sy)
    local tint = color.white(255)
    local ok = pcall(function()
        core.graphics.draw_texture(logo.id, pos, dw, dh, tint, true)
    end)
    return ok == true
end

local function store_element(self, kind, id, element, opts)
    opts = opts or {}
    local record = {
        kind = kind,
        id = id,
        element = element,
        label = opts.label or id,
        tooltip = opts.tooltip,
        tab = opts.tab,
        min = opts.min,
        max = opts.max,
        items = opts.items,
        width = opts.width,
        style = opts.style,
        on_click = opts.on_click,
        column = opts.column or 1,
        class_id = opts.class_id,
        race_id = opts.race_id,
        spell = opts.spell,
        skip_draw = opts.skip_draw == true,
    }
    self.elements[id] = record
    self.order[#self.order + 1] = record
    return element
end

function Menu:checkbox(id, default_value, opts)
    opts = opts or {}
    local element = core.menu.checkbox(default_value == true, id)
    return store_element(self, "checkbox", id, element, opts)
end

function Menu:slider_int(id, min_value, max_value, default_value, opts)
    opts = opts or {}
    opts.min = min_value
    opts.max = max_value
    local element = core.menu.slider_int(min_value, max_value, default_value, id)
    return store_element(self, "slider_int", id, element, opts)
end

function Menu:slider_float(id, min_value, max_value, default_value, opts)
    opts = opts or {}
    opts.min = min_value
    opts.max = max_value
    local element = core.menu.slider_float(min_value, max_value, default_value, id)
    return store_element(self, "slider_float", id, element, opts)
end

function Menu:text_input(id, save_input, opts)
    opts = opts or {}
    local element = core.menu.text_input(id, save_input ~= false)
    return store_element(self, "text_input", id, element, opts)
end

function Menu:combobox(id, default_index, items, opts)
    opts = opts or {}
    opts.items = items or {}
    local element = core.menu.combobox(default_index or 1, id)
    return store_element(self, "combobox", id, element, opts)
end

function Menu:keybind(id, default_key, initial_toggle, opts)
    opts = opts or {}
    local element = core.menu.keybind(default_key, initial_toggle == true, id)
    return store_element(self, "keybind", id, element, opts)
end

function Menu:button(id, opts)
    opts = opts or {}
    local element = core.menu.button(id)
    return store_element(self, "button", id, element, opts)
end

function Menu:element(id)
    local record = self.elements[id]
    return record and record.element or nil
end

function Menu:get(id)
    local record = self.elements[id]
    if not record or not record.element then
        return nil
    end
    if record.kind == "checkbox" or record.kind == "keybind" then
        return resolve_bool(record.element)
    end
    if record.kind == "text_input" then
        return resolve_text(record.element)
    end
    return resolve_number(record.element, nil)
end

function Menu:set(id, value)
    local record = self.elements[id]
    if not record or not record.element then
        return
    end
    if record.kind == "checkbox" then
        set_bool(record.element, value)
        return
    end
    pcall(function()
        record.element:set(value)
    end)
end

function Menu:set_combobox_items(id, items)
    local record = self.elements[id]
    if not record then
        return
    end
    record.items = items or {}
    pcall(function()
        record.element:set_items(record.items)
    end)
end

function Menu:on_tab(tab_id, fn)
    self.tab_draw[tab_id] = fn
end

function Menu:set_player_class(class_id)
    if type(class_id) == "number" then
        self._player_class_id = class_id
    end
end

--- Racials are per race, so a racial control carries race_id the same way a
--- class spell carries class_id. Without this every race's racials would show
--- on every character.
function Menu:set_player_race(race_id)
    if type(race_id) == "number" then
        self._player_race_id = race_id
    end
end

function Menu:player_race()
    return self._player_race_id
end

function Menu:player_class()
    return self._player_class_id
end

function Menu:control_visible(record)
    if type(record) ~= "table" then
        return false
    end
    if record.tab == nil then
        return false
    end
    if type(record.class_id) == "number" then
        if self._player_class_id ~= record.class_id then
            return false
        end
    end
    if type(record.race_id) == "number" then
        if self._player_race_id ~= record.race_id then
            return false
        end
    end
    if record.spell ~= nil then
        if not spellbook.ready() then
            return false
        end
        if not spellbook.spell_known(record.spell) then
            return false
        end
    end
    return true
end

---Themed child window (Barney popup-window pattern). Unique id per plugin version.
function Menu:add_popup(spec)
    spec = spec or {}
    if type(spec.id) ~= "string" or spec.id == "" then
        return nil
    end
    local width = spec.w or spec.width or 420
    local height = spec.h or spec.height or 480
    local px = spec.x or 870
    local py = spec.y or 48
    local win_id = self.id .. "_popup_" .. spec.id
    local win = core.menu.window(win_id)
    win:set_initial_size(vec2.new(width, height))
    -- Sub-window position is relative to the parent window.
    win:set_initial_position(vec2.new(px, py))
    pcall(function()
        win:set_visibility(false)
    end)
    pcall(function()
        win:set_corner_rounding(self.theme.rounding or 4.0)
    end)
    local popup = {
        id = spec.id,
        title = spec.title or spec.id,
        tab = spec.tab or spec.id,
        width = width,
        height = height,
        window = win,
        open = false,
        ever_open = false,
        on_open = spec.on_open,
    }
    self.popups[#self.popups + 1] = popup
    return popup
end

function Menu:find_popup(id)
    for i = 1, #self.popups do
        if self.popups[i].id == id then
            return self.popups[i]
        end
    end
    return nil
end

function Menu:open_popup(id)
    local popup = self:find_popup(id)
    if not popup then
        return
    end
    popup.open = true
    pcall(function()
        popup.window:set_visibility(true)
    end)
    pcall(function()
        popup.window:set_focus()
    end)
    if type(popup.on_open) == "function" then
        pcall(popup.on_open)
    end
end

function Menu:close_popup(id)
    local popup = self:find_popup(id)
    if not popup then
        return
    end
    popup.open = false
    pcall(function()
        popup.window:set_visibility(false)
    end)
end

function Menu:close_popups()
    for i = 1, #self.popups do
        local popup = self.popups[i]
        popup.open = false
        pcall(function()
            popup.window:set_visibility(false)
        end)
    end
end

function Menu:is_popup_open(id)
    local popup = self:find_popup(id)
    return popup ~= nil and popup.open == true
end

---Example-style hover/click rect, painted with the BLIZZ gold theme.
function Menu:draw_launcher(win, x, y, w, h, label)
    local t = self.theme
    local pmin = vec2.new(x, y)
    local pmax = vec2.new(x + w, y + h)
    local is_hover = hovered(win, pmin, pmax)
    local fill = is_hover and t.bg_tab_hover or t.bg_tab
    local border = is_hover and t.border_header or t.border_panel
    draw_rect(win, pmin, pmax, fill, border, t.rounding, 1.0)
    local text = label or ""
    local sz = size_of_font(win, t.font_small, t.small_font_size, text)
    draw_text(
        win,
        t.font_small,
        vec2.new(x + math.floor((w - sz.x) * 0.5), y + math.floor((h - sz.y) * 0.5)),
        t.text_header,
        text,
        t.small_font_size
    )
    block_drag(win, pmin, pmax)
    return clicked(win, pmin, pmax)
end

---Themed dropdown (custom window; core.menu.combobox does not paint inside these popups).
function Menu:draw_dropdown(win, id, x, y, width, label, items, index)
    items = items or {}
    if type(index) ~= "number" or index < 1 then
        index = 1
    end
    if #items > 0 and index > #items then
        index = #items
    end
    self._dd_open = self._dd_open or {}
    self._dd_scroll = self._dd_scroll or {}
    local t = self.theme
    local now = izi.now()
    draw_text(win, t.font_small, vec2.new(x, y), t.text_secondary, label or "", t.small_font_size)
    local fy = y + 16
    local fh = 30
    local pmin = vec2.new(x, fy)
    local pmax = vec2.new(x + width, fy + fh)
    local is_hover = hovered(win, pmin, pmax)
    local is_open = self._dd_open[id] == true
    local painted = pcall(function()
        win:render_dropdown_field(
            pmin,
            pmax,
            t.bg_input,
            t.bg_tab_hover,
            t.border_header,
            t.rounding or 4.0,
            is_hover and 1.0 or 0.0,
            is_open and 1.0 or 0.0,
            now,
            1.0
        )
    end)
    if painted ~= true then
        local fill = is_hover and t.bg_tab_hover or t.bg_input
        local border = is_open and t.border_header or t.border_panel
        draw_rect(win, pmin, pmax, fill, border, t.rounding, 1.0)
    end
    local shown = items[index] or "(no paths)"
    local text_sz = size_of_font(win, t.font_small, t.small_font_size, shown)
    local max_text_w = width - 28
    if text_sz.x > max_text_w and #shown > 8 then
        while #shown > 8 and size_of_font(win, t.font_small, t.small_font_size, shown .. "...").x > max_text_w do
            shown = shown:sub(1, #shown - 1)
        end
        shown = shown .. "..."
    end
    draw_text(
        win,
        t.font_small,
        vec2.new(x + 10, fy + math.floor((fh - text_sz.y) * 0.5)),
        t.text_header,
        shown,
        t.small_font_size
    )
    local chev = is_open and "^" or "v"
    local chev_sz = size_of_font(win, t.font_small, t.small_font_size, chev)
    draw_text(
        win,
        t.font_small,
        vec2.new(x + width - chev_sz.x - 10, fy + math.floor((fh - chev_sz.y) * 0.5)),
        t.text_header,
        chev,
        t.small_font_size
    )
    block_drag(win, pmin, pmax)
    if clicked(win, pmin, pmax) then
        if is_open then
            self._dd_open[id] = false
        else
            for key, _ in pairs(self._dd_open) do
                self._dd_open[key] = false
            end
            self._dd_open[id] = true
            self._dd_scroll[id] = 0
        end
        is_open = self._dd_open[id] == true
    end
    if self._dd_open[id] == true then
        local vis = 18
        if vis > #items then
            vis = #items
        end
        if vis < 1 then
            vis = 1
        end
        local row_h = 24
        local list_h = vis * row_h + 8
        local pop_pos = vec2.new(x, fy + fh + 2)
        local still = win:begin_popup(
            t.bg_window,
            t.border_window,
            vec2.new(width, list_h),
            pop_pos,
            false,
            false,
            function()
                if #items == 0 then
                    draw_text(win, t.font_small, vec2.new(8, 8), t.text_secondary, "(no paths)", t.small_font_size)
                    return
                end
                local scroll = self._dd_scroll[id] or 0
                if scroll < 0 then
                    scroll = 0
                end
                local max_scroll = #items - vis
                if max_scroll < 0 then
                    max_scroll = 0
                end
                local wheel = safe(function()
                    return core.get_mouse_wheel_delta()
                end)
                if type(wheel) == "number" and wheel ~= 0 then
                    local step = wheel
                    if math.abs(step) >= 10 then
                        step = step / 120
                    end
                    scroll = scroll - math.floor(step)
                end
                if scroll < 0 then
                    scroll = 0
                end
                if scroll > max_scroll then
                    scroll = max_scroll
                end
                self._dd_scroll[id] = scroll
                local row_y = 4
                local last = scroll + vis
                if last > #items then
                    last = #items
                end
                for i = scroll + 1, last do
                    local name = items[i] or ""
                    if self:draw_launcher(win, 4, row_y, width - 8, row_h - 2, name) then
                        index = i
                        self._dd_open[id] = false
                    end
                    row_y = row_y + row_h
                end
            end
        )
        if still ~= true then
            self._dd_open[id] = false
        end
    end
    return index, fy + fh + 8
end

---Inline begin_popup (closes on outside click). Used from Mode as a panel picker.
function Menu:draw_panel_picker_popup(win, pos)
    if self.tools_popup_active ~= true then
        return
    end
    local t = self.theme
    local size = vec2.new(250, 210)
    local start = pos or vec2.new(24, 90)
    local still_open = win:begin_popup(
        t.bg_window,
        t.border_window,
        size,
        start,
        false,
        false,
        function()
            local title = "Open Panel"
            local title_x = safe(function()
                return win:get_text_centered_x_pos(title)
            end) or 70
            pcall(function()
                win:add_menu_element_pos_offset(vec2.new(title_x, 8))
                win:add_text_on_dynamic_pos(t.text_header, title)
                win:add_separator(6.0, 6.0, 6.0, 0.0, t.border_window)
            end)
            local items = {
                { id = "path", label = "Load Profile" },
                { id = "quest", label = "Quests" },
                { id = "vendor", label = "Vendor" },
                { id = "grind", label = "Grind" },
            }
            local row_y = 44
            for i = 1, #items do
                if self:draw_launcher(win, 16, row_y, 218, 32, items[i].label) then
                    self:open_popup(items[i].id)
                    self.tools_popup_active = false
                end
                row_y = row_y + 38
            end
        end
    )
    if still_open ~= true then
        self.tools_popup_active = false
    end
end

function Menu:set_status(items)
    self.status_items = items or {}
end

function Menu:set_actions(items)
    self.actions = items or {}
end

function Menu:set_tabs(tabs)
    self.tabs = {}
    if type(tabs) ~= "table" then
        return
    end
    for i = 1, #tabs do
        local tab = tabs[i]
        if type(tab) == "table" and tab.id then
            self.tabs[#self.tabs + 1] = {
                id = tab.id,
                label = tab.label or tab.id,
            }
        end
    end
end

function Menu:active_tab()
    local index = resolve_number(self.tab_store, 1)
    if index < 1 then
        index = 1
    end
    if index > #self.tabs and #self.tabs > 0 then
        index = #self.tabs
    end
    local tab = self.tabs[index]
    return tab and tab.id or nil, index
end

function Menu:set_active_tab(tab_id)
    for i = 1, #self.tabs do
        if self.tabs[i].id == tab_id then
            pcall(function()
                self.tab_store:set(i)
            end)
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function Menu:layout_metrics(win)
    local t = self.theme
    local size = safe(function()
        return win:get_size()
    end)
    local w = (size and size.x) or self.width
    local h = (size and size.y) or self.height
    local left = t.left_margin
    local header_h = t.header_height
    local footer_h = t.footer_height
    local nav_h = t.nav_height
    local nav_w = t.nav_width
    local top_nav = self.nav_style ~= "left"
    local content_x = left
    local content_y = header_h + (top_nav and (nav_h + 10) or 10)
    if not top_nav then
        content_x = left + nav_w + t.panel_gap
    end
    local content_w = w - content_x - left
    local content_h = h - content_y - footer_h - 8
    return {
        w = w,
        h = h,
        left = left,
        header_h = header_h,
        footer_h = footer_h,
        nav_h = nav_h,
        nav_w = nav_w,
        top_nav = top_nav,
        content_x = content_x,
        content_y = content_y,
        content_w = content_w,
        content_h = content_h,
    }
end

-- ---------------------------------------------------------------------------
-- Chrome
-- ---------------------------------------------------------------------------

function Menu:draw_header(win, m)
    local t = self.theme
    local pmin = vec2.new(0, 0)
    local pmax = vec2.new(m.w, m.header_h)
    local painted = pcall(function()
        win:render_page_title(pmin, pmax, t.bg_header, t.border_header, t.accent, 0.0, 0.0, core.time(), 1.0)
    end)
    if not painted then
        draw_rect(win, pmin, pmax, t.bg_header, t.border_header, 0.0, t.border_thickness)
    end

    local pad = t.left_margin
    local bottom_pad = 10

    -- Version, top-left. Drawn before anything else in the header so nothing
    -- can overlap it, and independent of header_text: when that is set - which
    -- it always is - the subtitle branch below never runs, which is why the
    -- build number used to be nowhere on screen.
    local version_h = 0
    if self.version ~= nil and tostring(self.version) ~= "" then
        local vtext = "v" .. tostring(self.version)
        local vsz = size_of_font(win, t.font_small, t.small_font_size, vtext)
        draw_text(win, t.font_small, vec2.new(pad, 6), t.text_secondary, vtext, t.small_font_size)
        version_h = vsz.y + 4
    end

    local title = self.header_text
    local sub = ""
    if type(title) ~= "string" or title == "" then
        title = self.name
        sub = self.subtitle
        if sub == "" and self.version ~= "" then
            sub = "v" .. tostring(self.version)
        elseif sub ~= "" and self.version ~= "" then
            sub = sub .. "  -  v" .. tostring(self.version)
        end
    end

    local title_font = t.font_title or t.font
    local title_size = t.header_font_size
    local title_sz = size_of_font(win, title_font, title_size, title)
    local sub_sz = vec2.new(0, 0)
    if sub ~= "" then
        sub_sz = size_of_font(win, t.font_small, t.small_font_size, sub)
    end
    local text_h = title_sz.y
    if sub ~= "" then
        text_h = text_h + 4 + sub_sz.y
    end
    -- Reserve the version line so the title block centres in what is LEFT of
    -- the header rather than in the whole of it, which is what produced the
    -- uneven gap above the title.
    text_h = text_h + version_h

    local logo = type(self.logo) == "string" and self.logo ~= ""
    local dw, dh = 0, 0
    if logo then
        dw = self.logo_width
        dh = self.logo_height
        local max_h = m.header_h - bottom_pad - text_h - 4
        if max_h < 24 then
            max_h = 24
        end
        local max_w = math.min(self.logo_width, math.floor(m.w * 0.72))
        if dh > max_h and dh > 0 then
            local scale = max_h / dh
            dw = math.max(1, math.floor(dw * scale))
            dh = math.max(1, math.floor(dh * scale))
        end
        if dw > max_w and dw > 0 then
            local scale = max_w / dw
            dw = math.max(1, math.floor(dw * scale))
            dh = math.max(1, math.floor(dh * scale))
        end
    end

    local ly = 8
    if dw > 0 then
        local lx = math.floor((m.w - dw) * 0.5)
        local band_h = m.header_h - text_h - 4
        ly = math.floor((band_h - dh) * 0.62)
        if ly < 8 then
            ly = 8
        end
        if ly + dh > band_h then
            ly = math.max(4, band_h - dh)
        end
        self:draw_logo_texture(win, lx, ly, dw, dh)
    end

    local tx = pad
    local ty = math.floor((m.header_h - text_h) * 0.5)
    if dh > 0 then
        ty = ly + dh - 6
        local min_ty = ly + dh - 10
        if ty < min_ty then
            ty = min_ty
        end
        local max_ty = m.header_h - bottom_pad - text_h
        if ty > max_ty then
            ty = max_ty
        end
    end
    draw_text(win, title_font, vec2.new(tx, ty), t.text_header, title, title_size)
    if sub ~= "" then
        draw_text(win, t.font_small, vec2.new(tx, ty + title_sz.y + 4), t.text_secondary, sub, t.small_font_size)
    end

    local hints = self.header_hints
    if type(hints) == "function" then
        hints = safe(hints)
    end
    if type(hints) == "table" and #hints > 0 then
        local key_w = 0
        local line_h = 16
        for i = 1, #hints do
            local hint = hints[i]
            if type(hint) == "table" then
                local ksz = size_of_font(win, t.font_small, t.small_font_size, tostring(hint.key or ""))
                if ksz.x > key_w then
                    key_w = ksz.x
                end
                if ksz.y > line_h then
                    line_h = ksz.y
                end
            end
        end
        local col_gap = 14
        local block_h = (#hints * line_h) + ((#hints - 1) * 3)
        local hx = m.w - pad - 40
        local max_cmd_w = 0
        for i = 1, #hints do
            local hint = hints[i]
            if type(hint) == "table" then
                local csz = size_of_font(win, t.font_small, t.small_font_size, tostring(hint.command or ""))
                if csz.x > max_cmd_w then
                    max_cmd_w = csz.x
                end
            end
        end
        hx = m.w - 44 - key_w - col_gap - max_cmd_w
        if hx < (tx + title_sz.x + 24) then
            hx = tx + title_sz.x + 24
        end
        local hy = math.floor((m.header_h - block_h) * 0.5)
        if hy < 8 then
            hy = 8
        end
        for i = 1, #hints do
            local hint = hints[i]
            if type(hint) == "table" then
                local row_y = hy + ((i - 1) * (line_h + 3))
                draw_text(win, t.font_small, vec2.new(hx, row_y), t.text_header, tostring(hint.key or ""), t.small_font_size)
                draw_text(win, t.font_small, vec2.new(hx + key_w + col_gap, row_y), t.text_primary, tostring(hint.command or ""), t.small_font_size)
            end
        end
    end
end

function Menu:draw_nav(win, m)
    if #self.tabs == 0 then
        return
    end
    local t = self.theme
    local active_id, active_index = self:active_tab()

    if m.top_nav then
        local y = m.header_h + 6
        local x = t.left_margin
        local gap = 6
        local count = #self.tabs
        local avail = m.w - (t.left_margin * 2) - ((count - 1) * gap)
        local tab_w = math.floor(avail / math.max(count, 1))
        if tab_w < 64 then
            tab_w = 64
        end
        for i = 1, count do
            local tab = self.tabs[i]
            local pmin = vec2.new(x, y)
            local pmax = vec2.new(x + tab_w, y + t.nav_height)
            local is_active = tab.id == active_id
            local is_hover = hovered(win, pmin, pmax)
            local fill = t.bg_tab
            local border = t.border_tab
            local text_col = t.text_secondary
            if is_active then
                fill = t.bg_tab_active
                border = t.accent
                text_col = t.text_primary
            elseif is_hover then
                fill = t.bg_tab_hover
                text_col = t.text_primary
            end
            draw_rect(win, pmin, pmax, fill, border, t.rounding, 1.0)
            local sz = size_of_font(win, t.font, t.normal_font_size, tab.label)
            local tx = x + math.floor((tab_w - sz.x) * 0.5)
            local ty = y + math.floor((t.nav_height - sz.y) * 0.5)
            draw_text(win, t.font, vec2.new(tx, ty), text_col, tab.label, t.normal_font_size)
            block_drag(win, pmin, pmax)
            if clicked(win, pmin, pmax) then
                pcall(function()
                    self.tab_store:set(i)
                end)
                active_index = i
                active_id = tab.id
            end
            x = x + tab_w + gap
        end
        return
    end

    local y = m.header_h + 8
    local x = t.left_margin
    local tab_w = t.nav_width
    for i = 1, #self.tabs do
        local tab = self.tabs[i]
        local pmin = vec2.new(x, y)
        local pmax = vec2.new(x + tab_w, y + t.nav_height)
        local is_active = tab.id == active_id
        local is_hover = hovered(win, pmin, pmax)
        local fill = t.bg_tab
        local border = t.border_tab
        local text_col = t.text_secondary
        if is_active then
            fill = t.bg_tab_active
            border = t.accent
            text_col = t.text_primary
        elseif is_hover then
            fill = t.bg_tab_hover
            text_col = t.text_primary
        end
        draw_rect(win, pmin, pmax, fill, border, t.rounding, 1.0)
        local sz = size_of_font(win, t.font, t.normal_font_size, tab.label)
        local ty = y + math.floor((t.nav_height - sz.y) * 0.5)
        draw_text(win, t.font, vec2.new(x + 10, ty), text_col, tab.label, t.normal_font_size)
        block_drag(win, pmin, pmax)
        if clicked(win, pmin, pmax) then
            pcall(function()
                self.tab_store:set(i)
            end)
        end
        y = y + t.nav_height + 4
    end
end

function Menu:draw_panel(win, x, y, w, h, title)
    local t = self.theme
    local pmin = vec2.new(x, y)
    local pmax = vec2.new(x + w, y + h)
    draw_rect(win, pmin, pmax, t.bg_panel, t.border_panel, t.rounding, 1.0)

    if title and title ~= "" then
        local head_h = 28
        local head_max = vec2.new(x + w, y + head_h)
        pcall(function()
            win:render_section_header(
                pmin,
                head_max,
                t.bg_panel_alt,
                t.bg_panel,
                t.text_header,
                1.0,
                t.rounding,
                0.0,
                0.0,
                core.time(),
                1.0
            )
        end)
        local sz = size_of_font(win, t.font_section, t.section_font_size, title)
        local ty = y + math.floor((head_h - sz.y) * 0.5)
        draw_text(win, t.font_section, vec2.new(x + 10, ty), t.text_header, title, t.section_font_size)
        win:render_line(vec2.new(x + 8, y + head_h), vec2.new(x + w - 8, y + head_h), t.border_panel, 1.0)
        return y + head_h + 8
    end
    return y + 10
end

function Menu:draw_status(win, x, y, w, h, title)
    local inner_y = self:draw_panel(win, x, y, w, h, title or "Status")
    local t = self.theme
    local row_h = 22
    local row_y = inner_y + 6
    for i = 1, #self.status_items do
        local item = self.status_items[i]
        if type(item) == "table" then
            local label = tostring(item.label or item.key or "")
            local value = call_value(item.value)
            local value_color = item.color
            if type(value_color) == "function" then
                value_color = safe(value_color)
            end
            if not value_color then
                value_color = t.text_primary
            end
            local label_sz = size_of_font(win, t.font_small, t.small_font_size, label)
            local value_sz = size_of_font(win, t.font_small, t.small_font_size, value)
            local ty = row_y + math.floor((row_h - label_sz.y) * 0.5)
            draw_text(win, t.font_small, vec2.new(x + 12, ty), t.text_secondary, label, t.small_font_size)
            draw_text(win, t.font_small, vec2.new(x + w - 14 - value_sz.x, ty), value_color, value, t.small_font_size)
            row_y = row_y + row_h
        end
    end
end

function Menu:draw_action(win, spec, x, y, w, h)
    local t = self.theme
    local style = spec.style or "neutral"
    local pmin = vec2.new(x, y)
    local pmax = vec2.new(x + w, y + h)
    local is_hover = hovered(win, pmin, pmax)
    local base = t.button_neutral
    local elev = t.button_neutral_hi
    local accent = t.border_panel
    if style == "start" or style == "primary" then
        base = t.button_start
        elev = t.button_start_hi
        accent = t.success
    elseif style == "pause" or style == "secondary" then
        base = t.button_pause
        elev = t.button_pause_hi
        accent = t.warning
    elseif style == "stop" or style == "danger" then
        base = t.button_stop
        elev = t.button_stop_hi
        accent = t.danger
    end
    local fill = is_hover and elev or base
    local painted = pcall(function()
        win:render_button_face(
            pmin,
            pmax,
            base,
            elev,
            accent,
            t.rounding,
            is_hover and 1.0 or 0.0,
            0.0,
            core.time(),
            1.0,
            1.0
        )
    end)
    if not painted then
        draw_rect(win, pmin, pmax, fill, accent, t.rounding, 1.0)
    end
    local label = spec.label or "Action"
    local sz = size_of_font(win, t.font_small, t.small_font_size, label)
    draw_text(win, t.font_small, vec2.new(x + math.floor((w - sz.x) * 0.5), y + math.floor((h - sz.y) * 0.5)), t.text_primary, label, t.small_font_size)
    block_drag(win, pmin, pmax)
    if clicked(win, pmin, pmax) then
        if type(spec.on_click) == "function" then
            pcall(spec.on_click)
        end
        return true
    end
    return false
end

function Menu:draw_actions(win, x, y, w)
    if type(self.actions) ~= "table" or #self.actions == 0 then
        return y
    end
    local t = self.theme
    local gap = 10
    local count = #self.actions
    local btn_w = math.floor((w - ((count - 1) * gap)) / count)
    local btn_h = t.button_height or 34
    local ax = x
    for i = 1, count do
        self:draw_action(win, self.actions[i], ax, y, btn_w, btn_h)
        ax = ax + btn_w + gap
    end
    return y + btn_h + 6
end

function Menu:draw_footer(win, m)
    local t = self.theme
    local y = m.h - m.footer_h
    local pmin = vec2.new(0, y)
    local pmax = vec2.new(m.w, m.h)
    draw_rect(win, pmin, pmax, t.bg_header, t.border_header, 0.0, t.border_thickness)
    local text = self.footer
    if text == "" then
        text = self.name .. "  v" .. tostring(self.version)
    end
    local sz = size_of_font(win, t.font_small, t.small_font_size, text)
    local tx = math.floor((m.w - sz.x) * 0.5)
    if tx < t.left_margin then
        tx = t.left_margin
    end
    local ty = y + math.floor((m.footer_h - sz.y) * 0.5)
    draw_text(win, t.font_small, vec2.new(tx, ty), t.text_secondary, text, t.small_font_size)
end

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------

function Menu:draw_checkbox_row(win, record, x, y, width)
    local t = self.theme
    local on = resolve_bool(record.element)
    local h = t.row_height or 30
    local pmin = vec2.new(x, y)
    local pmax = vec2.new(x + width, y + h)
    local is_hover = hovered(win, pmin, pmax)
    local fill = t.bg_row
    local border = t.border_panel
    local text_col = t.text_off
    if on then
        fill = t.bg_tab_active
        border = t.accent
        text_col = t.text_on
    end
    if is_hover then
        fill = on and t.bg_tab_hover or t.bg_row_hover
    end
    draw_rect(win, pmin, pmax, fill, border, 3.0, 1.0)

    local stripe = on and t.text_on or t.text_off
    win:render_rect_filled(vec2.new(x, y), vec2.new(x + 3, y + h), stripe, 1.0)

    local box = 14
    local bx = x + 10
    local by = y + math.floor((h - box) * 0.5)
    draw_rect(win, vec2.new(bx, by), vec2.new(bx + box, by + box), on and t.accent or t.bg_input, border, 2.0, 1.0)
    if on then
        win:render_line(vec2.new(bx + 3, by + 7), vec2.new(bx + 6, by + 11), t.text_primary, 2.0)
        win:render_line(vec2.new(bx + 6, by + 11), vec2.new(bx + 11, by + 3), t.text_primary, 2.0)
    end

    local label_sz = size_of_font(win, t.font_small, t.small_font_size, record.label)
    local status = on and "ON" or "OFF"
    local status_sz = size_of_font(win, t.font_small, t.small_font_size, status)
    local ty = y + math.floor((h - label_sz.y) * 0.5)
    draw_text(win, t.font_small, vec2.new(bx + box + 10, ty), on and t.text_primary or t.text_secondary, record.label, t.small_font_size)
    draw_text(win, t.font_small, vec2.new(x + width - status_sz.x - 10, ty), text_col, status, t.small_font_size)

    if record.tooltip and is_hover then
        pcall(function()
            win:render_tooltip_text_only(record.tooltip, t.text_primary)
        end)
    end
    block_drag(win, pmin, pmax)
    if clicked(win, pmin, pmax) then
        set_bool(record.element, not on)
    end
    return y + h + t.control_gap
end

local function resolve_keybind_bool(elem)
    if not elem then
        return false
    end
    local state = safe(function()
        return elem:get_toggle_state()
    end)
    if type(state) == "boolean" then
        return state
    end
    return resolve_bool(elem)
end

function Menu:draw_keybind_row(win, record, x, y, width)
    local t = self.theme
    local elem = record.element
    local on = resolve_keybind_bool(elem)
    local code = 0
    if elem then
        local got = safe(function()
            return elem:get_key_code()
        end)
        if type(got) == "number" then
            code = got
        end
    end
    local h = t.row_height or 30
    local pmin = vec2.new(x, y)
    local pmax = vec2.new(x + width, y + h)
    local is_hover = hovered(win, pmin, pmax)
    local fill = t.bg_row
    local border = t.border_panel
    local text_col = t.text_off
    if on then
        fill = t.bg_tab_active
        border = t.accent
        text_col = t.text_on
    end
    if is_hover then
        fill = on and t.bg_tab_hover or t.bg_row_hover
    end
    draw_rect(win, pmin, pmax, fill, border, 3.0, 1.0)

    local stripe = on and t.text_on or t.text_off
    win:render_rect_filled(vec2.new(x, y), vec2.new(x + 3, y + h), stripe, 1.0)

    local key_name = key_display_name(code)
    local status = on and "ON" or "OFF"
    local label_sz = size_of_font(win, t.font_small, t.small_font_size, record.label)
    local status_sz = size_of_font(win, t.font_small, t.small_font_size, status)
    local key_sz = size_of_font(win, t.font_small, t.small_font_size, key_name)
    local ty = y + math.floor((h - label_sz.y) * 0.5)
    draw_text(win, t.font_small, vec2.new(x + 12, ty), on and t.text_primary or t.text_secondary, record.label, t.small_font_size)

    local pill_h = h - 10
    local pill_w = math.max(88, key_sz.x + 18)
    local pill_x = x + width - status_sz.x - 18 - pill_w
    local pill_y = y + math.floor((h - pill_h) * 0.5)
    local pill_min = vec2.new(pill_x, pill_y)
    local pill_max = vec2.new(pill_x + pill_w, pill_y + pill_h)
    local pill_ok = pcall(function()
        win:render_keybind_pill(
            pill_min,
            pill_max,
            t.bg_input,
            t.bg_tab_hover,
            on and t.accent or t.border_panel,
            4.0,
            is_hover and 1.0 or 0.0,
            0.0,
            core.time(),
            1.0
        )
    end)
    if not pill_ok then
        draw_rect(win, pill_min, pill_max, t.bg_input, on and t.accent or t.border_panel, 4.0, 1.0)
    end
    local key_ty = pill_y + math.floor((pill_h - key_sz.y) * 0.5)
    draw_text(win, t.font_small, vec2.new(pill_x + math.floor((pill_w - key_sz.x) * 0.5), key_ty), t.text_primary, key_name, t.small_font_size)
    draw_text(win, t.font_small, vec2.new(x + width - status_sz.x - 10, ty), text_col, status, t.small_font_size)

    local tip = record.tooltip
    if type(tip) ~= "string" or tip == "" then
        tip = "Click to toggle. Numpad keys also toggle this."
    end
    if is_hover then
        pcall(function()
            win:render_tooltip_text_only(tip, t.text_primary)
        end)
    end
    block_drag(win, pmin, pmax)
    if clicked(win, pmin, pmax) and elem then
        pcall(function()
            elem:set_toggle_state(not on)
        end)
    end
    return y + h + t.control_gap
end

function Menu:render_native_at(win, record, x, y, width)
    local element = record.element
    if not element then
        return y + 28
    end
    local row_h = 28
    local clip_h = 48
    if record.kind == "combobox" then
        row_h = 32
        clip_h = 240
    end
    local clipped = pcall(function()
        win:push_clip_rect(vec2.new(x, y), vec2.new(x + width, y + clip_h), true)
    end)
    pcall(function()
        win:begin_window_sub_context(vec2.new(x, y), true, function()
            pcall(function()
                win:set_next_widget_width(width or self.theme.control_width)
            end)
            if record.kind == "slider_int" or record.kind == "slider_float" then
                element:render(record.label, record.tooltip)
                return
            end
            if record.kind == "text_input" then
                element:render(record.label, record.tooltip)
                return
            end
            if record.kind == "combobox" then
                element:render(record.label, record.items or {}, record.tooltip)
                return
            end
            if record.kind == "button" then
                local pressed = element:render(record.label, record.tooltip)
                if pressed and type(record.on_click) == "function" then
                    pcall(record.on_click)
                end
            end
        end)
    end)
    if clipped then
        pcall(function()
            win:pop_clip_rect()
        end)
    end
    return y + row_h + self.theme.control_gap
end

function Menu:tab_content_height(tab_id)
    local t = self.theme
    local row = t.row_height or 35
    local gap = t.control_gap or 7
    local n = 0
    for i = 1, #self.order do
        local record = self.order[i]
        if record.tab == tab_id and self:control_visible(record) then
            if not record.skip_draw then
                n = n + 1
            end
        end
    end
    local h = 10 + n * (row + gap) + 10
    if self.tab_draw[tab_id] then
        h = h + ((row + gap) * 8) + 24
    end
    return h
end

function Menu:draw_scroll_thumb(win, tx, ty, tw, th, scroll, max_scroll, tab_id)
    if th < 8 then
        return scroll
    end
    local t = self.theme
    local track_min = vec2.new(tx, ty)
    local track_max = vec2.new(tx + tw, ty + th)
    draw_rect(win, track_min, track_max, t.bg_input, t.border_panel, 3.0, 1.0)

    local can_scroll = max_scroll >= 1
    if not can_scroll then
        max_scroll = 1
        scroll = 0
    end

    local thumb_h = math.floor(th * (th / (th + max_scroll)))
    if not can_scroll then
        thumb_h = th
    end
    if thumb_h < 22 then
        thumb_h = 22
    end
    if thumb_h > th then
        thumb_h = th
    end
    local travel = th - thumb_h
    local thumb_y = ty
    if travel > 0 then
        thumb_y = ty + math.floor(travel * (scroll / max_scroll))
    end
    local thumb_min = vec2.new(tx, thumb_y)
    local thumb_max = vec2.new(tx + tw, thumb_y + thumb_h)
    local is_hover = hovered(win, thumb_min, thumb_max) or hovered(win, track_min, track_max)
    draw_rect(win, thumb_min, thumb_max, is_hover and t.accent_hover or t.accent, t.border_header, 3.0, 1.0)

    local pressed = safe(function()
        return win:is_mouse_button_pressed(0)
    end) == true
    if not pressed then
        if self._scroll_drag == tab_id then
            self._scroll_drag = nil
        end
        block_drag(win, track_min, track_max)
        return scroll
    end

    local over = hovered(win, track_min, track_max) or self._scroll_drag == tab_id
    if over then
        self._scroll_drag = tab_id
        local mouse = safe(function()
            return win:get_mouse_pos_local()
        end)
        if mouse and type(mouse.y) == "number" and travel > 0 then
            local rel = (mouse.y - ty - (thumb_h * 0.5)) / travel
            if rel < 0 then
                rel = 0
            end
            if rel > 1 then
                rel = 1
            end
            scroll = rel * max_scroll
        end
    end
    block_drag(win, track_min, track_max)
    return scroll
end

function Menu:draw_tab_scroll_area(win, tab_id, x, y, w, h)
    local content_h = self:tab_content_height(tab_id)
    local bar_w = 8
    local view_w = w - bar_w - 4
    local max_scroll = math.max(0, content_h - h)
    local scroll = self._tab_scroll[tab_id] or 0

    local pmin = vec2.new(x, y)
    local pmax = vec2.new(x + w, y + h)
    block_drag(win, pmin, pmax)

    if hovered(win, pmin, pmax) and self._scroll_drag ~= tab_id then
        local wheel = safe(function()
            return core.get_mouse_wheel_delta()
        end)
        if type(wheel) == "number" and wheel ~= 0 then
            local step = wheel
            if math.abs(step) >= 10 then
                step = step / 120
            end
            scroll = scroll - (step * 36)
        end
    end

    if scroll < 0 then
        scroll = 0
    end
    if scroll > max_scroll then
        scroll = max_scroll
    end

    scroll = self:draw_scroll_thumb(win, x + w - bar_w, y, bar_w, h, scroll, max_scroll, tab_id) or scroll
    if scroll < 0 then
        scroll = 0
    end
    if scroll > max_scroll then
        scroll = max_scroll
    end
    self._tab_scroll[tab_id] = scroll

    local clipped = false
    if tab_id ~= "path" and tab_id ~= "quest" then
        clipped = pcall(function()
            win:push_clip_rect(vec2.new(x, y), vec2.new(x + view_w, y + h), true)
        end)
    end
    local start_x = x + 6
    local start_y = y + 6 - scroll
    local inner_w = view_w - 12
    local extra_top = 0
    if tab_id == "class" and self.tab_draw[tab_id] then
        -- 72 was exactly the two status lines. The Spells tab now also carries
        -- the button that opens the full spellbook, which ends at ~74px, so
        -- the reserve has to cover it or the button is clipped and the first
        -- toggle draws on top of it.
        extra_top = 104
        pcall(self.tab_draw[tab_id], win, start_x, start_y, inner_w, extra_top, self)
    end
    if tab_id == "path" and self.tab_draw[tab_id] then
        extra_top = 380
        pcall(self.tab_draw[tab_id], win, start_x, start_y, inner_w, extra_top, self)
    end
    if tab_id == "quest" and self.tab_draw[tab_id] then
        extra_top = 300
        pcall(self.tab_draw[tab_id], win, start_x, start_y, inner_w, extra_top, self)
    end
    local cy = self:render_tab_controls(win, tab_id, start_x, start_y + extra_top, inner_w)
    if tab_id ~= "class" and tab_id ~= "path" and tab_id ~= "quest" and self.tab_draw[tab_id] then
        pcall(self.tab_draw[tab_id], win, start_x, cy, inner_w, h, self)
    end
    if clipped then
        pcall(function()
            win:pop_clip_rect()
        end)
    end
end

function Menu:render_tab_controls(win, tab_id, x, y, width)
    local cy = y
    for i = 1, #self.order do
        local record = self.order[i]
        if record.tab == tab_id and self:control_visible(record) then
            if record.skip_draw then
                -- kept for persistence / getters only
            elseif record.kind == "checkbox" then
                cy = self:draw_checkbox_row(win, record, x, cy, width)
            elseif record.kind == "keybind" then
                cy = self:draw_keybind_row(win, record, x, cy, width)
            else
                cy = self:render_native_at(win, record, x, cy, width)
            end
        end
    end
    return cy
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------

function Menu:draw_popup_window(popup)
    if type(popup) ~= "table" or popup.open ~= true or not popup.window then
        return
    end
    local win = popup.window
    local t = self.theme
    pcall(function()
        win:set_next_window_padding(vec2.new(0, 0))
    end)
    pcall(function()
        win:set_next_window_items_spacing(vec2.new(4, 2))
    end)
    pcall(function()
        win:set_corner_rounding(t.rounding or 4.0)
    end)

    local open = win:begin(
        WE.window_resizing_flags.RESIZE_HEIGHT,
        true,
        t.bg_window,
        t.border_window,
        WE.window_cross_visuals.BLUE_THEME,
        function()
            local ok, err = pcall(function()
                local bounds = safe(function()
                    return win:get_close_cross_bounds()
                end)
                if type(bounds) == "table" and bounds.min and bounds.max then
                    block_drag(win, bounds.min, bounds.max)
                    if clicked(win, bounds.min, bounds.max) then
                        popup.open = false
                        pcall(function()
                            win:set_visibility(false)
                        end)
                        return
                    end
                end

                local size = safe(function()
                    return win:get_size()
                end)
                local w = (size and size.x) or popup.width
                local h = (size and size.y) or popup.height
                local header_h = 44

                -- Stop short of the close cross. The core draws the cross in
                -- the top-right BEFORE this callback runs, so a header bar
                -- spanning the full width painted straight over it and the
                -- popup looked as though it had no way to close.
                local cross_w = 34
                local bounds = safe(function()
                    return win:get_close_cross_bounds()
                end)
                if type(bounds) == "table" and bounds.min and bounds.max then
                    local want = w - bounds.min.x + 6
                    if type(want) == "number" and want > cross_w then
                        cross_w = want
                    end
                end
                draw_rect(win, vec2.new(0, 0), vec2.new(w - cross_w, header_h),
                    t.bg_header, t.border_header, 0.0, t.border_thickness)

                local title = popup.title or ""
                local sz = size_of_font(win, t.font_section, t.section_font_size, title)
                -- Centred in the space the header actually occupies, so a long
                -- title cannot drift under the close cross.
                local title_x = math.floor(((w - cross_w) - sz.x) * 0.5)
                if title_x < t.left_margin then
                    title_x = t.left_margin
                end
                draw_text(
                    win,
                    t.font_section,
                    vec2.new(title_x, 12),
                    t.text_header,
                    title,
                    t.section_font_size
                )
                pcall(function()
                    win:add_separator(8.0, 8.0, 8.0, 0.0, t.border_window)
                end)

                local content_y = header_h + 8
                local content_h = h - content_y - 12
                if content_h < 40 then
                    content_h = 40
                end
                local inner_y = self:draw_panel(win, 10, content_y, w - 20, content_h, nil)
                self:draw_tab_scroll_area(win, popup.tab, 16, inner_y, w - 32, (content_y + content_h) - inner_y - 8)
            end)
            if not ok then
                core.log_error("[Master Farmer - Grindbot] popup " .. tostring(popup.id) .. ": " .. tostring(err))
            end
        end
    )
    if open == true then
        popup.ever_open = true
        return
    end
    if open == false then
        popup.open = false
        pcall(function()
            win:set_visibility(false)
        end)
    end
end

function Menu:draw_popups()
    for i = 1, #self.popups do
        local popup = self.popups[i]
        if popup.open == true then
            pcall(function()
                popup.window:set_visibility(true)
            end)
            self:draw_popup_window(popup)
        end
    end
end

function Menu:set_visible(on)
    self.visible = on == true
    if self.visible then
        self._closed = false
        for i = 1, #self.popups do
            local popup = self.popups[i]
            if popup.open == true then
                pcall(function()
                    popup.window:set_visibility(true)
                end)
            end
        end
    else
        for i = 1, #self.popups do
            pcall(function()
                self.popups[i].window:set_visibility(false)
            end)
        end
    end
    pcall(function()
        self.window:set_visibility(self.visible)
    end)
end

function Menu:is_closed()
    return self._closed == true
end

function Menu:mark_closed()
    self.visible = false
    self._closed = true
    self:close_popups()
    pcall(function()
        self.window:set_visibility(false)
    end)
    if type(self.on_close) == "function" then
        pcall(self.on_close)
    end
end

function Menu:handle_close_cross(win)
    local bounds = safe(function()
        return win:get_close_cross_bounds()
    end)
    if type(bounds) ~= "table" or not bounds.min or not bounds.max then
        return false
    end
    block_drag(win, bounds.min, bounds.max)
    if clicked(win, bounds.min, bounds.max) then
        self:mark_closed()
        return true
    end
    return false
end

function Menu:draw()
    local win = self.window
    if self.visible == false then
        pcall(function()
            win:set_visibility(false)
        end)
        return
    end

    pcall(function()
        self:retry_font()
    end)

    pcall(function()
        win:force_window_size(vec2.new(self.width, self.height))
    end)
    pcall(function()
        win:set_next_window_padding(vec2.new(0, 0))
    end)
    pcall(function()
        win:set_next_window_items_spacing(vec2.new(4, 2))
    end)

    local t = self.theme
    local open = win:begin(
        WE.window_resizing_flags.NO_RESIZE,
        true,
        t.bg_window,
        t.border_window,
        WE.window_cross_visuals.BLUE_THEME,
        function()
            local ok, err = pcall(function()
                if self:handle_close_cross(win) then
                    return
                end
                local m = self:layout_metrics(win)
                self:draw_header(win, m)
                self:draw_nav(win, m)

                local active_id = self:active_tab()
                local tab_title = nil
                for i = 1, #self.tabs do
                    if self.tabs[i].id == active_id then
                        tab_title = self.tabs[i].label
                        break
                    end
                end

                local has_status = type(self.status_items) == "table" and #self.status_items > 0
                local gap = t.panel_gap
                local left_w = m.content_w
                local status_w = 0
                if has_status then
                    status_w = math.floor(m.content_w * 0.38)
                    left_w = m.content_w - status_w - gap
                end

                local left_x = m.content_x
                local left_y = m.content_y
                local panel_h = m.content_h
                if type(self.actions) == "table" and #self.actions > 0 then
                    panel_h = panel_h - ((t.button_height or 34) + 12)
                end

                local inner_y = self:draw_panel(win, left_x, left_y, left_w, panel_h, tab_title)
                self:draw_tab_scroll_area(win, active_id, left_x + 8, inner_y + 4, left_w - 16, (left_y + panel_h) - inner_y - 10)

                if has_status then
                    self:draw_status(win, left_x + left_w + gap, left_y, status_w, panel_h, "Status")
                end

                if type(self.actions) == "table" and #self.actions > 0 then
                    self:draw_actions(win, left_x, left_y + panel_h + 6, m.content_w)
                end

                self:draw_footer(win, m)
                self:draw_popups()
                if self.tools_popup_active == true then
                    self:draw_panel_picker_popup(win, vec2.new(24, 90))
                end
            end)
            if not ok then
                core.log_error("[Master Farmer - Grindbot] UI chrome: " .. tostring(err))
            end
        end
    )
    if open == true then
        self._ever_open = true
        return
    end
    if open == false and self._ever_open == true then
        self:mark_closed()
    end
end

ui.Menu = Menu

return ui

-- ============================================================================
-- Master Farmer - Grindbot
-- PathTool format — { name, map_id, loop, waypoints[{x,y,z,wait,combo,actions}] }
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.3.37
-- Folder: Master_Farmer_Grindbot_v1.3.37
-- ============================================================================

local path_format = {}

local function skip_ws(s, i)
    local n = #s
    while i <= n do
        local c = s:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            break
        end
        i = i + 1
    end
    return i
end

local parse_value

local function parse_string(s, i)
    i = i + 1
    local n = #s
    local start = i
    while i <= n do
        local c = s:sub(i, i)
        if c == '"' then
            return s:sub(start, i - 1), i + 1
        end
        if c == "\\" then
            break
        end
        i = i + 1
    end
    local buf = { s:sub(start, i - 1) }
    while i <= n do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(buf), i + 1
        end
        if c == "\\" then
            local n1 = s:sub(i + 1, i + 1)
            if n1 == '"' or n1 == "\\" or n1 == "/" then
                buf[#buf + 1] = n1
            elseif n1 == "n" then
                buf[#buf + 1] = "\n"
            elseif n1 == "t" then
                buf[#buf + 1] = "\t"
            elseif n1 == "r" then
                buf[#buf + 1] = "\r"
            else
                buf[#buf + 1] = n1
            end
            i = i + 2
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    return nil, i, "unterminated string"
end

local function parse_number(s, i)
    local n = #s
    local start = i
    if s:sub(i, i) == "-" then
        i = i + 1
    end
    while i <= n and s:sub(i, i):match("%d") do
        i = i + 1
    end
    if s:sub(i, i) == "." then
        i = i + 1
        while i <= n and s:sub(i, i):match("%d") do
            i = i + 1
        end
    end
    local e = s:sub(i, i)
    if e == "e" or e == "E" then
        i = i + 1
        local sign = s:sub(i, i)
        if sign == "+" or sign == "-" then
            i = i + 1
        end
        while i <= n and s:sub(i, i):match("%d") do
            i = i + 1
        end
    end
    local num = tonumber(s:sub(start, i - 1))
    if num == nil then
        return nil, start, "bad number"
    end
    return num, i
end

local function parse_array(s, i)
    i = i + 1
    local arr = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == "]" then
        return arr, i + 1
    end
    while true do
        local val, ni, err = parse_value(s, i)
        if err then
            return nil, ni, err
        end
        arr[#arr + 1] = val
        i = skip_ws(s, ni)
        local c = s:sub(i, i)
        if c == "]" then
            return arr, i + 1
        end
        if c ~= "," then
            return nil, i, "expected comma in array"
        end
        i = skip_ws(s, i + 1)
    end
end

local function parse_object(s, i)
    i = i + 1
    local obj = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == "}" then
        return obj, i + 1
    end
    while true do
        i = skip_ws(s, i)
        if s:sub(i, i) ~= '"' then
            return nil, i, "expected string key"
        end
        local key, ni, err = parse_string(s, i)
        if err then
            return nil, ni, err
        end
        i = skip_ws(s, ni)
        if s:sub(i, i) ~= ":" then
            return nil, i, "expected colon"
        end
        local val, vi, verr = parse_value(s, skip_ws(s, i + 1))
        if verr then
            return nil, vi, verr
        end
        obj[key] = val
        i = skip_ws(s, vi)
        local c = s:sub(i, i)
        if c == "}" then
            return obj, i + 1
        end
        if c ~= "," then
            return nil, i, "expected comma in object"
        end
        i = i + 1
    end
end

parse_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return parse_string(s, i)
    end
    if c == "{" then
        return parse_object(s, i)
    end
    if c == "[" then
        return parse_array(s, i)
    end
    if c == "t" and s:sub(i, i + 3) == "true" then
        return true, i + 4
    end
    if c == "f" and s:sub(i, i + 4) == "false" then
        return false, i + 5
    end
    if c == "n" and s:sub(i, i + 3) == "null" then
        return nil, i + 4
    end
    if c == "-" or c:match("%d") then
        return parse_number(s, i)
    end
    return nil, i, "unexpected token"
end

function path_format.decode_json(text)
    if type(text) ~= "string" or text == "" then
        return nil, "empty json"
    end
    local value, i, err = parse_value(text, 1)
    if err then
        return nil, err
    end
    return value
end

local function copy_actions(raw)
    local out = {}
    if type(raw) ~= "table" then
        return out
    end
    for i = 1, #raw do
        local act = raw[i]
        if type(act) == "table" and type(act.type) == "string" then
            local row = { type = act.type }
            if type(act.id) == "number" then
                row.id = act.id
            end
            if type(act.sec) == "number" then
                row.sec = act.sec
            end
            out[#out + 1] = row
        end
    end
    return out
end

local held_mod = nil

function path_format.take_module(mod)
    if type(mod) ~= "string" or mod == "" then
        return nil, "no module"
    end
    if held_mod and held_mod ~= mod then
        package.loaded[held_mod] = nil
        pcall(collectgarbage, "step", 400)
    end
    local ok, raw = pcall(require, mod)
    if not ok then
        return nil, tostring(raw)
    end
    held_mod = mod
    return raw
end

function path_format.drop()
    if held_mod then
        package.loaded[held_mod] = nil
        held_mod = nil
        pcall(collectgarbage, "step", 400)
    end
end

function path_format.normalize(raw)
    if type(raw) == "string" then
        local decoded, err = path_format.decode_json(raw)
        if not decoded then
            return nil, err or "json parse failed"
        end
        raw = decoded
    end
    if type(raw) ~= "table" then
        return nil, "path is not a table"
    end
    local src = raw.waypoints
    if type(src) ~= "table" then
        return nil, "path has no waypoints"
    end
    if raw._mfg_norm == true and #src > 0 then
        return raw
    end
    local write = 0
    for i = 1, #src do
        local wp = src[i]
        if type(wp) == "table" and type(wp.x) == "number" and type(wp.y) == "number" and type(wp.z) == "number" then
            if type(wp.wait) ~= "number" then
                wp.wait = 0
            end
            wp.combo = wp.combo == true
            if type(wp.actions) == "table" and #wp.actions > 0 then
                wp.actions = copy_actions(wp.actions)
            else
                wp.actions = nil
            end
            write = write + 1
            if write ~= i then
                src[write] = wp
            end
        end
    end
    for i = write + 1, #src do
        src[i] = nil
    end
    if write == 0 then
        return nil, "path has no valid waypoints"
    end
    local name = raw.name
    if type(name) ~= "string" or name == "" or name == "default" then
        raw.name = raw.id or "path"
    end
    if type(raw.map_id) ~= "number" then
        raw.map_id = 0
    end
    raw.loop = raw.loop == true
    raw._mfg_norm = true
    return raw
end

local function json_escape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function is_array(t)
    if type(t) ~= "table" then
        return false
    end
    local n = #t
    if n == 0 then
        return next(t) == nil
    end
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            return false
        end
        count = count + 1
    end
    return count == n
end

local encode_value

local function encode_object(t)
    local parts = { "{" }
    local first = true
    local keys = {}
    for k, _ in pairs(t) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    for i = 1, #keys do
        local k = keys[i]
        local v = t[k]
        if v ~= nil then
            if not first then
                parts[#parts + 1] = ","
            end
            first = false
            parts[#parts + 1] = "\""
            parts[#parts + 1] = json_escape(k)
            parts[#parts + 1] = "\":"
            parts[#parts + 1] = encode_value(v)
        end
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
end

local function encode_array(t)
    local parts = { "[" }
    for i = 1, #t do
        if i > 1 then
            parts[#parts + 1] = ","
        end
        parts[#parts + 1] = encode_value(t[i])
    end
    parts[#parts + 1] = "]"
    return table.concat(parts)
end

encode_value = function(v)
    local tv = type(v)
    if tv == "nil" then
        return "null"
    end
    if tv == "boolean" then
        if v then
            return "true"
        end
        return "false"
    end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "null"
        end
        return tostring(v)
    end
    if tv == "string" then
        return "\"" .. json_escape(v) .. "\""
    end
    if tv == "table" then
        if is_array(v) then
            return encode_array(v)
        end
        return encode_object(v)
    end
    return "null"
end

local function encode_waypoint(wp)
    local row = {
        x = wp.x,
        y = wp.y,
        z = wp.z,
    }
    if type(wp.wait) == "number" and wp.wait ~= 0 then
        row.wait = wp.wait
    end
    if wp.combo == true then
        row.combo = true
    end
    if type(wp.actions) == "table" and #wp.actions > 0 then
        row.actions = wp.actions
    end
    return row
end

function path_format.encode_json(path)
    local normalized = path
    if type(path) == "table" and type(path.waypoints) == "table" then
        local ok_norm, err = path_format.normalize(path)
        if ok_norm then
            normalized = ok_norm
        elseif err then
            normalized = path
        end
    else
        local ok_norm, err = path_format.normalize(path)
        if not ok_norm then
            return nil, err or "cannot encode path"
        end
        normalized = ok_norm
    end
    local wps = {}
    local src = normalized.waypoints
    for i = 1, #src do
        wps[i] = encode_waypoint(src[i])
    end
    local payload = {
        name = normalized.name,
        map_id = normalized.map_id,
        loop = normalized.loop == true,
        waypoints = wps,
    }
    if type(normalized.id) == "string" and normalized.id ~= "" then
        payload.id = normalized.id
    end
    return encode_value(payload)
end

function path_format.has_hold(wp)
    if type(wp) ~= "table" then
        return false
    end
    if type(wp.wait) == "number" and wp.wait > 0 then
        return true
    end
    local actions = wp.actions
    return type(actions) == "table" and #actions > 0
end

function path_format.reversed(path)
    local normalized, err = path_format.normalize(path)
    if not normalized then
        return nil, err
    end
    if normalized.reversed == true then
        return normalized
    end
    local src = normalized.waypoints
    local wps = {}
    for i = #src, 1, -1 do
        wps[#wps + 1] = src[i]
    end
    local out = {}
    for k, v in pairs(normalized) do
        out[k] = v
    end
    out.waypoints = wps
    out.reversed = true
    out._mfg_norm = true
    local name = out.name or "path"
    if not string.find(name, "(reverse)", 1, true) then
        out.name = name .. " (reverse)"
    end
    if type(out.id) == "string" and out.id ~= "" then
        if not string.find(out.id, "_rev", 1, true) then
            out.id = out.id .. "_rev"
        end
    end
    return out
end

return path_format

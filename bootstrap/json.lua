-- ============================================================================
-- Minimal JSON decoder (same algorithm as path_format.decode_json)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 1.4.0
-- Folder: Master_Farmer_Grindbot_v1.4.0
-- ============================================================================

local json = {}

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

function json.decode(text)
    if type(text) ~= "string" or text == "" then
        return nil, "empty json"
    end
    local value, i, err = parse_value(text, 1)
    if err then
        return nil, err
    end
    return value
end

return json

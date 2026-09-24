-- ============================================================================
-- Master Farmer - Grindbot
-- movement/zones.lua - blacklist zones
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Areas movement refuses to path into, pruned in place on a TTL. Nothing here
-- issues a command, so every other module may require it freely.
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

local K = require("movement/const")
local R = require("movement/rt")
local U = require("movement/util")

local ZONE_RADIUS      = K.ZONE_RADIUS
local ZONE_MERGE       = K.ZONE_MERGE
local ZONE_TTL         = K.ZONE_TTL
local ZONE_PRUNE_EVERY = K.ZONE_PRUNE_EVERY
local MAX_ZONES        = K.MAX_ZONES

local xyz, dist2, log = U.xyz, U.dist2, U.log

local Z = {}

function Z.prune(t, force)
    if not force and (t - R.zones_pruned_t) < ZONE_PRUNE_EVERY then return end
    R.zones_pruned_t = t
    local zones = R.zones
    local n, w = #zones, 0
    for i = 1, n do
        local z = zones[i]
        if (t - z.t) < ZONE_TTL then
            w = w + 1
            zones[w] = z
        end
    end
    for i = w + 1, n do zones[i] = nil end
end

--- Is (x, y) inside any blacklist zone? Squared distances, no allocation.
function Z.blocked_xy(x, y)
    local zones = R.zones
    for i = 1, #zones do
        local z = zones[i]
        local dx, dy = z.x - x, z.y - y
        if dx * dx + dy * dy <= z.r * z.r then return true end
    end
    return false
end

function Z.blacklist_area(pos, radius, why)
    local x, y, z = xyz(pos)
    if not x then return false end
    radius = tonumber(radius) or ZONE_RADIUS
    if radius < 6 then radius = 6 elseif radius > 30 then radius = 30 end
    local t = izi.now()
    Z.prune(t, true)
    local zones = R.zones
    for i = 1, #zones do
        local zn = zones[i]
        if dist2(zn.x, zn.y, x, y) < ZONE_MERGE then
            zn.x, zn.y, zn.z, zn.t = x, y, z, t
            if radius > zn.r then zn.r = radius end
            zn.hits = zn.hits + 1
            return true
        end
    end
    if #zones >= MAX_ZONES then table.remove(zones, 1) end
    zones[#zones + 1] = { x = x, y = y, z = z, r = radius, t = t, hits = 1, why = why }
    log(string.format("Blacklist area (%.1f, %.1f, %.1f) r=%.0f%s", x, y, z, radius,
        why and (" - " .. tostring(why)) or ""))
    return true
end

function Z.is_blocked(pos)
    local x, y = xyz(pos)
    if not x then return false end
    Z.prune(izi.now())
    return Z.blocked_xy(x, y)
end

function Z.count()
    Z.prune(izi.now(), true)
    return #R.zones
end

return Z

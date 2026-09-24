-- ============================================================================
-- Master Farmer - Grindbot
-- movement/geom.lua - number-only geometry (results go into pool slots)
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- ============================================================================
-- Every function here returns a pool point that is valid only until the next
-- steering call. Copy it (rt.to_vec3) before handing it to anything that keeps
-- it. No allocation happens in this file.
-- ============================================================================

local R = require("movement/rt")
local U = require("movement/util")

local pt       = R.pt
local ground_z = U.ground_z

local sqrt, sin, cos, rad = math.sqrt, math.sin, math.cos, math.rad

local G = {}

--- Point `travel` yards from f toward g (or g itself when closer), ground-snapped.
function G.extend(slot, f, g, travel)
    local dx, dy = g.x - f.x, g.y - f.y
    local d = sqrt(dx * dx + dy * dy)
    if d <= travel or d < 0.001 then
        return pt(slot, g.x, g.y, g.z)
    end
    local k = travel / d
    local x, y = f.x + dx * k, f.y + dy * k
    return pt(slot, x, y, ground_z(x, y, f.z + (g.z - f.z) * k))
end

--- p rotated `degrees` around o, ground-snapped.
function G.rotate(slot, p, o, degrees)
    local a = rad(degrees)
    local c, s = cos(a), sin(a)
    local dx, dy = p.x - o.x, p.y - o.y
    local x, y = o.x + dx * c - dy * s, o.y + dx * s + dy * c
    return pt(slot, x, y, ground_z(x, y, p.z))
end

--- Point `yards` to the left/right of d, perpendicular to the f->d direction.
function G.sidestep(slot, f, d, left, yards)
    local dx, dy = d.x - f.x, d.y - f.y
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    local nx, ny = -dy / len, dx / len          -- left normal
    if not left then nx, ny = -nx, -ny end
    local x, y = d.x + nx * yards, d.y + ny * yards
    return pt(slot, x, y, ground_z(x, y, d.z))
end

--- Point `yards` from `from`, directly away from `threat`. Ground-snapped.
function G.away_from(slot, from, threat, yards)
    local dx, dy = from.x - threat.x, from.y - threat.y
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    local k = yards / len
    local x, y = from.x + dx * k, from.y + dy * k
    return pt(slot, x, y, ground_z(x, y, from.z))
end

return G

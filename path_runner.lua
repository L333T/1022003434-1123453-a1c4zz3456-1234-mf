-- ============================================================================
-- Master Farmer - Grindbot
-- PathTool playback — recorded follow_path chunks stay on simple_movement.
-- Long OOC legs (approach to start, blocked hops) go through movement.nav_to
-- which may use Sentinel. Leash is disarmed while Sentinel owns a move.
-- Off-path: stay inside a 10-yard corridor; traceline + vec2/vec3 hops rejoin the polyline.
-- Reverse: waypoint order is flipped at start; skip/loop still walk +1 through that list.
-- Movement issues are throttled in movement.lua (max 1 per MOVE_GAP).
-- ============================================================================
-- Authors: BLIZZ - Anthonyk
-- Version: 2.2.0
-- Folder: Master_Farmer_Grindbot_v2.2.0
-- ============================================================================

---@type izi_api
local izi = require("common/izi_sdk")

---@type vec3
local vec3 = require("common/geometry/vector_3")

---@type color
local color = require("common/color")

local path_format = require("path_format")
local movement = require("movement")
local state = require("state")

local path_runner = {}

local CHUNK = 24
local AREA_YARDS = 80.0
local OFF_PATH = 10.0
local ARRIVE = 2.0
local OFFMESH_SKIP = 5

local session = nil
local preview = nil
local spell_by_id = {}

local function spell_of(id)
    if type(id) ~= "number" then
        return nil
    end
    local cached = spell_by_id[id]
    if cached then
        return cached
    end
    local spell = izi.spell(id)
    if spell then
        spell_by_id[id] = spell
    end
    return spell
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function dist(a, b)
    if not a or not b then
        return nil
    end
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function nearest_index(pos, waypoints)
    local best = 1
    local best_d = 1e9
    for i = 1, #waypoints do
        local d = dist(pos, waypoints[i])
        if type(d) == "number" and d < best_d then
            best_d = d
            best = i
        end
    end
    return best, best_d
end

local function recover_to_path(pos, waypoints, index)
    if not pos or type(waypoints) ~= "table" or #waypoints < 1 then
        return index, false
    end
    local best, best_d = nearest_index(pos, waypoints)
    if type(best_d) ~= "number" or best_d > AREA_YARDS then
        return index, false
    end
    local cur = waypoints[index]
    local cur_d = dist(pos, cur)
    local off_path = type(cur_d) ~= "number" or cur_d > OFF_PATH
    if off_path and best ~= index then
        return best, true
    end
    if type(cur_d) == "number" and best_d + 4.0 < cur_d and best ~= index then
        return best, true
    end
    return index, false
end

local function next_break(waypoints, from)
    local last = #waypoints
    if type(from) ~= "number" or from < 1 then
        from = 1
    end
    if from > last then
        return last
    end
    if path_format.has_hold(waypoints[from]) then
        return from
    end
    local limit = math.min(last, from + CHUNK - 1)
    for i = from + 1, limit do
        if path_format.has_hold(waypoints[i]) then
            return i
        end
    end
    return limit
end

local function reset_hold(s)
    s.wait_until = 0
    s.wait_armed = false
    s.action_i = 1
    s.tries = 0
    s.stuck_since = 0
    s.nav_until = 0
end

function path_runner.is_active()
    return session ~= nil
end

function path_runner.path_id()
    if not session or not session.path then
        return nil
    end
    return session.path.id
end

function path_runner.set_loop(on)
    if not session then
        return
    end
    local file_loop = session.path and session.path.loop == true
    session.loop = file_loop or (on == true)
end

function path_runner.pause(keep_nav)
    if not session then
        return
    end
    session.paused = true
    if keep_nav == true then
        return
    end
    pcall(function()
        movement.nav_stop()
    end)
end

function path_runner.resume()
    if not session then
        return
    end
    session.paused = false
    session.stuck_since = 0
    local pos = state.cached_pos
    if pos and session.path and type(session.path.waypoints) == "table" then
        local recovered, changed = recover_to_path(pos, session.path.waypoints, session.index)
        if changed then
            session.index = recovered
            reset_hold(session)
        end
    end
end

function path_runner.is_paused()
    return session ~= nil and session.paused == true
end

function path_runner.status_text()
    if not session then
        return "Idle"
    end
    local n = #session.path.waypoints
    if session.paused then
        return string.format("Combat  %d/%d  %s", session.index, n, session.path.name or "Path")
    end
    if session.approach then
        return string.format("To start  %s", session.path.name or "Path")
    end
    return string.format("%s  %d/%d", session.path.name or "Path", session.index, n)
end

function path_runner.stop()
    if not session then
        return
    end
    session = nil
    if type(movement.clear_path_leash) == "function" then
        movement.clear_path_leash()
    end
    pcall(function()
        movement.nav_stop()
    end)
end

function path_runner.start(path, opts)
    opts = opts or {}
    local normalized, err = path_format.normalize(path)
    if not normalized then
        return false, err
    end
    if opts.reverse == true then
        local reversed, rerr = path_format.reversed(normalized)
        if not reversed then
            return false, rerr or "reverse failed"
        end
        normalized = reversed
    end
    path_runner.stop()
    local pos = state.cached_pos
    local loop = normalized.loop == true
    if opts.loop == true then
        loop = true
    end
    session = {
        path = normalized,
        index = 1,
        loop = loop,
        laps = 0,
        lap_pending = 0,
        wait_until = 0,
        wait_armed = false,
        action_i = 1,
        tries = 0,
        stuck_since = 0,
        nav_until = 0,
        prefer_direct = false,
        paused = false,
        approach = true,
        started_at = izi.now(),
        map_warned = false,
        reversed = normalized.reversed == true,
        slice = nil,
        slice_from = nil,
        slice_to = nil,
    }
    preview = normalized
    local first = normalized.waypoints[1]
    local n = #normalized.waypoints
    if pos and first then
        local d = dist(pos, first)
        if type(d) == "number" and d <= ARRIVE then
            session.approach = false
        end
        local ni, nd = nearest_index(pos, normalized.waypoints)
        if type(nd) == "number" and nd <= AREA_YARDS then
            session.index = ni
            session.approach = false
        end
    end
    local map_id = normalized.map_id
    if type(map_id) == "number" and map_id > 0 then
        local current = safe(function() return core.get_map_id() end)
        if type(current) == "number" and current ~= 0 and current ~= map_id then
            session.map_warned = true
            core.log("[Master Farmer - Grindbot] Path map_id " .. tostring(map_id) .. " (current " .. tostring(current) .. ") - running world coords anyway.")
        end
    end
    core.log(string.format(
        "[Master Farmer - Grindbot] Path start: %s (%d waypoints, index %d%s)",
        tostring(normalized.name),
        n,
        session.index,
        session.reversed and ", reverse" or ""
    ))
    if type(movement.set_path_leash) == "function" then
        movement.set_path_leash(normalized.waypoints)
    end
    return true
end

local function run_action(player, act)
    if type(act) ~= "table" or type(act.type) ~= "string" then
        return true
    end
    if act.type == "wait" then
        local sec = act.sec
        if type(sec) ~= "number" or sec < 0 then
            sec = 0
        end
        if sec > 0 then
            session.wait_until = izi.now() + sec
            state.set_note("Path", string.format("Wait %.1fs", sec))
        end
        return true
    end
    if act.type == "spell" then
        local id = act.id
        if type(id) ~= "number" then
            return true
        end
        local spell = spell_of(id)
        if not spell then
            core.log_warning("[Master Farmer - Grindbot] Path spell missing: " .. tostring(id))
            return true
        end
        local learned = true
        if type(spell.is_learned) == "function" then
            learned = spell:is_learned() == true
        end
        if not learned then
            core.log("[Master Farmer - Grindbot] Path spell not learned, skip: " .. tostring(id))
            return true
        end
        pcall(function()
            movement.nav_stop()
        end)
        local ok = safe(function()
            return spell:cast_safe(player, "path:" .. tostring(id))
        end)
        if ok then
            state.last_action = "Path spell " .. tostring(id)
            session.wait_until = izi.now() + 0.35
        end
        return true
    end
    return true
end

local function skip_blocked(waypoints, index)
    local i = index
    local n = #waypoints
    local hops = 0
    local pos = state.cached_pos
    while i <= n and hops < 20 do
        local wp = waypoints[i]
        if movement.is_blocked(wp) then
            i = i + 1
            hops = hops + 1
        elseif pos and i < n and not path_format.has_hold(wp) and movement.line_blocked and movement.line_blocked(pos, wp) then
            local nxt = waypoints[i + 1]
            if nxt and not movement.is_blocked(nxt) and not movement.line_blocked(pos, nxt) then
                i = i + 1
                hops = hops + 1
            else
                break
            end
        else
            break
        end
    end
    return i
end

local function skip_passed(pos, waypoints, index)
    local i = index
    while i < #waypoints do
        local wp = waypoints[i]
        if path_format.has_hold(wp) then
            break
        end
        if movement.is_blocked(wp) then
            i = i + 1
        else
            local d = dist(pos, wp)
            if type(d) ~= "number" or d > ARRIVE then
                break
            end
            i = i + 1
        end
    end
    return i
end

local function issue_move(waypoints, from_index)
    if type(from_index) ~= "number" or from_index < 1 then
        return false
    end
    local wp = waypoints[from_index]
    if not wp then
        return false
    end
    local to = next_break(waypoints, from_index)
    if type(to) ~= "number" or to < from_index then
        to = from_index
    end
    session.nav_until = to
    if to > from_index then
        if session.slice and session.slice_from == from_index and session.slice_to == to then
            return movement.nav_path(session.slice)
        end
        local pts = {}
        for i = from_index, to do
            pts[#pts + 1] = waypoints[i]
        end
        session.slice, session.slice_from, session.slice_to = pts, from_index, to
        return movement.nav_path(pts)
    end
    session.slice, session.slice_from, session.slice_to = nil, nil, nil
    return movement.nav_to(wp)
end

local function skip_offmesh(n)
    local jump = math.min(n, session.index + OFFMESH_SKIP)
    core.log_warning(string.format(
        "[Master Farmer - Grindbot] Path skip off-navmesh waypoints %d-%d (%s)",
        session.index,
        jump,
        tostring(movement.last_fail_reason() or "navmesh")
    ))
    session.index = jump + 1
    reset_hold(session)
    pcall(function()
        movement.nav_stop()
    end)
    movement.clear_fail()
end

function path_runner.tick(player)
    if not session then
        return false
    end
    local path = session.path
    local waypoints = path.waypoints
    local n = #waypoints
    if n == 0 then
        path_runner.stop()
        return false
    end
    if session.paused then
        return true
    end
    if movement.in_combat_movement() then
        return true
    end

    local now = izi.now()
    if session.last_tick and (now - session.last_tick) > 1.0 then
        session.stuck_since = 0
    end
    session.last_tick = now
    if session.wait_until > now then
        return true
    end
    if movement.is_quiet() then
        state.set_note("Path", "Nav settle")
        return true
    end

    local pos = state.cached_pos or safe(function() return player:get_position() end)
    if not pos then
        return true
    end

    if movement.needs_rejoin and movement.needs_rejoin() == true then
        if type(movement.path_anchor_index) == "function" then
            local idx = movement.path_anchor_index(pos)
            if type(idx) == "number" and idx >= 1 and idx <= n then
                session.index = idx
            end
        end
        if movement.is_moving() then
            pcall(function()
                movement.nav_stop()
            end)
            state.set_note("Path", "Rejoin path")
            return true
        end
        if type(movement.rejoin_path) == "function" then
            movement.rejoin_path()
        end
        state.set_note("Path", "Rejoin path")
        return true
    end

    if not session.approach then
        local recovered, changed = recover_to_path(pos, waypoints, session.index)
        if changed then
            session.index = recovered
            reset_hold(session)
            state.set_note("Path", "Rejoin closest waypoint")
        end
    end

    if session.approach then
        local recovered, changed = recover_to_path(pos, waypoints, 1)
        if changed then
            session.approach = false
            session.index = recovered
            reset_hold(session)
            state.set_note("Path", "Rejoin closest waypoint")
        else
            local first = waypoints[1]
            if not first then
                session.approach = false
            elseif movement.arrived(first, ARRIVE) then
                session.approach = false
                session.index = 1
                reset_hold(session)
                core.log("[Master Farmer - Grindbot] Reached path start: " .. tostring(path.name))
            else
                if movement.is_blocked(first) or movement.last_fail_offmesh() then
                    session.approach = false
                    session.index = skip_blocked(waypoints, 1)
                    reset_hold(session)
                    movement.clear_fail()
                    core.log_warning("[Master Farmer - Grindbot] Path start not on navmesh - skipping to waypoint " .. tostring(session.index))
                    return true
                end
                state.set_note("Path", "Travel to start  " .. tostring(path.name))
                movement.nav_to(first)
                return true
            end
        end
    end

    session.index = skip_passed(pos, waypoints, session.index)
    session.index = skip_blocked(waypoints, session.index)

    if session.index > n then
        if session.loop then
            session.index = 1
            reset_hold(session)
            session.laps = (session.laps or 0) + 1
            session.lap_pending = (session.lap_pending or 0) + 1
            core.log("[Master Farmer - Grindbot] Path loop restart: " .. tostring(path.name))
        else
            state.set_note("Path", "Complete")
            core.log("[Master Farmer - Grindbot] Path complete: " .. tostring(path.name))
            path_runner.stop()
            return false
        end
    end

    local wp = waypoints[session.index]
    if not wp then
        return true
    end
    if movement.is_blocked(wp) then
        skip_offmesh(n)
        return true
    end
    local arrived = movement.arrived(wp, ARRIVE)
    if not arrived then
        if movement.last_fail_offmesh() then
            if not session.prefer_direct then
                session.prefer_direct = true
                core.log("[Master Farmer - Grindbot] Path navmesh miss - walking recorded points directly.")
                pcall(function()
                    movement.nav_stop()
                end)
                movement.clear_fail()
                issue_move(waypoints, session.index)
                return true
            end
            skip_offmesh(n)
            return true
        end
        local moving = movement.is_moving()
        if moving then
            session.stuck_since = 0
            local until_i = session.nav_until or 0
            if type(until_i) ~= "number" or until_i < session.index then
                issue_move(waypoints, session.index)
            end
        else
            issue_move(waypoints, session.index)
            if session.stuck_since == 0 then
                session.stuck_since = now
            elseif (now - session.stuck_since) > 12 then
                if movement.sentinel_active and movement.sentinel_active() then
                    session.stuck_since = now
                else
                    core.log_warning("[Master Farmer - Grindbot] Path skip stuck waypoint " .. tostring(session.index))
                    session.index = session.index + 1
                    reset_hold(session)
                end
            end
        end
        state.set_note("Path", string.format("%s  %d/%d", path.name, session.index, n))
        return true
    end

    session.tries = 0
    session.stuck_since = 0

    if not session.wait_armed then
        session.wait_armed = true
        if type(wp.wait) == "number" and wp.wait > 0 then
            session.wait_until = now + wp.wait
            state.set_note("Path", string.format("Waypoint wait %.1fs", wp.wait))
            return true
        end
    end

    local actions = wp.actions
    if type(actions) == "table" and session.action_i <= #actions then
        run_action(player, actions[session.action_i])
        session.action_i = session.action_i + 1
        return true
    end

    session.index = session.index + 1
    reset_hold(session)
    if session.index > n then
        if session.loop then
            session.index = 1
            session.laps = (session.laps or 0) + 1
            session.lap_pending = (session.lap_pending or 0) + 1
            core.log("[Master Farmer - Grindbot] Path loop restart: " .. tostring(path.name))
            return true
        end
        state.set_note("Path", "Complete")
        core.log("[Master Farmer - Grindbot] Path complete: " .. tostring(path.name))
        path_runner.stop()
        return false
    end

    issue_move(waypoints, session.index)
    state.set_note("Path", string.format("%s  %d/%d", path.name, session.index, n))
    return true
end

--- Laps completed since the path started.
function path_runner.laps()
    return (session and session.laps) or 0
end

--- True once per completed lap, and only once: the caller consumes the lap.
---
--- A flag rather than a comparison against a remembered count, because the
--- consumer (the vendor trip) runs for many ticks after the lap ends and must
--- not re-trigger itself when it finishes.
function path_runner.take_lap()
    if not session or (session.lap_pending or 0) <= 0 then
        return false
    end
    session.lap_pending = session.lap_pending - 1
    return true
end

function path_runner.current_path()
    if session and session.path then
        return session.path
    end
    return preview
end

function path_runner.set_preview(path)
    local normalized = path
    if type(path) == "table" and type(path.waypoints) == "table" then
        local ok_norm = path_format.normalize(path)
        if ok_norm then
            normalized = ok_norm
        end
        preview = normalized
    else
        preview = nil
    end
end

function path_runner.clear_preview()
    preview = nil
end

local DRAW_RANGE = 160
local MAX_LINES = 220
local LINE_COL = color.new(248, 226, 132, 210)
local NOW_COL = color.new(80, 200, 90, 230)
local NEXT_COL = color.new(64, 176, 220, 230)

local function wp_vec(wp)
    if type(wp) ~= "table" then
        return nil
    end
    if type(wp.x) ~= "number" or type(wp.y) ~= "number" or type(wp.z) ~= "number" then
        return nil
    end
    return vec3.new(wp.x, wp.y, wp.z)
end

local function near_player(pos, wp)
    if not pos or not wp then
        return false
    end
    local dx = wp.x - pos.x
    local dy = wp.y - pos.y
    local dz = (wp.z or 0) - (pos.z or 0)
    return (dx * dx + dy * dy + dz * dz) <= (DRAW_RANGE * DRAW_RANGE)
end

function path_runner.draw()
    local path = nil
    local current = 0
    if session and session.path then
        path = session.path
        current = session.index or 0
    elseif preview then
        path = preview
    end
    if not path or type(path.waypoints) ~= "table" then
        return
    end
    local waypoints = path.waypoints
    local n = #waypoints
    if n < 1 then
        return
    end
    local pos = state.cached_pos
    local step = 1
    if n > 400 then
        step = math.ceil(n / 300)
    end
    local drawn = 0
    local prev = nil
    local prev_i = 0
    for i = 1, n, step do
        local wp = waypoints[i]
        if near_player(pos, wp) then
            local v = wp_vec(wp)
            if v and prev and (i - prev_i) <= (step * 2) then
                pcall(function()
                    core.graphics.line_3d(prev, v, LINE_COL, 2.0, 2.5, false)
                end)
                drawn = drawn + 1
                if drawn >= MAX_LINES then
                    break
                end
            end
            prev = v
            prev_i = i
        else
            prev = nil
            prev_i = 0
        end
    end
    if current >= 1 and current <= n then
        local now_v = wp_vec(waypoints[current])
        if now_v then
            pcall(function()
                core.graphics.circle_3d(now_v, 1.6, NOW_COL, 2.0, 2.5)
            end)
        end
        local nxt = waypoints[current + 1]
        local nxt_v = wp_vec(nxt)
        if nxt_v then
            pcall(function()
                core.graphics.circle_3d(nxt_v, 1.2, NEXT_COL, 2.0, 2.5)
            end)
            if now_v then
                pcall(function()
                    core.graphics.line_3d(now_v, nxt_v, NEXT_COL, 3.0, 2.5, false)
                end)
            end
        end
    elseif n >= 1 then
        local first = wp_vec(waypoints[1])
        if first and near_player(pos, waypoints[1]) then
            pcall(function()
                core.graphics.circle_3d(first, 1.4, LINE_COL, 2.0, 2.5)
            end)
        end
    end
end

return path_runner

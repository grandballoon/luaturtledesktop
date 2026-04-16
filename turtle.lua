-- turtle.lua
-- Entry point: require("turtle")
-- Creates a default screen, core, and renderer. Exports all API functions
-- as globals. turtle.Turtle() creates additional turtles on the same screen.

local Core     = require("turtle.core")
local Screen   = require("turtle.screen")
local Renderer = require("turtle.renderer")

----------------------------------------------------------------
-- Module table
----------------------------------------------------------------

local turtle = {}

-- Derive window title from the running script name (arg[0])
local function script_title()
    local path = arg and arg[0]
    if not path then return "Lua Turtle" end
    local name = path:match("([^/\\]+)$") or path
    return (name:match("^(.+)%.[^.]+$") or name)
end

-- Create the default screen, core, and renderer.
local screen   = Screen.new()
local core     = Core.new(screen)  -- screen:register(core) called inside
local renderer = Renderer.new({ title = script_title(), screen = screen })
renderer.core  = core

-- Expose for advanced users and Turtle() factory
turtle._screen   = screen
turtle._core     = core
turtle._renderer = renderer

-- Graceful error recovery: keep window open if script exits without done().
local _mainloop_entered = false
turtle._exit_sentinel = setmetatable({ renderer = renderer }, {
    __gc = function(self)
        if self.renderer.initialized and not _mainloop_entered then
            io.stderr:write(
                "\n[turtle] script ended before done() — "
                .. "window is open, press ESC or close to exit.\n"
            )
            self.renderer:mainloop()
        end
    end
})

----------------------------------------------------------------
-- with_undo: wraps a command so undo records the added segment indices.
-- Call BEFORE the command (push) and AFTER (commit).
-- All turtle command wrappers use this; it is the only place _push_undo /
-- _commit_undo_segments are called.
----------------------------------------------------------------

local function with_undo(c, fn)
    c:_push_undo()
    fn()
    c:_commit_undo_segments()
end

----------------------------------------------------------------
-- Animation helpers
----------------------------------------------------------------

-- Returns the step granularity for the given speed setting (1–10).
-- Higher speed → bigger steps → fewer intermediate renders → visually faster.
-- speed 1 → 1px/deg, speed 5 → 4px/deg, speed 10 → 16px/deg
local function step_size_for_speed(s)
    if s == 0 then return math.huge end
    return math.max(1, math.floor(2 ^ (s / 2.5)))
end

----------------------------------------------------------------
-- Per-turtle command implementations (parameterized by core `c`).
-- These contain all the animated / render logic. The global API functions
-- and Turtle() method wrappers are thin shells around these.
----------------------------------------------------------------

local function _forward(c, distance)
    distance = distance or 0
    with_undo(c, function()
        if distance == 0 then
            c:forward(0)
            return
        end
        if c.speed_setting == 0 then
            c:forward(distance)
            return
        end
        local step_size  = step_size_for_speed(c.speed_setting)
        local steps      = math.max(1, math.floor(math.abs(distance) / step_size))
        local step_dist  = distance / steps
        local delay      = renderer:frame_delay()
        for _ = 1, steps do
            c:forward(step_dist)
            renderer:render()
            if delay > 0 then renderer:sleep(delay) end
        end
    end)
end

local function _right(c, angle)
    angle = angle or 0
    with_undo(c, function()
        if angle == 0 or c.speed_setting == 0 then
            c:right(angle)
            if c.speed_setting ~= 0 then renderer:render() end
            return
        end
        local step_angle = step_size_for_speed(c.speed_setting)
        local steps      = math.max(1, math.floor(math.abs(angle) / step_angle))
        local step       = angle / steps
        local delay      = renderer:frame_delay()
        for _ = 1, steps do
            c:right(step)
            renderer:render()
            if delay > 0 then renderer:sleep(delay) end
        end
    end)
end

local function _circle(c, radius, extent, steps)
    radius = radius or 0
    extent = extent or 360
    with_undo(c, function()
        if radius == 0 then return end
        if not steps then
            steps = math.max(4, math.floor(math.abs(extent) / 6))
        end
        local RAD          = math.pi / 180
        local step_angle   = extent / steps
        local step_len     = 2 * math.abs(radius) * math.sin(math.abs(step_angle) / 2 * RAD)
        if radius < 0 then step_angle = -step_angle end
        local delay        = renderer:frame_delay()
        local render_every = step_size_for_speed(c.speed_setting)
        for i = 1, steps do
            c:left(step_angle / 2)
            c:forward(step_len)
            c:left(step_angle / 2)
            if c.speed_setting ~= 0 and (i % render_every == 0 or i == steps) then
                renderer:render()
                if delay > 0 then renderer:sleep(delay) end
            end
        end
    end)
end

-- Generic draw command: call core method, render if animated, wrap with undo.
-- Returns any values the core method returns (for getters).
local function _draw(c, method_name, ...)
    local args   = {...}
    local result = {}
    with_undo(c, function()
        result = {c[method_name](c, table.unpack(args))}
        if c.speed_setting ~= 0 then renderer:render() end
    end)
    return table.unpack(result)
end

local function _do_clear(c)
    c:clear()
    renderer:request_full_redraw()
    renderer:render()
end

local function _do_reset(c)
    c:reset()
    renderer:request_full_redraw()
    renderer:render()
end

local function _do_end_fill(c)
    with_undo(c, function()
        c:end_fill()
        renderer:request_full_redraw()
        renderer:render()
    end)
end

local function _do_clearstamp(c, id)
    with_undo(c, function()
        c:clearstamp(id)
        renderer:request_full_redraw()
        renderer:render()
    end)
end

local function _do_clearstamps(c, n)
    with_undo(c, function()
        c:clearstamps(n)
        renderer:request_full_redraw()
        renderer:render()
    end)
end

-- Conditional-undo helpers for getter/setters
local function _pensize(c, w)
    if w ~= nil then
        with_undo(c, function() c:pensize(w) end)
    end
    return c:pensize()
end

local function _pencolor(c, r, g, b, a)
    if r ~= nil then
        with_undo(c, function() c:pencolor(r, g, b, a) end)
    else
        return c:pencolor()
    end
end

local function _fillcolor(c, r, g, b, a)
    if r ~= nil then
        with_undo(c, function() c:fillcolor(r, g, b, a) end)
    else
        return c:fillcolor()
    end
end

local function _color(c, pen, fill)
    if pen ~= nil then
        with_undo(c, function() c:color(pen, fill) end)
    else
        return c:color()
    end
end

local function _teleport(c, x, y)
    with_undo(c, function() c:teleport(x, y) end)
end

local function _penup(c)
    with_undo(c, function() c:penup() end)
end

local function _pendown(c)
    with_undo(c, function() c:pendown() end)
end

local function _begin_fill(c)
    with_undo(c, function() c:begin_fill() end)
end

local function _dot(c, size, r, g, b, a)
    with_undo(c, function()
        c:dot(size, r, g, b, a)
        renderer:render()
    end)
end

local function _write(c, text, move, align, font)
    with_undo(c, function()
        c:write(text, move, align, font)
        renderer:render()
    end)
end

local function _stamp(c)
    local id
    with_undo(c, function()
        id = c:stamp()
        renderer:render()
    end)
    return id
end

local function _showturtle(c)
    with_undo(c, function() c:showturtle(); renderer:render() end)
end

local function _hideturtle(c)
    with_undo(c, function() c:hideturtle(); renderer:render() end)
end

-- Animated undo (M4 / Refactor 4).
--
-- core:undo() applies the state restoration and returns a description:
--   { segments, current_state {x,y,angle}, previous_state {x,y,angle} }
--
-- Animation rules (speed=0 → instant for all):
--   • All-line segments (forward/back/circle/arc) → erase path in reverse.
--     Walk segments in reverse order, each going from its .to back to its .from.
--     A _temp_segs overlay shows the remaining line/arc shrinking each frame.
--     Works whether or not the heading changes (covers both straight and curved paths).
--   • No segments, heading changed → reverse the turn.
--   • Anything else (fill, dot, stamp, text, compound) → instant.
local function _undo(c)
    local desc = c:undo()
    if not desc then return end

    local speed = c.speed_setting
    if speed ~= 0 then
        local segs  = desc.segments
        local curr  = desc.current_state
        local prev  = desc.previous_state

        -- Detect all-line undo with unchanged heading (forward / back / setpos)
        local all_lines = #segs > 0
        for _, seg in ipairs(segs) do
            if seg.type ~= "line" then all_lines = false; break end
        end
        -- heading_unchanged: used only for the pure-turn branch below
        local angle_diff        = (curr.angle - prev.angle) % 360
        local heading_unchanged = angle_diff < 0.001 or angle_diff > 359.999

        if all_lines then
            -- Place turtle at the "current" end of the path and step backward
            -- through each sub-segment in reverse order (works for straight
            -- lines and curves: heading_unchanged is not required).
            -- The segments are already hidden; _temp_segs on the overlay shows
            -- the remaining arc/line and shrinks as the turtle walks back.
            c.x     = curr.x
            c.y     = curr.y
            c.angle = curr.angle
            -- Rebuild canvas without the hidden segments, then build temp segs.
            renderer.needs_full_redraw = true
            renderer._temp_segs = {}
            for i, seg in ipairs(segs) do
                renderer._temp_segs[i] = {
                    from  = seg.from,
                    to    = seg.to,
                    color = seg.color,
                    width = seg.width or 2,
                }
            end
            local delay         = renderer:frame_delay()
            local step_size     = step_size_for_speed(c.speed_setting)
            -- Distribute total heading reversal evenly across segments so the
            -- turtle's heading tracks the arc (for straight lines the delta is 0).
            local heading_delta = (prev.angle - curr.angle) / #segs
            for i = #segs, 1, -1 do
                local seg  = segs[i]
                local tseg = renderer._temp_segs[i]
                local dx   = seg.from[1] - seg.to[1]
                local dy   = seg.from[2] - seg.to[2]
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0 then
                    local steps      = math.max(1, math.floor(dist / step_size))
                    local sx, sy     = dx / steps, dy / steps
                    local angle_step = heading_delta / steps
                    for _ = 1, steps do
                        c.x     = c.x + sx
                        c.y     = c.y + sy
                        c.angle = c.angle + angle_step
                        tseg.to = { c.x, c.y }   -- shorten this segment on overlay
                        renderer:render()
                        if delay > 0 then renderer:sleep(delay) end
                    end
                else
                    c.angle = c.angle + heading_delta
                end
                renderer._temp_segs[i] = nil   -- segment fully erased, drop from overlay
            end
            -- Snap to exact restored position (eliminates float drift)
            c.x     = prev.x
            c.y     = prev.y
            c.angle = prev.angle
            renderer._temp_segs = nil

        elseif #segs == 0 and not heading_unchanged then
            -- Reverse a turn: animate from current angle back to previous.
            -- Direct delta (no modular normalization needed: turns are recorded
            -- as exact angle values, so linear interpolation is correct).
            c.x     = curr.x
            c.y     = curr.y
            c.angle = curr.angle
            local delta      = prev.angle - curr.angle
            local step_angle = step_size_for_speed(c.speed_setting)
            local steps      = math.max(1, math.floor(math.abs(delta) / step_angle))
            local step       = delta / steps
            local delay      = renderer:frame_delay()
            for _ = 1, steps do
                c.angle = c.angle + step
                renderer:render()
                if delay > 0 then renderer:sleep(delay) end
            end
            c.angle = prev.angle
        end
        -- else: instant (fill, dot, stamp, text, circle, compound) — fall through
    end

    renderer:request_full_redraw()
    renderer:render()
end

----------------------------------------------------------------
-- Build a method table for a turtle core.
-- Methods accept `self` as first argument (for t:forward() colon syntax).
-- The default turtle's globals are built from the same functions with no self.
----------------------------------------------------------------

local function make_turtle_methods(c)
    local m = {}

    -- Movement (animated)
    m.forward  = function(_, d)         _forward(c, d) end
    m.fd       = m.forward
    m.back     = function(_, d)         _forward(c, -(d or 0)) end
    m.bk       = m.back
    m.backward = m.back
    m.right    = function(_, a)         _right(c, a) end
    m.rt       = m.right
    m.left     = function(_, a)         _right(c, -(a or 0)) end
    m.lt       = m.left
    m.circle   = function(_, r, e, s)   _circle(c, r, e, s) end

    -- Absolute positioning
    m.setpos      = function(_, x, y)   _draw(c, "setpos", x, y) end
    m.setposition = m.setpos
    m.setx        = function(_, x)      _draw(c, "setx", x) end
    m.sety        = function(_, y)      _draw(c, "sety", y) end
    m.setheading  = function(_, a)      _draw(c, "setheading", a) end
    m.seth        = m.setheading
    m.home        = function(_)         _draw(c, "home") end
    m.teleport    = function(_, x, y)   _teleport(c, x, y) end

    -- Pen control
    m.penup    = function(_)            _penup(c) end
    m.pu       = m.penup
    m.up       = m.penup
    m.pendown  = function(_)            _pendown(c) end
    m.pd       = m.pendown
    m.down     = m.pendown
    m.pensize  = function(_, w)         return _pensize(c, w) end
    m.width    = m.pensize
    m.pencolor = function(_, r, g, b, a) return _pencolor(c, r, g, b, a) end
    m.fillcolor= function(_, r, g, b, a) return _fillcolor(c, r, g, b, a) end
    m.color    = function(_, p, f)      return _color(c, p, f) end

    -- Fill
    m.begin_fill = function(_)          _begin_fill(c) end
    m.end_fill   = function(_)          _do_end_fill(c) end
    m.filling    = function(_)          return c:is_filling() end

    -- Drawing extras
    m.dot        = function(_, s, r, g, b, a) _dot(c, s, r, g, b, a) end
    m.write      = function(_, t, mv, al, f)  _write(c, t, mv, al, f) end
    m.stamp      = function(_)          return _stamp(c) end
    m.clearstamp = function(_, id)      _do_clearstamp(c, id) end
    m.clearstamps= function(_, n)       _do_clearstamps(c, n) end

    -- Canvas
    m.clear = function(_)               _do_clear(c) end
    m.reset = function(_)               _do_reset(c) end

    -- State queries
    m.position  = function(_)           return c:position() end
    m.pos       = m.position
    m.xcor      = function(_)           return c:xcor() end
    m.ycor      = function(_)           return c:ycor() end
    m.heading   = function(_)           return c:heading() end
    m.isdown    = function(_)           return c:isdown() end
    m.isvisible = function(_)           return c:isvisible() end
    m.towards   = function(_, x, y)    return c:towards(x, y) end
    m.distance  = function(_, x, y)    return c:distance(x, y) end

    -- Visibility
    m.showturtle = function(_)          _showturtle(c) end
    m.st         = m.showturtle
    m.hideturtle = function(_)          _hideturtle(c) end
    m.ht         = m.hideturtle

    -- Speed
    m.speed = function(_, n)
        if n == nil then return c:speed() end
        c:speed(n)
    end

    -- Undo
    m.undo             = function(_)    _undo(c) end
    m.setundobuffer    = function(_, n) c:setundobuffer(n) end
    m.undobufferentries= function(_)    return c:undobufferentries() end

    return m
end

----------------------------------------------------------------
-- Build the module-level (global) API from the default core.
-- These are plain functions (no self argument), identical semantics to
-- the Turtle() method variants.
----------------------------------------------------------------

turtle.forward   = function(d)         _forward(core, d) end
turtle.fd        = turtle.forward
turtle.back      = function(d)         _forward(core, -(d or 0)) end
turtle.bk        = turtle.back
turtle.backward  = turtle.back
turtle.right     = function(a)         _right(core, a) end
turtle.rt        = turtle.right
turtle.left      = function(a)         _right(core, -(a or 0)) end
turtle.lt        = turtle.left
turtle.circle    = function(r, e, s)   _circle(core, r, e, s) end

turtle.setpos      = function(x, y)    _draw(core, "setpos", x, y) end
turtle.setposition = turtle.setpos
turtle.setx        = function(x)       _draw(core, "setx", x) end
turtle.sety        = function(y)       _draw(core, "sety", y) end
turtle.setheading  = function(a)       _draw(core, "setheading", a) end
turtle.seth        = turtle.setheading
turtle.home        = function()        _draw(core, "home") end
turtle.teleport    = function(x, y)    _teleport(core, x, y) end

turtle.penup    = function()           _penup(core) end
turtle.pu       = turtle.penup
turtle.up       = turtle.penup
turtle.pendown  = function()           _pendown(core) end
turtle.pd       = turtle.pendown
turtle.down     = turtle.pendown
turtle.pensize  = function(w)          return _pensize(core, w) end
turtle.width    = turtle.pensize
turtle.pencolor = function(r, g, b, a) return _pencolor(core, r, g, b, a) end
turtle.fillcolor= function(r, g, b, a) return _fillcolor(core, r, g, b, a) end
turtle.color    = function(p, f)       return _color(core, p, f) end

turtle.begin_fill = function()         _begin_fill(core) end
turtle.end_fill   = function()         _do_end_fill(core) end
turtle.filling    = function()         return core:is_filling() end

turtle.dot        = function(s, r, g, b, a) _dot(core, s, r, g, b, a) end
turtle.write      = function(t, mv, al, f)  _write(core, t, mv, al, f) end
turtle.stamp      = function()         return _stamp(core) end
turtle.clearstamp = function(id)       _do_clearstamp(core, id) end
turtle.clearstamps= function(n)        _do_clearstamps(core, n) end

turtle.clear   = function()            _do_clear(core) end
turtle.reset   = function()            _do_reset(core) end

turtle.bgcolor = function(r, g, b, a)
    if r == nil then return screen:bgcolor() end
    core:_push_undo()
    screen:bgcolor(r, g, b, a)
    core:_commit_undo_segments()
    renderer:request_full_redraw()
    renderer:render()
end

turtle.position  = function()          return core:position() end
turtle.pos       = turtle.position
turtle.xcor      = function()          return core:xcor() end
turtle.ycor      = function()          return core:ycor() end
turtle.heading   = function()          return core:heading() end
turtle.isdown    = function()          return core:isdown() end
turtle.isvisible = function()          return core:isvisible() end
turtle.towards   = function(x, y)      return core:towards(x, y) end
turtle.distance  = function(x, y)      return core:distance(x, y) end

turtle.showturtle = function()         _showturtle(core) end
turtle.st         = turtle.showturtle
turtle.hideturtle = function()         _hideturtle(core) end
turtle.ht         = turtle.hideturtle

turtle.speed = function(n)
    if n == nil then return core:speed() end
    core:speed(n)
end

-- tracer/update for batch drawing (simultaneous multi-turtle movement)
turtle.tracer = function(n, _)
    if n == 0 then core:speed(0) end
end
turtle.update = function()
    renderer:request_full_redraw()
    renderer:render()
end

turtle.undo             = function()    _undo(core) end
turtle.setundobuffer    = function(n)   core:setundobuffer(n) end
turtle.undobufferentries= function()    return core:undobufferentries() end

-- Event loop
turtle.done     = function()
    _mainloop_entered = true
    renderer:request_full_redraw()
    renderer:mainloop()
end
turtle.mainloop = turtle.done
turtle.bye      = function() renderer:close() end

----------------------------------------------------------------
-- turtle.Turtle() — create an additional turtle on the same screen.
-- Returns a wrapper with method-style access: t:forward(100), t:color("red"), etc.
----------------------------------------------------------------

function turtle.Turtle()
    local t_core = Core.new(screen)
    return make_turtle_methods(t_core)
end

----------------------------------------------------------------
-- Export all module-level API functions as globals
----------------------------------------------------------------

for name, fn in pairs(turtle) do
    if type(fn) == "function" and not name:match("^_") then
        _G[name] = fn
    end
end

----------------------------------------------------------------
-- Undefined variable detection with "did you mean?" suggestions
----------------------------------------------------------------

local _api_names = {}
for name in pairs(turtle) do
    if not name:match("^_") then table.insert(_api_names, name) end
end

local function _editdist(s, t)
    s, t = s:lower(), t:lower()
    local m, n = #s, #t
    if m == 0 then return n end
    if n == 0 then return m end
    local prev = {}
    for j = 0, n do prev[j] = j end
    for i = 1, m do
        local curr = { [0] = i }
        for j = 1, n do
            local cost = s:sub(i, i) == t:sub(j, j) and 0 or 1
            curr[j] = math.min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
        end
        prev = curr
    end
    return prev[n]
end

local function _suggest(name)
    local best, best_d = nil, 3
    for _, known in ipairs(_api_names) do
        local d = _editdist(name, known)
        if d < best_d then best, best_d = known, d end
    end
    return best
end

setmetatable(_G, {
    __index = function(_, name)
        local msg = ("'%s' is not defined"):format(name)
        local suggestion = _suggest(name)
        if suggestion then
            msg = msg .. (" — did you mean '%s'?"):format(suggestion)
        end
        error(msg, 2)
    end
})

return turtle

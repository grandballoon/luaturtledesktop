-- turtle.lua
-- Entry point: require("turtle")
-- Creates a default turtle, wires core + renderer, exports API as globals.

local Core = require("turtle.core")
local Renderer = require("turtle.renderer")
local colors = require("turtle.colors")

----------------------------------------------------------------
-- Module table
----------------------------------------------------------------

local turtle = {}

-- Create default core and renderer
local core = Core.new()
local renderer = Renderer.new()
renderer.core = core
core.renderer = renderer

-- Expose core and renderer for advanced users
turtle._core = core
turtle._renderer = renderer

----------------------------------------------------------------
-- Helper: wrap a core method so it also triggers rendering
----------------------------------------------------------------

local function draw_cmd(method_name)
    return function(...)
        local result = {core[method_name](core, ...)}
        -- Render after each drawing command
        if core.speed_setting == 0 then
            -- Instant mode: just mark that we need to render, but defer
            -- until the next explicit render or done()
        else
            renderer:render()
        end
        if #result > 0 then
            return table.unpack(result)
        end
    end
end

-- State-only commands (no rendering needed)
local function state_cmd(method_name)
    return function(...)
        return core[method_name](core, ...)
    end
end

-- Query commands (return values, no rendering)
local function query_cmd(method_name)
    return function(...)
        return core[method_name](core, ...)
    end
end

----------------------------------------------------------------
-- Animated forward/back
-- When speed > 0, break movement into visible steps.
----------------------------------------------------------------

local function animated_forward(distance)
    distance = distance or 0
    if distance == 0 then
        core:forward(0)
        return
    end

    if core.speed_setting == 0 then
        -- Instant: just do it
        core:forward(distance)
        return
    end

    -- Break into steps for animation
    local step_size = 2  -- pixels per animation step
    local steps = math.max(1, math.floor(math.abs(distance) / step_size))
    local step_dist = distance / steps

    for i = 1, steps do
        core:forward(step_dist)
        renderer:render()
        renderer:_sleep(renderer:_frame_delay())
    end
end

local function animated_back(distance)
    animated_forward(-(distance or 0))
end

local function animated_right(angle)
    angle = angle or 0
    if angle == 0 or core.speed_setting == 0 then
        core:right(angle)
        if core.speed_setting ~= 0 then renderer:render() end
        return
    end

    local step_angle = 2  -- degrees per animation step
    local steps = math.max(1, math.floor(math.abs(angle) / step_angle))
    local step = angle / steps

    for i = 1, steps do
        core:right(step)
        renderer:render()
        renderer:_sleep(renderer:_frame_delay())
    end
end

local function animated_left(angle)
    animated_right(-(angle or 0))
end

local function animated_circle(radius, extent, steps)
    -- For animated circle, we let core handle the polygon decomposition
    -- but intercept the forward/left calls via the core directly.
    -- The simplest approach: just call core:circle which calls
    -- core:forward and core:left internally, then render.
    --
    -- For animation, we temporarily replace core methods... actually,
    -- core:circle already calls self:forward and self:left, which
    -- are on the core object. For animation we need to render between
    -- each step. The cleanest approach: replicate the circle logic here.

    radius = radius or 0
    extent = extent or 360
    if radius == 0 then return end

    local RAD = math.pi / 180

    if not steps then
        steps = math.max(4, math.floor(math.abs(extent) / 6))
    end

    local step_angle = extent / steps
    local step_len = 2 * math.abs(radius) * math.sin(math.abs(step_angle) / 2 * RAD)

    if radius < 0 then
        step_angle = -step_angle
    end

    for i = 1, steps do
        core:left(step_angle / 2)
        core:forward(step_len)
        core:left(step_angle / 2)
        if core.speed_setting ~= 0 then
            renderer:render()
            renderer:_sleep(renderer:_frame_delay())
        end
    end
    if core.speed_setting == 0 then
        renderer:render()
    end
end

----------------------------------------------------------------
-- Commands that trigger a full redraw
----------------------------------------------------------------

local function do_clear()
    core:clear()
    renderer.needs_full_redraw = true
    renderer:render()
end

local function do_reset()
    core:reset()
    renderer.needs_full_redraw = true
    renderer:render()
end

local function do_clearstamp(id)
    core:clearstamp(id)
    renderer.needs_full_redraw = true
    renderer:render()
end

local function do_clearstamps(n)
    core:clearstamps(n)
    renderer.needs_full_redraw = true
    renderer:render()
end

local function do_bgcolor(r, g, b, a)
    if r == nil then return core:bgcolor() end
    core:bgcolor(r, g, b, a)
    renderer.needs_full_redraw = true
    renderer:render()
end

----------------------------------------------------------------
-- Build API table and export globals
----------------------------------------------------------------

-- Movement (animated)
turtle.forward   = animated_forward
turtle.fd        = animated_forward
turtle.back      = animated_back
turtle.bk        = animated_back
turtle.backward  = animated_back
turtle.right     = animated_right
turtle.rt        = animated_right
turtle.left      = animated_left
turtle.lt        = animated_left
turtle.circle    = animated_circle

-- Absolute positioning (draw command)
turtle.setpos       = draw_cmd("setpos")
turtle.setposition  = draw_cmd("setpos")
turtle.setx         = draw_cmd("setx")
turtle.sety         = draw_cmd("sety")
turtle.setheading   = draw_cmd("setheading")
turtle.seth         = draw_cmd("setheading")
turtle.home         = draw_cmd("home")
turtle.teleport     = draw_cmd("teleport")

-- Pen control (state commands that trigger render for visual feedback)
turtle.penup     = function() core:penup() end
turtle.pu        = turtle.penup
turtle.up        = turtle.penup
turtle.pendown   = function() core:pendown() end
turtle.pd        = turtle.pendown
turtle.down      = turtle.pendown
turtle.pensize   = function(w) return core:pensize(w) end
turtle.width     = turtle.pensize
turtle.pencolor  = function(r, g, b, a) return core:pencolor(r, g, b, a) end
turtle.fillcolor = function(r, g, b, a) return core:fillcolor(r, g, b, a) end
turtle.color     = function(pen, fill) return core:color(pen, fill) end

-- Filling
turtle.begin_fill = function() core:begin_fill() end
turtle.end_fill   = function()
    core:end_fill()
    renderer:render()
end
turtle.filling    = function() return core:is_filling() end

-- Drawing extras
turtle.dot   = function(size, r, g, b, a)
    core:dot(size, r, g, b, a)
    renderer:render()
end
turtle.write = function(text, move, align, font)
    core:write(text, move, align, font)
    renderer:render()
end
turtle.stamp       = function()
    local id = core:stamp()
    renderer:render()
    return id
end
turtle.clearstamp  = do_clearstamp
turtle.clearstamps = do_clearstamps

-- Canvas
turtle.clear   = do_clear
turtle.reset   = do_reset
turtle.bgcolor = do_bgcolor

-- State queries
turtle.position  = query_cmd("position")
turtle.pos       = query_cmd("pos")
turtle.xcor      = query_cmd("xcor")
turtle.ycor      = query_cmd("ycor")
turtle.heading   = query_cmd("heading")
turtle.isdown    = query_cmd("isdown")
turtle.isvisible = query_cmd("isvisible")
turtle.towards   = query_cmd("towards")
turtle.distance  = query_cmd("distance")

-- Visibility
turtle.showturtle = function() core:showturtle(); renderer:render() end
turtle.st         = turtle.showturtle
turtle.hideturtle = function() core:hideturtle(); renderer:render() end
turtle.ht         = turtle.hideturtle

-- Speed
turtle.speed = function(n)
    if n == nil then return core:speed() end
    core:speed(n)
end

-- Degrees/radians mode (Python turtle compat)
turtle.degrees = function(fullcircle)
    -- For now, we only support degrees. Placeholder for future.
end
turtle.radians = function()
    -- Placeholder for future radians mode.
end

-- tracer/update for batch drawing
turtle.tracer = function(n, delay)
    -- tracer(0) = turn off animation (like speed(0) but different semantics)
    -- tracer(1) = normal
    -- For now, map to speed
    if n == 0 then
        core:speed(0)
    end
end
turtle.update = function()
    renderer.needs_full_redraw = true
    renderer:render()
end

-- Event loop
turtle.done     = function() renderer:mainloop() end
turtle.mainloop = turtle.done
turtle.bye      = function() renderer:close() end

----------------------------------------------------------------
-- Export all API functions as globals
-- This lets students write forward(100) instead of turtle.forward(100)
----------------------------------------------------------------

local _G = _G
for name, fn in pairs(turtle) do
    if type(fn) == "function" and not name:match("^_") then
        _G[name] = fn
    end
end

----------------------------------------------------------------
-- Render on first require if speed > 0
-- (Opens the window so it's visible even before any draw command)
----------------------------------------------------------------

-- Don't auto-open; window opens lazily on first draw command.
-- This matches Python turtle behavior.

return turtle

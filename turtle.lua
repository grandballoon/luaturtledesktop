-- turtle.lua
-- Entry point: require("turtle")
-- Creates a default turtle, wires core + renderer, exports API as globals.

local Core = require("turtle.core")
local Renderer = require("turtle.renderer")

----------------------------------------------------------------
-- Module table
----------------------------------------------------------------

local turtle = {}

-- Create default core and renderer
local core = Core.new()
local renderer = Renderer.new()
renderer.core = core
core.renderer = renderer

-- Expose for advanced users
turtle._core = core
turtle._renderer = renderer

----------------------------------------------------------------
-- Animated movement
-- When speed > 0, break movement into visible steps.
----------------------------------------------------------------

local function animated_forward(distance)
    distance = distance or 0
    if distance == 0 then
        core:forward(0)
        return
    end

    if core.speed_setting == 0 then
        core:forward(distance)
        return
    end

    -- Break into steps for animation
    local step_size = 2
    local steps = math.max(1, math.floor(math.abs(distance) / step_size))
    local step_dist = distance / steps
    local delay = renderer:frame_delay()

    for i = 1, steps do
        core:forward(step_dist)
        renderer:render()
        if delay > 0 then renderer:sleep(delay) end
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

    local step_angle = 2
    local steps = math.max(1, math.floor(math.abs(angle) / step_angle))
    local step = angle / steps
    local delay = renderer:frame_delay()

    for i = 1, steps do
        core:right(step)
        renderer:render()
        if delay > 0 then renderer:sleep(delay) end
    end
end

local function animated_left(angle)
    animated_right(-(angle or 0))
end

local function animated_circle(radius, extent, steps)
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

    local delay = renderer:frame_delay()

    for i = 1, steps do
        core:left(step_angle / 2)
        core:forward(step_len)
        core:left(step_angle / 2)
        if core.speed_setting ~= 0 then
            renderer:render()
            if delay > 0 then renderer:sleep(delay) end
        end
    end
end

----------------------------------------------------------------
-- Draw command wrapper (renders after state change)
----------------------------------------------------------------

local function draw_cmd(method_name)
    return function(...)
        local result = {core[method_name](core, ...)}
        if core.speed_setting ~= 0 then
            renderer:render()
        end
        if #result > 0 then
            return table.unpack(result)
        end
    end
end

----------------------------------------------------------------
-- Commands that need a full redraw
----------------------------------------------------------------

local function do_clear()
    core:clear()
    renderer:request_full_redraw()
    renderer:render()
end

local function do_reset()
    core:reset()
    renderer:request_full_redraw()
    renderer:render()
end

local function do_clearstamp(id)
    core:clearstamp(id)
    renderer:request_full_redraw()
    renderer:render()
end

local function do_clearstamps(n)
    core:clearstamps(n)
    renderer:request_full_redraw()
    renderer:render()
end

local function do_bgcolor(r, g, b, a)
    if r == nil then return core:bgcolor() end
    core:bgcolor(r, g, b, a)
    renderer:request_full_redraw()
    renderer:render()
end

----------------------------------------------------------------
-- Build API table
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

-- Absolute positioning
turtle.setpos       = draw_cmd("setpos")
turtle.setposition  = draw_cmd("setpos")
turtle.setx         = draw_cmd("setx")
turtle.sety         = draw_cmd("sety")
turtle.setheading   = draw_cmd("setheading")
turtle.seth         = draw_cmd("setheading")
turtle.home         = draw_cmd("home")
turtle.teleport     = function(x, y) core:teleport(x, y) end

-- Pen control
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
turtle.position  = function() return core:position() end
turtle.pos       = turtle.position
turtle.xcor      = function() return core:xcor() end
turtle.ycor      = function() return core:ycor() end
turtle.heading   = function() return core:heading() end
turtle.isdown    = function() return core:isdown() end
turtle.isvisible = function() return core:isvisible() end
turtle.towards   = function(x, y) return core:towards(x, y) end
turtle.distance  = function(x, y) return core:distance(x, y) end

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

-- tracer/update for batch drawing
turtle.tracer = function(n, delay)
    if n == 0 then core:speed(0) end
end
turtle.update = function()
    renderer:request_full_redraw()
    renderer:render()
end

-- Event loop
turtle.done     = function()
    -- Final render (important for speed(0) batch mode)
    renderer:request_full_redraw()
    renderer:mainloop()
end
turtle.mainloop = turtle.done
turtle.bye      = function() renderer:close() end

----------------------------------------------------------------
-- Export all API functions as globals
----------------------------------------------------------------

for name, fn in pairs(turtle) do
    if type(fn) == "function" and not name:match("^_") then
        _G[name] = fn
    end
end

return turtle

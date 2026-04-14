-- turtle.lua
-- Entry point: require("turtle")
-- Creates a default turtle, wires core + renderer, exports API as globals.

local Core = require("turtle.core")
local Renderer = require("turtle.renderer")

----------------------------------------------------------------
-- Module table
----------------------------------------------------------------

local turtle = {}

-- Derive window title from the running script name (arg[0])
local function script_title()
    local path = arg and arg[0]
    if not path then return "Lua Turtle" end
    local name = path:match("([^/\\]+)$") or path   -- strip directories
    return (name:match("^(.+)%.[^.]+$") or name)    -- strip extension
end

-- Create default core and renderer
local core = Core.new()
local renderer = Renderer.new({ title = script_title() })
renderer.core = core
core.renderer = renderer

-- Expose for advanced users
turtle._core = core
turtle._renderer = renderer

-- Graceful error recovery ------------------------------------------------
-- The standard Lua interpreter always calls lua_close after a script ends
-- (whether normally or via error), which runs __gc finalizers.  This sentinel
-- keeps the window open if the script exits without calling done(), so the
-- student can see what was drawn before the error.
--
-- Storing renderer inside the table (not just as a closure upvalue) ensures
-- it is kept alive until the finalizer fires.
local _mainloop_entered = false
-- Anchored to turtle._exit_sentinel so it stays alive (via package.loaded)
-- for the entire program lifetime.  __gc fires during lua_close, which the
-- standard Lua interpreter always calls after a script ends or errors.
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
-- Animated movement
-- When speed > 0, break movement into visible steps.
----------------------------------------------------------------

local function animated_forward(distance)
    distance = distance or 0
    core:_push_undo()

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
    core:_push_undo()
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
    core:_push_undo()
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
        core:_push_undo()
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
    core:_push_undo()
    core:clearstamp(id)
    renderer:request_full_redraw()
    renderer:render()
end

local function do_clearstamps(n)
    core:_push_undo()
    core:clearstamps(n)
    renderer:request_full_redraw()
    renderer:render()
end

local function do_bgcolor(r, g, b, a)
    if r == nil then return core:bgcolor() end
    core:_push_undo()
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
turtle.teleport     = function(x, y) core:_push_undo(); core:teleport(x, y) end

-- Pen control
turtle.penup     = function() core:_push_undo(); core:penup() end
turtle.pu        = turtle.penup
turtle.up        = turtle.penup
turtle.pendown   = function() core:_push_undo(); core:pendown() end
turtle.pd        = turtle.pendown
turtle.down      = turtle.pendown
turtle.pensize   = function(w)
    if w ~= nil then core:_push_undo() end
    return core:pensize(w)
end
turtle.width     = turtle.pensize
turtle.pencolor  = function(r, g, b, a)
    if r ~= nil then core:_push_undo() end
    return core:pencolor(r, g, b, a)
end
turtle.fillcolor = function(r, g, b, a)
    if r ~= nil then core:_push_undo() end
    return core:fillcolor(r, g, b, a)
end
turtle.color     = function(pen, fill)
    if pen ~= nil then core:_push_undo() end
    return core:color(pen, fill)
end

-- Filling
turtle.begin_fill = function() core:_push_undo(); core:begin_fill() end
turtle.end_fill   = function()
    core:_push_undo()
    core:end_fill()
    renderer:request_full_redraw()
    renderer:render()
end
turtle.filling    = function() return core:is_filling() end

-- Drawing extras
turtle.dot   = function(size, r, g, b, a)
    core:_push_undo()
    core:dot(size, r, g, b, a)
    renderer:render()
end
turtle.write = function(text, move, align, font)
    core:_push_undo()
    core:write(text, move, align, font)
    renderer:render()
end
turtle.stamp       = function()
    core:_push_undo()
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
turtle.showturtle = function() core:_push_undo(); core:showturtle(); renderer:render() end
turtle.st         = turtle.showturtle
turtle.hideturtle = function() core:_push_undo(); core:hideturtle(); renderer:render() end
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

-- Undo
turtle.undo = function()
    core:undo()
    renderer:request_full_redraw()
    renderer:render()
end
turtle.setundobuffer   = function(n) core:setundobuffer(n) end
turtle.undobufferentries = function() return core:undobufferentries() end

-- Event loop
turtle.done     = function()
    _mainloop_entered = true
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

----------------------------------------------------------------
-- 9.3: Undefined variable detection
-- __index on _G fires only when a name is NOT already in the global table,
-- so standard library globals (math, string, io …) and all exported turtle
-- functions are found normally.  Only genuine typos hit this handler.
----------------------------------------------------------------

-- Collect exported API names for "did you mean?" suggestions.
local _api_names = {}
for name in pairs(turtle) do
    if not name:match("^_") then
        table.insert(_api_names, name)
    end
end

-- Edit distance (Levenshtein) — used to find the closest API name.
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
    local best, best_d = nil, 3   -- only suggest when edit distance ≤ 2
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

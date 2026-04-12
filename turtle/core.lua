-- turtle/core.lua
-- Pure turtle state machine. No rendering dependencies.
-- Owns: position, heading, pen state, fill state, segment log, stamps.

local Core = {}
Core.__index = Core

function Core.new()
    local self = setmetatable({}, Core)

    -- Position and heading (turtle-space: center origin, y-up)
    self.x = 0
    self.y = 0
    self.angle = 0  -- degrees, 0=east, CCW positive

    -- Pen state
    self.pen_down = true
    self.pen_color = {1, 1, 1, 1}  -- RGBA, 0-1 range
    self.pen_size = 2

    -- Fill state
    self.filling = false
    self.fill_color = {1, 1, 1, 1}
    self.fill_vertices = {}

    -- Turtle appearance
    self.visible = true
    self.shape = "classic"  -- "arrow", "turtle", "circle", "square", "triangle", "classic"

    -- Canvas
    self.bg_color = {0, 0, 0, 1}

    -- Animation
    self.speed_setting = 5  -- 0=instant, 1=slowest, 10=fastest

    -- Segment log (append-only)
    self.segments = {}

    -- Line segments deferred during a fill so that end_fill() can log
    -- the fill polygon first, ensuring it renders behind the outline.
    self._fill_pending_segs = {}

    -- Stamp management
    self._next_stamp_id = 1
    self._cleared_stamps = {}  -- set of stamp IDs that have been cleared

    -- Mode: "standard" (0=east, CCW) or "logo" (0=north, CW)
    self.mode = "standard"

    -- Renderer (injected later)
    self.renderer = nil

    return self
end

----------------------------------------------------------------
-- Angle helpers
----------------------------------------------------------------

local RAD = math.pi / 180
local DEG = 180 / math.pi

function Core:_heading_rad()
    return self.angle * RAD
end

function Core:_dx_dy(distance)
    local rad = self:_heading_rad()
    return math.cos(rad) * distance, math.sin(rad) * distance
end

----------------------------------------------------------------
-- Color normalization
----------------------------------------------------------------

-- Accept (r,g,b) or (r,g,b,a). Auto-detect 0-1 vs 0-255 range.
function Core.normalize_color(r, g, b, a)
    a = a or 1
    -- If any channel > 1, treat all as 0-255
    if r > 1 or g > 1 or b > 1 or a > 1 then
        r, g, b, a = r / 255, g / 255, b / 255, a / 255
    end
    return {
        math.max(0, math.min(1, r)),
        math.max(0, math.min(1, g)),
        math.max(0, math.min(1, b)),
        math.max(0, math.min(1, a)),
    }
end

----------------------------------------------------------------
-- Segment log
----------------------------------------------------------------

function Core:_log(entry)
    -- Defer line segments drawn during a fill so the fill polygon can be
    -- logged first at end_fill(), keeping it behind the outline in draw order.
    if self.filling and entry.type == "line" then
        table.insert(self._fill_pending_segs, entry)
        return
    end
    table.insert(self.segments, entry)
    return #self.segments
end

----------------------------------------------------------------
-- Movement
----------------------------------------------------------------

function Core:forward(distance)
    distance = distance or 0
    local dx, dy = self:_dx_dy(distance)
    local x0, y0 = self.x, self.y
    self.x = self.x + dx
    self.y = self.y + dy

    if self.pen_down and distance ~= 0 then
        self:_log({
            type = "line",
            from = {x0, y0},
            to = {self.x, self.y},
            color = {table.unpack(self.pen_color)},
            width = self.pen_size,
        })
    end

    if self.filling then
        table.insert(self.fill_vertices, {self.x, self.y})
    end
end

function Core:back(distance)
    self:forward(-(distance or 0))
end

function Core:right(angle)
    -- Right = clockwise = negative in standard math convention
    self.angle = self.angle - (angle or 0)
end

function Core:left(angle)
    self.angle = self.angle + (angle or 0)
end

----------------------------------------------------------------
-- Absolute positioning
----------------------------------------------------------------

function Core:setpos(x, y)
    -- If x is a table, unpack it
    if type(x) == "table" then
        x, y = x[1], x[2]
    end
    local x0, y0 = self.x, self.y
    self.x = x
    self.y = y

    if self.pen_down then
        self:_log({
            type = "line",
            from = {x0, y0},
            to = {self.x, self.y},
            color = {table.unpack(self.pen_color)},
            width = self.pen_size,
        })
    end

    if self.filling then
        table.insert(self.fill_vertices, {self.x, self.y})
    end
end

function Core:setx(x)
    self:setpos(x, self.y)
end

function Core:sety(y)
    self:setpos(self.x, y)
end

function Core:setheading(angle)
    self.angle = angle or 0
end

function Core:home()
    self:setpos(0, 0)
    self:setheading(0)
end

function Core:teleport(x, y)
    -- Move without drawing, regardless of pen state
    if type(x) == "table" then
        x, y = x[1], x[2]
    end
    self.x = x or self.x
    self.y = y or self.y
    -- No segment logged, even if pen is down
    if self.filling then
        table.insert(self.fill_vertices, {self.x, self.y})
    end
end

----------------------------------------------------------------
-- Circle / Arc
----------------------------------------------------------------

-- Python turtle convention: circle center is radius units to the LEFT
-- of the turtle. Positive radius = CCW arc, negative = CW arc.
-- extent = degrees of arc (default 360). steps = polygon segments.
function Core:circle(radius, extent, steps)
    radius = radius or 0
    extent = extent or 360
    if radius == 0 then return end

    -- Default steps: ~1 segment per 6 degrees, minimum 4
    if not steps then
        steps = math.max(4, math.floor(math.abs(extent) / 6))
    end

    local step_angle = extent / steps
    local step_len = 2 * math.abs(radius) * math.sin(math.abs(step_angle) / 2 * RAD)

    -- Negative radius means the circle center is to the right
    -- which effectively mirrors the arc
    if radius < 0 then
        step_angle = -step_angle
    end

    for i = 1, steps do
        self:left(step_angle / 2)
        self:forward(step_len)
        self:left(step_angle / 2)
    end
end

----------------------------------------------------------------
-- Pen control
----------------------------------------------------------------

function Core:penup()
    self.pen_down = false
end

function Core:pendown()
    self.pen_down = true
end

function Core:pensize(width)
    if width then
        self.pen_size = math.max(1, width)
    end
    return self.pen_size
end

function Core:pencolor(r, g, b, a)
    if r == nil then
        return table.unpack(self.pen_color)
    end
    if type(r) == "string" then
        -- Named color lookup (deferred to colors.lua integration)
        local colors = require("turtle.colors")
        local c = colors[r:lower()]
        if c then
            self.pen_color = {c[1], c[2], c[3], c[4] or 1}
        end
        return
    end
    self.pen_color = Core.normalize_color(r, g, b, a)
end

function Core:fillcolor(r, g, b, a)
    if r == nil then
        return table.unpack(self.fill_color)
    end
    if type(r) == "string" then
        local colors = require("turtle.colors")
        local c = colors[r:lower()]
        if c then
            self.fill_color = {c[1], c[2], c[3], c[4] or 1}
        end
        return
    end
    self.fill_color = Core.normalize_color(r, g, b, a)
end

function Core:color(pen, fill)
    -- Dual setter/getter like Python turtle.
    -- color()          → returns pen_color, fill_color
    -- color(c)         → sets both pen and fill to c (Python behavior)
    -- color(pen, fill) → sets pen and fill independently
    if pen == nil and fill == nil then
        return self.pen_color, self.fill_color
    end
    if fill == nil then
        fill = pen  -- single arg: apply to both
    end
    if pen then
        if type(pen) == "string" then
            self:pencolor(pen)
        elseif type(pen) == "table" then
            self:pencolor(pen[1], pen[2], pen[3], pen[4])
        end
    end
    if fill then
        if type(fill) == "string" then
            self:fillcolor(fill)
        elseif type(fill) == "table" then
            self:fillcolor(fill[1], fill[2], fill[3], fill[4])
        end
    end
end

----------------------------------------------------------------
-- Filling
----------------------------------------------------------------

function Core:begin_fill()
    self.filling = true
    self.fill_vertices = {{self.x, self.y}}
    self._fill_pending_segs = {}
end

function Core:end_fill()
    if not self.filling then return end
    self.filling = false  -- cleared before _log so deferred check is skipped

    -- Log the fill polygon FIRST so the renderer draws it behind the outline.
    if #self.fill_vertices >= 3 then
        self:_log({
            type = "fill",
            vertices = self.fill_vertices,
            color = {table.unpack(self.fill_color)},
        })
    end
    -- Flush the deferred line segments; they land after fill in the log,
    -- so the incremental renderer draws them on top of the fill.
    for _, seg in ipairs(self._fill_pending_segs) do
        table.insert(self.segments, seg)
    end
    self._fill_pending_segs = {}
    self.fill_vertices = {}
end

function Core:is_filling()
    return self.filling
end

----------------------------------------------------------------
-- Drawing extras
----------------------------------------------------------------

function Core:dot(size, r, g, b, a)
    size = size or math.max(self.pen_size + 4, self.pen_size * 2)
    local color
    if r then
        if type(r) == "string" then
            local colors = require("turtle.colors")
            color = colors[r:lower()] or self.pen_color
        else
            color = Core.normalize_color(r, g, b, a)
        end
    else
        color = {table.unpack(self.pen_color)}
    end

    self:_log({
        type = "dot",
        pos = {self.x, self.y},
        size = size,
        color = color,
    })
end

function Core:write(text, move, align, font)
    text = tostring(text or "")
    align = align or "left"
    -- font: {family, size, style} or nil for default

    self:_log({
        type = "text",
        pos = {self.x, self.y},
        content = text,
        align = align,
        font = font,
        color = {table.unpack(self.pen_color)},
    })
end

----------------------------------------------------------------
-- Stamps
----------------------------------------------------------------

function Core:stamp()
    local id = self._next_stamp_id
    self._next_stamp_id = id + 1

    self:_log({
        type = "stamp",
        id = id,
        pos = {self.x, self.y},
        heading = self.angle,
        shape = self.shape,
        color = {table.unpack(self.pen_color)},
        fill_color = {table.unpack(self.fill_color)},
        size = self.pen_size,
    })

    return id
end

function Core:clearstamp(stamp_id)
    self._cleared_stamps[stamp_id] = true
    -- Renderer must redraw from log, skipping this stamp
end

function Core:clearstamps(n)
    -- Clear first n stamps (or last n if negative, or all if nil)
    local stamp_ids = {}
    for i, seg in ipairs(self.segments) do
        if seg.type == "stamp" and not self._cleared_stamps[seg.id] then
            table.insert(stamp_ids, seg.id)
        end
    end

    if n == nil then
        for _, id in ipairs(stamp_ids) do
            self._cleared_stamps[id] = true
        end
    elseif n > 0 then
        for i = 1, math.min(n, #stamp_ids) do
            self._cleared_stamps[stamp_ids[i]] = true
        end
    elseif n < 0 then
        for i = #stamp_ids + n + 1, #stamp_ids do
            if i >= 1 then
                self._cleared_stamps[stamp_ids[i]] = true
            end
        end
    end
end

----------------------------------------------------------------
-- Canvas operations
----------------------------------------------------------------

function Core:clear()
    -- Clear drawing, preserve turtle state.
    -- Also cancels any in-progress fill so pending segments don't leak.
    self.filling = false
    self._fill_pending_segs = {}
    self.fill_vertices = {}
    self:_log({ type = "clear" })
end

function Core:reset()
    -- Clear drawing AND reset turtle state
    self.x = 0
    self.y = 0
    self.angle = 0
    self.pen_down = true
    self.pen_color = {1, 1, 1, 1}
    self.pen_size = 2
    self.filling = false
    self.fill_vertices = {}
    self.fill_color = {1, 1, 1, 1}
    self._fill_pending_segs = {}
    self.visible = true
    self._cleared_stamps = {}
    self:_log({ type = "clear" })
end

function Core:bgcolor(r, g, b, a)
    if r == nil then
        return table.unpack(self.bg_color)
    end
    if type(r) == "string" then
        local colors = require("turtle.colors")
        local c = colors[r:lower()]
        if c then
            self.bg_color = {c[1], c[2], c[3], c[4] or 1}
        end
        return
    end
    self.bg_color = Core.normalize_color(r, g, b, a)
end

----------------------------------------------------------------
-- State queries
----------------------------------------------------------------

function Core:position()
    return self.x, self.y
end

function Core:pos()
    return self.x, self.y
end

function Core:xcor()
    return self.x
end

function Core:ycor()
    return self.y
end

function Core:heading()
    return self.angle
end

function Core:isdown()
    return self.pen_down
end

function Core:isvisible()
    return self.visible
end

function Core:towards(x, y)
    if type(x) == "table" then
        x, y = x[1], x[2]
    end
    local dx = x - self.x
    local dy = y - self.y
    return math.atan(dy, dx) * DEG
end

function Core:distance(x, y)
    if type(x) == "table" then
        x, y = x[1], x[2]
    end
    local dx = x - self.x
    local dy = y - self.y
    return math.sqrt(dx * dx + dy * dy)
end

----------------------------------------------------------------
-- Turtle visibility
----------------------------------------------------------------

function Core:showturtle()
    self.visible = true
end

function Core:hideturtle()
    self.visible = false
end

----------------------------------------------------------------
-- Speed
----------------------------------------------------------------

function Core:speed(n)
    if n == nil then
        return self.speed_setting
    end
    self.speed_setting = math.max(0, math.min(10, math.floor(n)))
end

----------------------------------------------------------------
-- Segment replay (for renderer to use on redraw)
----------------------------------------------------------------

-- Returns an iterator over visible segments (skipping cleared stamps,
-- only showing segments after the last clear)
function Core:visible_segments()
    -- Find the last "clear" entry
    local start = 1
    for i = #self.segments, 1, -1 do
        if self.segments[i].type == "clear" then
            start = i + 1
            break
        end
    end

    local results = {}
    for i = start, #self.segments do
        local seg = self.segments[i]
        if seg.type == "stamp" then
            if not self._cleared_stamps[seg.id] then
                table.insert(results, seg)
            end
        elseif seg.type ~= "clear" then
            table.insert(results, seg)
        end
    end
    return results
end

return Core

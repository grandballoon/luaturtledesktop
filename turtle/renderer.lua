-- turtle/renderer.lua
-- Cairo + SDL2 rendering backend for turtle graphics.
-- Owns: window, persistent canvas surface, coordinate transform,
-- drawing primitives, animation timing, full redraw from segment log.

local cairo = require("turtlecairo")

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Renderer)

    self.width  = opts.width  or 800
    self.height = opts.height or 600
    self.title  = opts.title  or "Lua Turtle"

    self.initialized = false

    -- screen owns the segment log and bg_color; set by turtle.lua via opts.
    self.screen = opts.screen or nil
    -- core is the default turtle; set by turtle.lua.
    self.core   = nil

    -- Track what we've drawn to the persistent canvas
    self.committed_up_to = 0
    self.needs_full_redraw = true

    return self
end

----------------------------------------------------------------
-- Initialization (lazy — called on first draw)
----------------------------------------------------------------

function Renderer:ensure_init()
    if self.initialized then return true end

    cairo.init_window(self.width, self.height, self.title)
    cairo.create_canvas(self.width, self.height)

    self.initialized = true
    return true
end

----------------------------------------------------------------
-- Coordinate transform
----------------------------------------------------------------

-- Turtle-space (center origin, y-up) → screen-space (top-left origin, y-down)
function Renderer:turtle_to_screen(tx, ty)
    local w = cairo.get_screen_width()
    local h = cairo.get_screen_height()
    local sx = w / 2 + tx
    local sy = h / 2 - ty   -- flip y
    return sx, sy
end

----------------------------------------------------------------
-- Color encoding
----------------------------------------------------------------

-- Convert {r, g, b, a} in 0-1 range to 0-255 integers
function Renderer:color255(c)
    return
        math.floor(c[1] * 255),
        math.floor(c[2] * 255),
        math.floor(c[3] * 255),
        math.floor((c[4] or 1) * 255)
end

----------------------------------------------------------------
-- Drawing a single segment to the persistent canvas
----------------------------------------------------------------

function Renderer:_draw_segment(seg)
    if seg.type == "line" then
        local x1, y1 = self:turtle_to_screen(seg.from[1], seg.from[2])
        local x2, y2 = self:turtle_to_screen(seg.to[1], seg.to[2])
        local r, g, b, a = self:color255(seg.color)
        cairo.draw_line(x1, y1, x2, y2, r, g, b, a, seg.width or 2)

    elseif seg.type == "fill" then
        -- Convert vertices to screen coords
        local screen_verts = {}
        for _, v in ipairs(seg.vertices) do
            local sx, sy = self:turtle_to_screen(v[1], v[2])
            table.insert(screen_verts, {sx, sy})
        end
        local r, g, b, a = self:color255(seg.color)
        cairo.draw_polygon_fill(screen_verts, r, g, b, a)

    elseif seg.type == "dot" then
        local x, y = self:turtle_to_screen(seg.pos[1], seg.pos[2])
        local r, g, b, a = self:color255(seg.color)
        cairo.draw_circle(x, y, seg.size / 2, r, g, b, a)

    elseif seg.type == "text" then
        local x, y = self:turtle_to_screen(seg.pos[1], seg.pos[2])
        local r, g, b, a = self:color255(seg.color)
        local size = 20
        if seg.font and seg.font[2] then
            size = seg.font[2]
        end
        -- cairo.draw_text positions text with its visual top at y
        cairo.draw_text(seg.content, x, y, size, r, g, b, a)

    elseif seg.type == "stamp" then
        self:_draw_turtle_shape(
            seg.pos[1], seg.pos[2], seg.heading,
            seg.color, seg.fill_color, seg.size
        )
    end
end

----------------------------------------------------------------
-- Turtle head shape
----------------------------------------------------------------

function Renderer:_draw_turtle_shape(tx, ty, heading, pen_color, fill_color, size)
    local rad    = heading * math.pi / 180
    local len    = (size or 2) * 6
    local half_w = len * 0.4

    local cos_h = math.cos(rad)
    local sin_h = math.sin(rad)
    local cos_p = math.cos(rad + math.pi / 2)
    local sin_p = math.sin(rad + math.pi / 2)

    -- Three vertices of the arrow in turtle-space
    local tip_x   = tx + cos_h * len
    local tip_y   = ty + sin_h * len
    local left_x  = tx - cos_h * len * 0.3 + cos_p * half_w
    local left_y  = ty - sin_h * len * 0.3 + sin_p * half_w
    local right_x = tx - cos_h * len * 0.3 - cos_p * half_w
    local right_y = ty - sin_h * len * 0.3 - sin_p * half_w

    -- Convert to screen coords
    local sx1, sy1 = self:turtle_to_screen(tip_x,   tip_y)
    local sx2, sy2 = self:turtle_to_screen(left_x,  left_y)
    local sx3, sy3 = self:turtle_to_screen(right_x, right_y)

    -- Fill (polygon)
    if fill_color then
        local r, g, b, a = self:color255(fill_color)
        cairo.draw_polygon_fill({{sx1,sy1},{sx2,sy2},{sx3,sy3}}, r, g, b, a)
    end

    -- Outline (three edges)
    if pen_color then
        local r, g, b, a = self:color255(pen_color)
        local lw = size or 2
        cairo.draw_line(sx1, sy1, sx2, sy2, r, g, b, a, lw)
        cairo.draw_line(sx2, sy2, sx3, sy3, r, g, b, a, lw)
        cairo.draw_line(sx3, sy3, sx1, sy1, r, g, b, a, lw)
    end
end

----------------------------------------------------------------
-- Full render frame
----------------------------------------------------------------

function Renderer:_render_frame()
    if not self.initialized or not self.core or not self.screen then return end

    -- Check for window resize
    local w = cairo.get_screen_width()
    local h = cairo.get_screen_height()
    if w ~= self.width or h ~= self.height then
        self.width  = w
        self.height = h
        cairo.resize_canvas(w, h)
        self.needs_full_redraw = true
    end

    local screen = self.screen

    -- Update the persistent canvas with new segments
    if self.needs_full_redraw then
        -- Clear and replay all visible segments onto the canvas
        local br, bg, bb, ba = self:color255(screen.bg_color)
        cairo.clear_canvas(br, bg, bb, ba)

        cairo.begin_canvas()
        local visible = screen:visible_segments()
        -- Draw fill polygons first so they appear behind lines/dots/text.
        for _, seg in ipairs(visible) do
            if seg.type == "fill" then self:_draw_segment(seg) end
        end
        for _, seg in ipairs(visible) do
            if seg.type ~= "fill" then self:_draw_segment(seg) end
        end
        cairo.end_canvas()

        self.committed_up_to = #screen.segments
        self.needs_full_redraw = false

    elseif self.committed_up_to < #screen.segments then
        -- Incremental: draw only new segments
        cairo.begin_canvas()
        local segs = screen.segments
        for i = self.committed_up_to + 1, #segs do
            local seg = segs[i]
            if seg.type == "clear" then
                self.needs_full_redraw = true
                cairo.end_canvas()
                self:_render_frame()
                return
            elseif seg.type == "stamp" and screen._cleared_stamps[seg.id] then
                -- skip cleared stamp
            else
                self:_draw_segment(seg)
            end
        end
        cairo.end_canvas()
        self.committed_up_to = #screen.segments
    end

    -- Frame: overlay (turtle heads) on top of canvas
    cairo.begin_drawing()   -- clears overlay, routes draw calls there

    -- Draw all visible turtle heads onto the overlay
    for _, t in ipairs(screen.turtles) do
        if t.visible then
            self:_draw_turtle_shape(t.x, t.y, t.angle, t.pen_color, t.fill_color)
        end
    end

    -- Draw undo-erase temp line if active (shrinks each frame as turtle walks back)
    if self._temp_line then
        local tl = self._temp_line
        local x1, y1 = self:turtle_to_screen(tl.from[1], tl.from[2])
        local x2, y2 = self:turtle_to_screen(tl.to[1],   tl.to[2])
        local r, g, b, a = self:color255(tl.color)
        cairo.draw_line(x1, y1, x2, y2, r, g, b, a, tl.width or 2)
    end

    local br, bg, bb, ba = self:color255(screen.bg_color)
    cairo.clear(br, bg, bb, ba)   -- store background color for end_drawing
    cairo.end_drawing()           -- compose canvas + overlay + bg, present
end

----------------------------------------------------------------
-- Public interface
----------------------------------------------------------------

function Renderer:render()
    if not self:ensure_init() then return end
    self:_render_frame()
    if cairo.window_should_close() then
        cairo.close_window()
        os.exit(0)
    end
end

function Renderer:request_full_redraw()
    self.needs_full_redraw = true
end

function Renderer:sleep(seconds)
    if seconds <= 0 then return end
    cairo.wait(seconds)
end

function Renderer:frame_delay()
    if not self.core then return 0 end
    local s = self.core.speed_setting
    if s == 0 then return 0 end
    -- Exponential scale: speed 1 ~23ms/step, speed 10 ~0.5ms/step (~45x range)
    return 0.023 * (0.65 ^ (s - 1))
end

-- Keep the window open until user closes it
function Renderer:mainloop()
    if not self.initialized then return end
    self:_render_frame()
    while not cairo.window_should_close() do
        self:_render_frame()
    end
    cairo.close_window()
end

-- Returns true if the OS has signalled that the window should close.
-- Useful for REPL mode where the loop needs to break cleanly.
-- Note: render() already calls os.exit(0) on close, so this is a
-- belt-and-suspenders check for callers that want explicit control.
function Renderer:window_should_close()
    if not self.initialized then return false end
    return cairo.window_should_close()
end

function Renderer:close()
    if self.initialized then
        cairo.close_window()
        self.initialized = false
    end
end

return Renderer

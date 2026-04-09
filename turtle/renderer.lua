-- turtle/renderer.lua
-- Raylib rendering backend for turtle graphics.
-- Owns: window, render texture (persistent canvas), coordinate transform,
-- drawing primitives, animation timing, full redraw from segment log.

local ray = require("turtleray")

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Renderer)

    self.width = opts.width or 800
    self.height = opts.height or 600
    self.title = opts.title or "Lua Turtle"

    self.initialized = false

    -- Reference to the core (set by turtle.lua)
    self.core = nil

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

    ray.init_window(self.width, self.height, self.title)
    -- Disable fps cap during script execution; animated steps control timing
    -- via explicit sleep() calls. Re-enabled in mainloop() for the idle loop.
    ray.set_target_fps(0)

    -- Create offscreen render texture for persistent drawing
    ray.create_canvas(self.width, self.height)

    self.initialized = true
    return true
end

----------------------------------------------------------------
-- Coordinate transform
----------------------------------------------------------------

-- Turtle-space (center origin, y-up) → screen-space (top-left origin, y-down)
function Renderer:turtle_to_screen(tx, ty)
    local w = ray.get_screen_width()
    local h = ray.get_screen_height()
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
        ray.draw_line(x1, y1, x2, y2, r, g, b, a, seg.width or 2)

    elseif seg.type == "fill" then
        -- Convert vertices to screen coords
        local screen_verts = {}
        for _, v in ipairs(seg.vertices) do
            local sx, sy = self:turtle_to_screen(v[1], v[2])
            table.insert(screen_verts, {sx, sy})
        end
        local r, g, b, a = self:color255(seg.color)
        ray.draw_polygon_fill(screen_verts, r, g, b, a)

    elseif seg.type == "dot" then
        local x, y = self:turtle_to_screen(seg.pos[1], seg.pos[2])
        local r, g, b, a = self:color255(seg.color)
        ray.draw_circle(x, y, seg.size / 2, r, g, b, a)

    elseif seg.type == "text" then
        local x, y = self:turtle_to_screen(seg.pos[1], seg.pos[2])
        local r, g, b, a = self:color255(seg.color)
        local size = 20
        if seg.font and seg.font[2] then
            size = seg.font[2]
        end
        -- Adjust y for text (raylib draws from top-left of text)
        ray.draw_text(seg.content, x, y - size, size, r, g, b, a)

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
    local rad = heading * math.pi / 180
    local len = (size or 2) * 6
    local half_w = len * 0.4

    local cos_h = math.cos(rad)
    local sin_h = math.sin(rad)
    local cos_p = math.cos(rad + math.pi / 2)
    local sin_p = math.sin(rad + math.pi / 2)

    -- Three vertices of the arrow in turtle-space
    local tip_x = tx + cos_h * len
    local tip_y = ty + sin_h * len
    local left_x = tx - cos_h * len * 0.3 + cos_p * half_w
    local left_y = ty - sin_h * len * 0.3 + sin_p * half_w
    local right_x = tx - cos_h * len * 0.3 - cos_p * half_w
    local right_y = ty - sin_h * len * 0.3 - sin_p * half_w

    -- Convert to screen coords
    local sx1, sy1 = self:turtle_to_screen(tip_x, tip_y)
    local sx2, sy2 = self:turtle_to_screen(left_x, left_y)
    local sx3, sy3 = self:turtle_to_screen(right_x, right_y)

    -- Fill
    if fill_color then
        local r, g, b, a = self:color255(fill_color)
        ray.draw_triangle_fill(sx1, sy1, sx2, sy2, sx3, sy3, r, g, b, a)
    end
end

----------------------------------------------------------------
-- Full render frame
----------------------------------------------------------------

function Renderer:_render_frame()
    if not self.initialized or not self.core then return end

    -- Check for window resize
    local w = ray.get_screen_width()
    local h = ray.get_screen_height()
    if w ~= self.width or h ~= self.height then
        self.width = w
        self.height = h
        ray.resize_canvas(w, h)
        self.needs_full_redraw = true
    end

    -- Update the persistent canvas with new segments
    if self.needs_full_redraw then
        -- Clear and replay all visible segments onto the canvas
        local br, bg, bb, ba = self:color255(self.core.bg_color)
        ray.clear_canvas(br, bg, bb, ba)

        ray.begin_canvas()
        local visible = self.core:visible_segments()
        for _, seg in ipairs(visible) do
            self:_draw_segment(seg)
        end
        ray.end_canvas()

        self.committed_up_to = #self.core.segments
        self.needs_full_redraw = false

    elseif self.committed_up_to < #self.core.segments then
        -- Incremental: draw only new segments
        ray.begin_canvas()
        local segs = self.core.segments
        for i = self.committed_up_to + 1, #segs do
            local seg = segs[i]
            if seg.type == "clear" then
                self.needs_full_redraw = true
                ray.end_canvas()
                self:_render_frame()
                return
            elseif seg.type == "stamp" and self.core._cleared_stamps[seg.id] then
                -- skip
            else
                self:_draw_segment(seg)
            end
        end
        ray.end_canvas()
        self.committed_up_to = #self.core.segments
    end

    -- Now draw a frame: canvas + turtle head overlay
    ray.begin_drawing()
    local br, bg, bb, ba = self:color255(self.core.bg_color)
    ray.clear(br, bg, bb, ba)

    -- Draw the persistent canvas
    ray.draw_canvas()

    -- Draw the turtle head (ephemeral — not on the persistent canvas)
    if self.core.visible then
        self:_draw_turtle_shape(
            self.core.x, self.core.y, self.core.angle,
            self.core.pen_color,
            {0.3, 0.8, 0.3, 0.8}  -- green-ish fill
        )
    end

    ray.end_drawing()
end

----------------------------------------------------------------
-- Public interface
----------------------------------------------------------------

function Renderer:render()
    if not self:ensure_init() then return end
    self:_render_frame()
end

function Renderer:request_full_redraw()
    self.needs_full_redraw = true
end

function Renderer:sleep(seconds)
    if seconds <= 0 then return end
    ray.wait(seconds)
end

function Renderer:frame_delay()
    if not self.core then return 0 end
    local s = self.core.speed_setting
    if s == 0 then return 0 end
    -- Exponential scale: speed 1 ~90ms/step, speed 10 ~2ms/step (~45x range)
    return 0.09 * (0.65 ^ (s - 1))
end

-- Keep the window open until user closes it
function Renderer:mainloop()
    if not self.initialized then return end
    ray.set_target_fps(60)  -- Re-enable fps cap for idle loop
    self:_render_frame()
    while not ray.window_should_close() do
        self:_render_frame()
    end
    ray.close_window()
end

function Renderer:close()
    if self.initialized then
        ray.close_window()
        self.initialized = false
    end
end

return Renderer

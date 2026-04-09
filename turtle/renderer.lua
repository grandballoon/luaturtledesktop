-- turtle/renderer.lua
-- IUP + CD rendering backend.
-- Owns: window, canvas, coordinate transform, drawing, animation timing.
-- Requires: iuplua, cdlua, iupluacd (and optionally cdluacontextplus)

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Renderer)

    self.width = opts.width or 800
    self.height = opts.height or 600
    self.title = opts.title or "Lua Turtle"

    -- IUP/CD objects (created lazily on first draw)
    self.dialog = nil
    self.iup_canvas = nil
    self.cd_canvas = nil       -- double-buffered CD canvas
    self.initialized = false

    -- Reference to the core (set by turtle.lua)
    self.core = nil

    -- Rendering bookkeeping
    self.committed_up_to = 0   -- index into core.segments we've drawn so far
    self.needs_full_redraw = true

    return self
end

----------------------------------------------------------------
-- Initialization (lazy — called on first draw)
----------------------------------------------------------------

function Renderer:ensure_init()
    if self.initialized then return true end

    -- Load IUP and CD in the correct order
    local ok, err

    ok, err = pcall(require, "iuplua")
    if not ok then
        io.stderr:write("turtle: failed to load iuplua: " .. tostring(err) .. "\n")
        io.stderr:write("Install IUP: https://sourceforge.net/projects/iup/files/\n")
        return false
    end

    ok, err = pcall(require, "cdlua")
    if not ok then
        io.stderr:write("turtle: failed to load cdlua: " .. tostring(err) .. "\n")
        return false
    end

    ok, err = pcall(require, "iupluacd")
    if not ok then
        io.stderr:write("turtle: failed to load iupluacd: " .. tostring(err) .. "\n")
        return false
    end

    -- Try to enable context plus (Cairo on Linux, GDI+ on Windows)
    -- for alpha transparency and anti-aliasing support.
    -- Not fatal if unavailable — we fall back to base drivers.
    self.has_context_plus = false
    ok, _ = pcall(function()
        require("cdluacontextplus")
        cd.UseContextPlus(1)
        self.has_context_plus = true
    end)
    if not self.has_context_plus then
        -- Try the Cairo-specific module name as fallback
        ok, _ = pcall(function()
            require("cdluacairo")
            cd.UseContextPlus(1)
            self.has_context_plus = true
        end)
    end

    -- Create IUP canvas widget
    self.iup_canvas = iup.canvas{
        bgcolor = "0 0 0",
        rastersize = self.width .. "x" .. self.height,
        border = "NO",
    }

    -- Create dialog
    self.dialog = iup.dialog{
        self.iup_canvas;
        title = self.title,
        size = nil,  -- let rastersize determine initial size
    }

    -- Canvas callbacks
    local renderer = self

    function self.iup_canvas:map_cb()
        -- Create double-buffered CD canvas
        local cv = cd.CreateCanvas(cd.IUP, self)
        if cv then
            renderer.cd_canvas = cd.CreateCanvas(cd.DBUFFER, cv)
            if renderer.cd_canvas then
                renderer.cd_canvas:Activate()
            end
        end
    end

    function self.iup_canvas:action()
        renderer.needs_full_redraw = true
        renderer:_redraw()
    end

    function self.iup_canvas:resize_cb(w, h)
        renderer.width = w
        renderer.height = h
        renderer.needs_full_redraw = true
    end

    -- Show the dialog
    self.dialog:showxy(iup.CENTER, iup.CENTER)

    -- Allow rastersize to be overridden by user resizing after initial show
    self.iup_canvas.rastersize = nil

    self.initialized = true
    return true
end

----------------------------------------------------------------
-- Coordinate transform
----------------------------------------------------------------

-- Turtle-space (center origin, y-up) → CD canvas coordinates.
-- CD's default is bottom-left origin, y-up, so we just translate
-- to center the origin.

function Renderer:turtle_to_canvas(tx, ty)
    local cx = self.width / 2 + tx
    local cy = self.height / 2 + ty  -- CD is y-up, same as turtle-space
    return cx, cy
end

----------------------------------------------------------------
-- Color encoding
----------------------------------------------------------------

function Renderer:encode_color(c)
    -- c is {r, g, b, a} in 0-1 range
    local r = math.floor(c[1] * 255)
    local g = math.floor(c[2] * 255)
    local b = math.floor(c[3] * 255)
    local encoded = cd.EncodeColor(r, g, b)
    if c[4] and c[4] < 1 and self.has_context_plus then
        local a = math.floor(c[4] * 255)
        encoded = cd.EncodeAlpha(encoded, a)
    end
    return encoded
end

----------------------------------------------------------------
-- Drawing primitives
----------------------------------------------------------------

function Renderer:_draw_segment(seg)
    local cv = self.cd_canvas
    if not cv then return end

    if seg.type == "line" then
        cv:SetForeground(self:encode_color(seg.color))
        cv:LineWidth(seg.width or 2)
        cv:LineStyle(cd.CONTINUOUS)
        local x1, y1 = self:turtle_to_canvas(seg.from[1], seg.from[2])
        local x2, y2 = self:turtle_to_canvas(seg.to[1], seg.to[2])
        cv:Line(x1, y1, x2, y2)

    elseif seg.type == "fill" then
        cv:SetForeground(self:encode_color(seg.color))
        cv:Begin(cd.FILL)
        for _, v in ipairs(seg.vertices) do
            local x, y = self:turtle_to_canvas(v[1], v[2])
            cv:Vertex(x, y)
        end
        cv:End()

    elseif seg.type == "dot" then
        cv:SetForeground(self:encode_color(seg.color))
        local x, y = self:turtle_to_canvas(seg.pos[1], seg.pos[2])
        cv:Sector(x, y, seg.size, seg.size, 0, 360)

    elseif seg.type == "text" then
        cv:SetForeground(self:encode_color(seg.color))
        if seg.font then
            local family = seg.font[1] or "Helvetica"
            local size = seg.font[2] or 12
            local style = seg.font[3] or cd.PLAIN
            cv:Font(family, style, size)
        else
            cv:Font("Helvetica", cd.PLAIN, 12)
        end
        -- Map alignment
        local align = cd.BASE_LEFT
        if seg.align == "center" then
            align = cd.BASE_CENTER
        elseif seg.align == "right" then
            align = cd.BASE_RIGHT
        end
        cv:TextAlignment(align)
        local x, y = self:turtle_to_canvas(seg.pos[1], seg.pos[2])
        cv:Text(x, y, seg.content)

    elseif seg.type == "stamp" then
        -- Draw turtle shape at the stamped position/heading
        self:_draw_turtle_shape(
            seg.pos[1], seg.pos[2], seg.heading,
            seg.color, seg.fill_color, seg.size
        )
    end
end

function Renderer:_draw_turtle_shape(tx, ty, heading, pen_color, fill_color, size)
    local cv = self.cd_canvas
    if not cv then return end

    -- Classic arrow shape: triangle pointing in heading direction
    local rad = heading * math.pi / 180
    local len = (size or 2) * 6   -- scale shape with pen size
    local half_w = len * 0.4

    local cos_h = math.cos(rad)
    local sin_h = math.sin(rad)
    -- Perpendicular
    local cos_p = math.cos(rad + math.pi / 2)
    local sin_p = math.sin(rad + math.pi / 2)

    -- Three vertices of the arrow
    local tip_x = tx + cos_h * len
    local tip_y = ty + sin_h * len
    local left_x = tx - cos_h * len * 0.3 + cos_p * half_w
    local left_y = ty - sin_h * len * 0.3 + sin_p * half_w
    local right_x = tx - cos_h * len * 0.3 - cos_p * half_w
    local right_y = ty - sin_h * len * 0.3 - sin_p * half_w

    -- Fill
    if fill_color then
        cv:SetForeground(self:encode_color(fill_color))
        cv:Begin(cd.FILL)
        local cx1, cy1 = self:turtle_to_canvas(tip_x, tip_y)
        local cx2, cy2 = self:turtle_to_canvas(left_x, left_y)
        local cx3, cy3 = self:turtle_to_canvas(right_x, right_y)
        cv:Vertex(cx1, cy1)
        cv:Vertex(cx2, cy2)
        cv:Vertex(cx3, cy3)
        cv:End()
    end

    -- Outline
    if pen_color then
        cv:SetForeground(self:encode_color(pen_color))
        cv:LineWidth(1)
        local cx1, cy1 = self:turtle_to_canvas(tip_x, tip_y)
        local cx2, cy2 = self:turtle_to_canvas(left_x, left_y)
        local cx3, cy3 = self:turtle_to_canvas(right_x, right_y)
        cv:Begin(cd.CLOSED_LINES)
        cv:Vertex(cx1, cy1)
        cv:Vertex(cx2, cy2)
        cv:Vertex(cx3, cy3)
        cv:End()
    end
end

----------------------------------------------------------------
-- Redraw
----------------------------------------------------------------

function Renderer:_redraw()
    local cv = self.cd_canvas
    if not cv or not self.core then return end

    cv:Activate()

    if self.needs_full_redraw then
        -- Clear and replay visible segments
        cv:SetBackground(self:encode_color(self.core.bg_color))
        cv:Clear()

        local visible = self.core:visible_segments()
        for _, seg in ipairs(visible) do
            self:_draw_segment(seg)
        end

        self.committed_up_to = #self.core.segments
        self.needs_full_redraw = false
    else
        -- Incremental: draw only new segments since last render
        local segs = self.core.segments
        for i = self.committed_up_to + 1, #segs do
            local seg = segs[i]
            if seg.type == "clear" then
                -- Need a full redraw
                self.needs_full_redraw = true
                self:_redraw()
                return
            elseif seg.type == "stamp" and self.core._cleared_stamps[seg.id] then
                -- Skip cleared stamps (shouldn't appear in incremental,
                -- but guard against it)
            else
                self:_draw_segment(seg)
            end
        end
        self.committed_up_to = #segs
    end

    -- Draw the turtle head (if visible)
    if self.core.visible then
        self:_draw_turtle_shape(
            self.core.x, self.core.y, self.core.angle,
            self.core.pen_color,
            {0.5, 0.5, 0.5, 0.8},  -- semi-transparent gray fill
            self.core.pen_size
        )
    end

    cv:Flush()
end

----------------------------------------------------------------
-- Public interface (called by turtle.lua after each command)
----------------------------------------------------------------

function Renderer:render()
    if not self:ensure_init() then return end
    self:_redraw()
end

function Renderer:render_animated(steps_fn)
    -- steps_fn is an iterator that yields partial states.
    -- Between each step, we render and sleep.
    if not self:ensure_init() then return end

    for _ in steps_fn do
        self:_redraw()
        -- Process pending UI events to keep window responsive
        if iup then iup.LoopStep() end
        -- Brief sleep for animation pacing
        self:_sleep(self:_frame_delay())
    end
end

function Renderer:_frame_delay()
    -- Delay in seconds between animation frames, based on speed setting
    if not self.core then return 0 end
    local s = self.core.speed_setting
    if s == 0 then return 0 end
    -- speed 1 = 50ms per frame, speed 10 = 5ms per frame
    return 0.05 / s
end

function Renderer:_sleep(seconds)
    if seconds <= 0 then return end
    local target = os.clock() + seconds
    while os.clock() < target do
        -- busy wait (simple but effective for small durations)
        -- Process IUP events during the wait
        if iup then iup.LoopStep() end
    end
end

----------------------------------------------------------------
-- Event loop
----------------------------------------------------------------

function Renderer:mainloop()
    if not self.initialized then return end
    -- Final render before entering the loop
    self:_redraw()
    if iup then
        iup.MainLoop()
    end
end

function Renderer:close()
    if self.cd_canvas then
        self.cd_canvas:Kill()
        self.cd_canvas = nil
    end
    if self.dialog then
        self.dialog:destroy()
        self.dialog = nil
    end
    self.initialized = false
end

return Renderer

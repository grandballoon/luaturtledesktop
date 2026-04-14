-- tests/test_pen.lua
-- Tests for pen state, segments, fills, and stamps.

package.path = "./?.lua;./turtle/?.lua;" .. package.path

local Core = require("turtle.core")
local h = require("tests.test_helpers")
local test = h.test

-- Pen state -----------------------------------------------------------

test("pen starts down", function()
    local t = Core.new()
    assert(t:isdown() == true)
end)

test("penup / pendown", function()
    local t = Core.new()
    t:penup()
    assert(t:isdown() == false)
    t:pendown()
    assert(t:isdown() == true)
end)

test("forward with pen down creates segment", function()
    local t = Core.new()
    t:forward(100)
    assert(h.count_segments(t, "line") == 1)
end)

test("forward with pen up creates no segment", function()
    local t = Core.new()
    t:penup()
    t:forward(100)
    assert(h.count_segments(t, "line") == 0)
end)

test("segment has correct endpoints", function()
    local t = Core.new()
    t:forward(100)
    local seg = t.segments[1]
    assert(seg.type == "line")
    h.assert_near(seg.from[1], 0, 0.001, "from x")
    h.assert_near(seg.from[2], 0, 0.001, "from y")
    h.assert_near(seg.to[1], 100, 0.001, "to x")
    h.assert_near(seg.to[2], 0, 0.001, "to y")
end)

test("segment has pen color and width", function()
    local t = Core.new()
    t:pencolor(1, 0, 0)
    t:pensize(5)
    t:forward(100)
    local seg = t.segments[1]
    h.assert_near(seg.color[1], 1, 0.001, "red")
    h.assert_near(seg.color[2], 0, 0.001, "green")
    h.assert_near(seg.color[3], 0, 0.001, "blue")
    assert(seg.width == 5)
end)

test("pencolor with 0-255 range normalizes", function()
    local t = Core.new()
    t:pencolor(255, 128, 0)
    h.assert_near(t.pen_color[1], 1, 0.001)
    h.assert_near(t.pen_color[2], 128/255, 0.001)
    h.assert_near(t.pen_color[3], 0, 0.001)
end)

test("pencolor with alpha", function()
    local t = Core.new()
    t:pencolor(1, 0, 0, 0.5)
    h.assert_near(t.pen_color[4], 0.5, 0.001)
end)

test("pensize returns current width", function()
    local t = Core.new()
    t:pensize(7)
    assert(t:pensize() == 7)
end)

-- Fills ---------------------------------------------------------------

test("begin_fill / end_fill creates fill segment", function()
    local t = Core.new()
    t:begin_fill()
    for i = 1, 4 do
        t:forward(100)
        t:right(90)
    end
    t:end_fill()
    assert(h.count_segments(t, "fill") == 1)
end)

test("fill segment has vertices", function()
    local t = Core.new()
    t:begin_fill()
    t:forward(100)
    t:right(90)
    t:forward(100)
    t:right(90)
    t:forward(100)
    t:right(90)
    t:forward(100)
    t:end_fill()
    local fill = nil
    for _, seg in ipairs(t.segments) do
        if seg.type == "fill" then fill = seg end
    end
    assert(fill, "fill segment should exist")
    assert(#fill.vertices >= 4, "should have at least 4 vertices")
end)

test("filling() returns state", function()
    local t = Core.new()
    assert(t:is_filling() == false)
    t:begin_fill()
    assert(t:is_filling() == true)
    t:end_fill()
    assert(t:is_filling() == false)
end)

test("end_fill with < 3 vertices creates no fill", function()
    local t = Core.new()
    t:begin_fill()
    t:forward(100)
    t:end_fill()
    assert(h.count_segments(t, "fill") == 0)
end)

test("fill segment logged after its outline lines in segment log", function()
    local t = Core.new()
    t:begin_fill()
    for i = 1, 4 do t:forward(100); t:right(90) end
    t:end_fill()
    -- lines are logged as drawn; fill is appended at end_fill()
    -- renderer's full-redraw path draws fills before lines regardless of log order
    assert(t.segments[1].type == "line", "lines should be logged as drawn")
    local last = t.segments[#t.segments]
    assert(last.type == "fill", "fill should be the last logged segment")
end)

test("color(c) sets both pen and fill", function()
    local t = Core.new()
    t:color("white")
    local pr, pg, pb = t:pencolor()
    local fr, fg, fb = t:fillcolor()
    h.assert_near(pr, 1, 0.001, "pen r")
    h.assert_near(fr, 1, 0.001, "fill r")
    h.assert_near(pg, 1, 0.001, "pen g")
    h.assert_near(fg, 1, 0.001, "fill g")
end)

-- Dots ----------------------------------------------------------------

test("dot creates segment", function()
    local t = Core.new()
    t:dot(10)
    assert(h.count_segments(t, "dot") == 1)
end)

-- Stamps --------------------------------------------------------------

test("stamp creates segment and returns id", function()
    local t = Core.new()
    local id = t:stamp()
    assert(type(id) == "number")
    assert(h.count_segments(t, "stamp") == 1)
end)

test("clearstamp removes from visible", function()
    local t = Core.new()
    local id = t:stamp()
    assert(h.count_visible(t, "stamp") == 1)
    t:clearstamp(id)
    assert(h.count_visible(t, "stamp") == 0)
end)

test("clearstamps(nil) clears all stamps", function()
    local t = Core.new()
    for i = 1, 5 do
        t:forward(20)
        t:stamp()
    end
    assert(h.count_visible(t, "stamp") == 5)
    t:clearstamps()
    assert(h.count_visible(t, "stamp") == 0)
end)

test("clearstamps(n) clears first n", function()
    local t = Core.new()
    for i = 1, 5 do
        t:forward(20)
        t:stamp()
    end
    t:clearstamps(2)
    assert(h.count_visible(t, "stamp") == 3)
end)

test("clearstamps(-n) clears last n", function()
    local t = Core.new()
    for i = 1, 5 do
        t:forward(20)
        t:stamp()
    end
    t:clearstamps(-2)
    assert(h.count_visible(t, "stamp") == 3)
end)

-- Clear / Reset -------------------------------------------------------

test("clear preserves position and heading", function()
    local t = Core.new()
    t:forward(100)
    t:left(45)
    local x, y = t:position()
    local h_val = t:heading()
    t:clear()
    h.assert_pos(t, x, y)
    h.assert_heading(t, h_val)
end)

test("clear hides previous segments from visible_segments", function()
    local t = Core.new()
    t:forward(100)
    assert(h.count_visible(t, "line") == 1)
    t:clear()
    assert(h.count_visible(t, "line") == 0)
end)

test("reset moves to origin", function()
    local t = Core.new()
    t:forward(100)
    t:left(45)
    t:reset()
    h.assert_pos(t, 0, 0)
    h.assert_heading(t, 0)
    assert(t:isdown() == true)
end)

-- Speed ---------------------------------------------------------------

test("speed default is 5", function()
    local t = Core.new()
    assert(t:speed() == 5)
end)

test("speed clamps to 0-10", function()
    local t = Core.new()
    t:speed(-5)
    assert(t:speed() == 0)
    t:speed(100)
    assert(t:speed() == 10)
end)

h.run("test_pen")

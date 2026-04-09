-- tests/test_position.lua
-- Tests for turtle position and heading.

package.path = "../?.lua;../turtle/?.lua;" .. package.path

local Core = require("turtle.core")
local h = require("tests.test_helpers")
local test = h.test

test("initial state", function()
    local t = Core.new()
    h.assert_pos(t, 0, 0)
    h.assert_heading(t, 0)
    assert(t:isdown() == true)
end)

test("forward from origin", function()
    local t = Core.new()
    t:forward(100)
    h.assert_pos(t, 100, 0)
end)

test("back from origin", function()
    local t = Core.new()
    t:back(50)
    h.assert_pos(t, -50, 0)
end)

test("forward negative = back", function()
    local t = Core.new()
    t:forward(-75)
    h.assert_pos(t, -75, 0)
end)

test("right then forward", function()
    local t = Core.new()
    t:right(90)
    t:forward(100)
    h.assert_pos(t, 0, -100)
end)

test("left then forward", function()
    local t = Core.new()
    t:left(90)
    t:forward(100)
    h.assert_pos(t, 0, 100)
end)

test("forward then back returns to origin", function()
    local t = Core.new()
    t:forward(100)
    t:back(100)
    h.assert_pos(t, 0, 0)
end)

test("four right turns = full rotation", function()
    local t = Core.new()
    for i = 1, 4 do t:right(90) end
    h.assert_heading(t, 0)
end)

test("right 360 = no change", function()
    local t = Core.new()
    t:right(360)
    h.assert_heading(t, 0)
end)

test("negative right = left", function()
    local t = Core.new()
    t:right(-90)
    h.assert_heading(t, 90)
end)

test("square returns to origin", function()
    local t = Core.new()
    for i = 1, 4 do
        t:forward(100)
        t:right(90)
    end
    h.assert_pos(t, 0, 0)
    h.assert_heading(t, 0)
end)

test("equilateral triangle returns to origin", function()
    local t = Core.new()
    for i = 1, 3 do
        t:forward(100)
        t:right(120)
    end
    h.assert_pos(t, 0, 0)
    h.assert_heading(t, 0)
end)

test("star returns to origin", function()
    local t = Core.new()
    for i = 1, 5 do
        t:forward(100)
        t:right(144)
    end
    h.assert_pos(t, 0, 0)
end)

test("setpos moves to absolute position", function()
    local t = Core.new()
    t:setpos(50, 75)
    h.assert_pos(t, 50, 75)
end)

test("setpos with table", function()
    local t = Core.new()
    t:setpos({50, 75})
    h.assert_pos(t, 50, 75)
end)

test("setx changes only x", function()
    local t = Core.new()
    t:setpos(10, 20)
    t:setx(99)
    h.assert_pos(t, 99, 20)
end)

test("sety changes only y", function()
    local t = Core.new()
    t:setpos(10, 20)
    t:sety(99)
    h.assert_pos(t, 10, 99)
end)

test("setheading", function()
    local t = Core.new()
    t:setheading(180)
    h.assert_heading(t, 180)
end)

test("home resets position and heading", function()
    local t = Core.new()
    t:forward(100)
    t:left(45)
    t:home()
    h.assert_pos(t, 0, 0)
    h.assert_heading(t, 0)
end)

test("teleport moves without drawing", function()
    local t = Core.new()
    t:teleport(100, 200)
    h.assert_pos(t, 100, 200)
    assert(h.count_segments(t, "line") == 0, "teleport should not create segments")
end)

test("towards", function()
    local t = Core.new()
    local angle = t:towards(100, 0)
    h.assert_near(angle, 0, 0.001, "towards east")
    angle = t:towards(0, 100)
    h.assert_near(angle, 90, 0.001, "towards north")
end)

test("distance", function()
    local t = Core.new()
    local d = t:distance(3, 4)
    h.assert_near(d, 5, 0.001, "3-4-5 triangle")
end)

test("forward(0) no segment", function()
    local t = Core.new()
    t:forward(0)
    h.assert_pos(t, 0, 0)
    assert(h.count_segments(t, "line") == 0)
end)

test("large forward", function()
    local t = Core.new()
    t:forward(10000)
    h.assert_pos(t, 10000, 0)
end)

test("floating point forward", function()
    local t = Core.new()
    t:forward(0.5)
    h.assert_pos(t, 0.5, 0)
end)

h.run("test_position")

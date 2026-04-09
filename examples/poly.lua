-- POLY — Turtle Geometry, Chapter 1
-- The fundamental turtle graphics procedure.
-- POLY(side, angle) draws a regular polygon (or star polygon).
--
-- Try: poly(100, 90)    -- square
--      poly(100, 120)   -- triangle
--      poly(100, 144)   -- five-pointed star
--      poly(50, 60)     -- hexagon

local turtle = require("turtle")

local function poly(side, angle)
    -- POLY closes when total turning = 360 (or a multiple).
    -- For simple polygons, this is 360/angle steps.
    -- For star polygons, it may take multiple full rotations.
    local total = 0
    repeat
        forward(side)
        right(angle)
        total = total + angle
    until math.abs(total % 360) < 0.001 and total > 0
end

speed(0)
pencolor("red")
poly(100, 144)

turtle.done()

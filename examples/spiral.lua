-- Spiral
-- Colorful spiral demonstrating loops, color changes, and speed.

local turtle = require("turtle")

speed(0)
bgcolor("black")

for i = 1, 200 do
    -- Cycle through hues using simple RGB math
    local r = math.sin(i * 0.03) * 0.5 + 0.5
    local g = math.sin(i * 0.03 + 2) * 0.5 + 0.5
    local b = math.sin(i * 0.03 + 4) * 0.5 + 0.5
    pencolor(r, g, b)
    forward(i)
    right(91)
end

hideturtle()
turtle.done()

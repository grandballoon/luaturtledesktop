-- Circle Flower
-- Draw overlapping circles to create a flower pattern.
-- Demonstrates circle() and rotation.
-- From the spirit of Turtle Geometry Chapter 1 exercises.

local turtle = require("turtle")

speed(0)
pencolor("magenta")

for i = 1, 12 do
    circle(80)
    right(30)
end

hideturtle()
turtle.done()

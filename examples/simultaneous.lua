-- simultaneous.lua
-- Two turtles spiral outward simultaneously using tracer(0) + update().
-- Exercises: tracer/update batch drawing pattern, per-turtle color/speed.

local turtle = require("turtle")

bgcolor(0.08, 0.08, 0.12)  -- near-black

tracer(0)  -- disable per-step rendering

local t1 = turtle.Turtle()
local t2 = turtle.Turtle()

t1:color("orangered")
t2:color("dodgerblue")
t1:speed(0)
t2:speed(0)


-- Mirror-image spirals
for i = 1, 180 do
    t1:forward(i * 0.7); t1:right(91)
    t2:forward(i * 0.7); t2:left(91)
    update()  -- render every single step (slow but visible)
end


update()
turtle.done()

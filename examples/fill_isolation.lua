-- fill_isolation.lua
-- Verifies that t2 drawing during t1's open fill does not corrupt t1's polygon.
-- t1 draws a filled square. t2 draws lines in between t1's moves.
-- Result: t1's fill should be a clean square; t2's lines are separate.

local turtle = require("turtle")

bgcolor("black")
speed(0)

local t2 = turtle.Turtle()
t2:color("deepskyblue")
t2:speed(0)

-- Open t1's fill
color("tomato", "gold")  -- pen=tomato, fill=gold
begin_fill()

-- t1 draws first side, t2 draws a line in between each t1 move
forward(120); right(90)
t2:forward(80); t2:left(45)

forward(120); right(90)
t2:forward(80); t2:left(45)

forward(120); right(90)
t2:forward(80); t2:left(45)

forward(120); right(90)

-- Close t1's fill — should be a clean gold square, not contaminated by t2
end_fill()

-- Label
local label = turtle.Turtle()
label:color("white")
label:speed(0)
label:penup()
label:setpos(-290, -230)
label:pendown()
label:write("gold square = t1 fill  |  blue lines = t2 (separate)", false, "left")

turtle.done()

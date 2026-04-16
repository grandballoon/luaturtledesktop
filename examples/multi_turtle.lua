-- multi_turtle.lua
-- Exercises: bgcolor, turtle.Turtle(), per-turtle color, simultaneous
-- movement via tracer/update, and per-turtle clear.

local turtle = require("turtle")

-- Dark background
bgcolor("midnightblue")

-- Default turtle draws a red square
color("tomato")
speed(5)
for _ = 1, 4 do
    forward(120)
    right(90)
end

-- Second turtle draws a blue triangle on the right side of the screen
local t2 = turtle.Turtle()
t2:color("deepskyblue")
t2:speed(0)
t2:penup()
t2:setpos(80, 100)
t2:pendown()
for _ = 1, 3 do
    t2:forward(100)
    t2:right(120)
end

-- Third turtle writes text and stamps
local t3 = turtle.Turtle()
t3:color("gold")
t3:speed(5)
t3:penup()
t3:setpos(-280, -200)
t3:pendown()
t3:write("multi-turtle", false, "left")
t3:penup()
t3:setpos(-200, -50)
t3:stamp()
t3:setpos(-150, -50)
t3:stamp()
t3:setpos(-100, -50)
t3:stamp()

-- Show that per-turtle clear only affects one turtle.
-- Clear t2's triangle — red square and stamps stay.
t2:clear()
t2:penup()
t2:setpos(80, -80)
t2:pendown()
t2:color("limegreen")
t2:write("(t2 was cleared and redrew here)", false, "left")

turtle.done()

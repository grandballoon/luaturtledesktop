-- Star
-- Five-pointed star, filled with yellow, outlined in red.
-- Matches the classic Python turtle example.

local turtle = require("turtle")

speed(0)
pencolor("red")
fillcolor("yellow")

begin_fill()
for i = 1, 5 do
    forward(200)
    right(144)
end
end_fill()

hideturtle()
turtle.done()

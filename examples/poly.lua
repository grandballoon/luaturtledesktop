local turtle = require("turtle")

-- TO POLY SIDE ANGLE
-- REPEAT FOREVER
-- FORWARD SIDE
-- RIGHT ANGLE

function poly(side, angle)
    for i = 1, 15 do
        turtle.fd(side)
        turtle.right(angle)
    end
end

turtle.bgcolor("gold")
turtle.color("dodgerblue", 0.7)
speed(3)
turtle.circle(100)
print(towards(100, 100))
undo()
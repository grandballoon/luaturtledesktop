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

speed(3)
turtle.fd(50)
turtle.rt(45)
turtle.fd(50)
undo()
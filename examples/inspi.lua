turtle = require("turtle")


-- TO INSPI (SIDE, ANGLE, INC)
-- FORWARD SIDE
-- RIGHT ANGLE
-- INSPI (SIDE, ANGLE + INC. INC)

function inspi(side, angle, inc)
    turtle.fd(side)
    turtle.rt(angle)
    inspi(side, angle + inc, inc)
end

inspi(50, 5, 7)
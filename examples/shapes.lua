local turtle = require("turtle")

speed(10)
local function inspi(side, angle, inc)
    local total = 0
    repeat
        turtle.fd(side)
        turtle.rt(angle)
        total = total + angle
        angle = angle + inc
    until math.abs(total % 360) < 0.001 and total > 0
end
turtle.color("dodgeblue", 0.5)
turtle.fillcolor("dodgerblue", 0.79)

print(pencolor())
print(fillcolor())
write('hi')
rt(90)
fd(50)
write('there', 'center')
fd(50)
write('everybody', 'left')
fd(50)
write('adios', 'right')
dot()
left(90)
fd(100)
turtle.done()
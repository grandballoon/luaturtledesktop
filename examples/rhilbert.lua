t = require("turtle")

function lhilbert(size, level)
    if level == 0 then return end
    t.left(90)
    rhilbert(size, level - 1)
    t.fd(size)
    t.right(90)
    lhilbert(size, level - 1)
    t.fd(size)
    lhilbert(size, level - 1)
    t.rt(90)
    rhilbert(size, level - 1)
    t.left(90)
end

function rhilbert(size, level)      
    if level == 0 then return end
    t.right(90)
    lhilbert(size, level - 1)
    t.fd(size)
    t.left(90)
    rhilbert(size, level - 1)
    t.fd(size)
    rhilbert(size, level - 1)
    t.lt(90)
    t.fd(size)
    lhilbert(size, level - 1)
    t.rt(90)
end

t.speed(10)
rhilbert(50, 2)
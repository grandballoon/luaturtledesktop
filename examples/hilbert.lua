local t = require("turtle")

function hilbert(size, level, parity)
    if level == 0 then return end
    t.left(parity * 90)
    hilbert(size, level - 1, -parity)
    t.fd(size)
    t.right(parity * 90)
    hilbert(size, level - 1, parity)
    t.fd(size)
    hilbert(size, level - 1, parity)
    t.right(parity * 90)
    t.fd(size)
    hilbert(size, level - 1, -parity)
    t.left(parity * 90)

end

hilbert(20, 3, 1)
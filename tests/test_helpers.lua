-- tests/test_helpers.lua
-- Test utilities for turtle core tests.
-- No IUP/CD dependency — tests run with plain lua5.4.

local helpers = {}

-- Floating point comparison
function helpers.assert_near(actual, expected, tolerance, msg)
    tolerance = tolerance or 0.001
    msg = msg or ""
    assert(math.abs(actual - expected) < tolerance,
        string.format("%s: expected %g, got %g (tolerance %g)",
            msg, expected, actual, tolerance))
end

-- Assert position
function helpers.assert_pos(core, ex, ey, tolerance)
    tolerance = tolerance or 0.001
    local ax, ay = core:position()
    helpers.assert_near(ax, ex, tolerance,
        string.format("x position"))
    helpers.assert_near(ay, ey, tolerance,
        string.format("y position"))
end

-- Assert heading (normalized to 0-360)
function helpers.assert_heading(core, expected, tolerance)
    tolerance = tolerance or 0.001
    local actual = core:heading() % 360
    expected = expected % 360
    -- Handle wrap-around near 0/360
    local diff = math.abs(actual - expected)
    if diff > 180 then diff = 360 - diff end
    assert(diff < tolerance,
        string.format("heading: expected %g, got %g", expected, actual))
end

-- Count segments of a given type
function helpers.count_segments(core, seg_type)
    local count = 0
    for _, seg in ipairs(core.segments) do
        if seg.type == seg_type then
            count = count + 1
        end
    end
    return count
end

-- Count visible segments (after last clear, excluding cleared stamps)
function helpers.count_visible(core, seg_type)
    local visible = core:visible_segments()
    if not seg_type then return #visible end
    local count = 0
    for _, seg in ipairs(visible) do
        if seg.type == seg_type then
            count = count + 1
        end
    end
    return count
end

-- Simple test runner
local _tests = {}
local _current_file = ""

function helpers.test(name, fn)
    table.insert(_tests, {name = _current_file .. " :: " .. name, fn = fn})
end

function helpers.run(file_label)
    _current_file = file_label or ""
    local passed, failed = 0, 0
    for _, t in ipairs(_tests) do
        local ok, err = pcall(t.fn)
        if ok then
            passed = passed + 1
            io.write("  PASS  " .. t.name .. "\n")
        else
            failed = failed + 1
            io.write("  FAIL  " .. t.name .. "\n")
            io.write("        " .. tostring(err) .. "\n")
        end
    end
    io.write(string.format("\n%d passed, %d failed\n", passed, failed))
    _tests = {}
    return failed == 0
end

return helpers

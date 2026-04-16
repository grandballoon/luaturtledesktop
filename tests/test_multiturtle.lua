-- tests/test_multiturtle.lua
-- Multi-turtle tests: per-screen shared log, per-turtle clear/reset/undo,
-- fill isolation. Covers Milestones 1.1 through 1.4.
--
-- Run from project root:   lua tests/test_multiturtle.lua

package.path = "./?.lua;./turtle/?.lua;" .. package.path

local Core   = require("turtle.core")
local Screen = require("turtle.screen")
local h      = require("tests.test_helpers")
local test   = h.test

----------------------------------------------------------------
-- M1.1: Shared segment log
----------------------------------------------------------------

test("M1.1: two cores share one screen's segment log", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100)
    t2:forward(50)
    t1:forward(75)

    -- All three line segments appear in the shared log
    assert(#screen.segments == 3, "expected 3 segments, got " .. #screen.segments)
end)

test("M1.1: visible_segments returns segments from both turtles", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100)
    t2:forward(50)

    local vis = screen:visible_segments()
    assert(#vis == 2, "expected 2 visible segments, got " .. #vis)
end)

test("M1.1: segments carry correct turtle_id", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100)
    t2:forward(50)

    assert(screen.segments[1].turtle_id == t1.turtle_id)
    assert(screen.segments[2].turtle_id == t2.turtle_id)
    assert(t1.turtle_id ~= t2.turtle_id, "turtles must have distinct IDs")
end)

test("M1.1: screen registers turtles in order", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)
    local t3 = Core.new(screen)

    assert(#screen.turtles == 3)
    assert(screen.turtles[1] == t1)
    assert(screen.turtles[2] == t2)
    assert(screen.turtles[3] == t3)
end)

test("M1.1: Core.new() with no args creates private screen (single-turtle compat)", function()
    local t = Core.new()
    t:forward(100)
    assert(#t.segments == 1)
    assert(t.turtle_id ~= nil)
end)

test("M1.1: core.segments alias matches screen.segments (same table)", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    t1:forward(100)
    -- core.segments is an alias — same table, not a copy
    assert(t1.segments == screen.segments)
    assert(t1.segments[1] == screen.segments[1])
end)

test("M1.1: screen:bgcolor sets and gets background color", function()
    local screen = Screen.new()
    screen:bgcolor(1, 0, 0)
    local r, g, b = screen:bgcolor()
    assert(math.abs(r - 1) < 0.001)
    assert(math.abs(g - 0) < 0.001)
    assert(math.abs(b - 0) < 0.001)
end)

test("M1.1: screen:bgcolor with named color", function()
    local screen = Screen.new()
    screen:bgcolor("white")
    local r, g, b = screen:bgcolor()
    assert(math.abs(r - 1) < 0.001 and math.abs(g - 1) < 0.001 and math.abs(b - 1) < 0.001)
end)

----------------------------------------------------------------
-- M1.1: _segments_after_clears filter
----------------------------------------------------------------

test("M1.1: _segments_after_clears hides segments before a clear", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    t1:forward(100)   -- segment 1
    t1:clear()        -- clear marker
    t1:forward(50)    -- segment 3 (visible)

    local segs = screen:_segments_after_clears()
    assert(#segs == 1, "expected 1 segment after clear, got " .. #segs)
    assert(segs[1].type == "line")
    -- clear() preserves position (at x=100); forward(50) goes to x=150
    h.assert_near(segs[1].from[1], 100, 0.001, "post-clear segment starts at turtle position")
    h.assert_near(segs[1].to[1],   150, 0.001, "post-clear segment ends 50 units further")
end)

test("M1.1: _segments_after_clears is per-turtle (t2 unaffected by t1:clear)", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100)  -- t1's line
    t2:forward(80)   -- t2's line
    t1:clear()       -- clears only t1

    local segs = screen:_segments_after_clears()
    -- t2's line should still be visible; t1's line before clear should be gone
    local line_count = 0
    for _, s in ipairs(segs) do
        if s.type == "line" then line_count = line_count + 1 end
    end
    assert(line_count == 1, "expected 1 visible line (t2's), got " .. line_count)
    assert(segs[1].turtle_id == t2.turtle_id, "remaining line should belong to t2")
end)

test("M1.1: _filter_cleared_stamps removes cleared stamps", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    local id = t1:stamp()
    local segs_before = screen:_filter_cleared_stamps(screen.segments)
    assert(#segs_before == 1)

    t1:clearstamp(id)
    local segs_after = screen:_filter_cleared_stamps(screen.segments)
    assert(#segs_after == 0, "stamp should be filtered out after clearstamp")
end)

----------------------------------------------------------------
-- M1.2: Per-turtle clear and reset (Python gotcha cases)
----------------------------------------------------------------

test("M1.2: t1:clear() removes t1 lines, t2 lines remain", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100)
    t2:forward(80)
    t1:clear()

    local vis = screen:visible_segments()
    local t1_lines, t2_lines = 0, 0
    for _, s in ipairs(vis) do
        if s.type == "line" then
            if s.turtle_id == t1.turtle_id then t1_lines = t1_lines + 1
            else t2_lines = t2_lines + 1 end
        end
    end
    assert(t1_lines == 0, "t1 lines should be gone after clear")
    assert(t2_lines == 1, "t2 line should remain")
end)

test("M1.2: t1:clear() preserves t1 position and heading", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    t1:forward(100)
    t1:left(45)
    local x, y = t1:position()
    local hdg   = t1:heading()
    t1:clear()
    h.assert_pos(t1, x, y)
    h.assert_heading(t1, hdg)
end)

test("M1.2: t1:reset() resets t1 to origin, t2 untouched", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100); t1:left(45)
    t2:forward(80)
    t1:reset()

    -- t1 back at origin with default state
    h.assert_pos(t1, 0, 0)
    h.assert_heading(t1, 0)
    assert(t1:isdown() == true)

    -- t2 position unchanged
    h.assert_pos(t2, 80, 0)

    -- t2 line still visible
    local vis = screen:visible_segments()
    local t2_lines = 0
    for _, s in ipairs(vis) do
        if s.type == "line" and s.turtle_id == t2.turtle_id then
            t2_lines = t2_lines + 1
        end
    end
    assert(t2_lines == 1, "t2 line should survive t1:reset()")
end)

test("M1.2: bgcolor belongs to screen, not turtle", function()
    local screen = Screen.new()
    screen:bgcolor(0, 0, 1)  -- blue
    local r, _, b = screen:bgcolor()
    assert(math.abs(r) < 0.001 and math.abs(b - 1) < 0.001)
end)

test("M1.2: second clear only hides segments after first clear", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    t1:forward(100)  -- hidden by first clear
    t1:clear()
    t1:forward(50)   -- hidden by second clear
    t1:clear()
    t1:forward(25)   -- visible

    local vis = screen:visible_segments()
    local lines = 0
    for _, s in ipairs(vis) do if s.type == "line" then lines = lines + 1 end end
    assert(lines == 1, "only post-second-clear segment visible, got " .. lines)
    h.assert_near(vis[1].to[1] - vis[1].from[1], 25, 0.001, "visible segment is the 25-unit one")
end)

----------------------------------------------------------------
-- M1.3: Per-turtle undo with interleaving
----------------------------------------------------------------

test("M1.3: single-turtle undo restores state and hides segment", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    t1:_push_undo(); t1:forward(100); t1:_commit_undo_segments()
    assert(#screen:visible_segments() == 1)

    t1:undo()
    assert(#screen:visible_segments() == 0, "segment should be hidden after undo")
    h.assert_pos(t1, 0, 0)
end)

test("M1.3: undo does not truncate shared log (index marking)", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    t1:_push_undo(); t1:forward(100); t1:_commit_undo_segments()
    local log_len_before = #screen.segments

    t1:undo()

    -- Log is NOT truncated — the entry is still there, just hidden
    assert(#screen.segments == log_len_before,
        "undo must not truncate shared log; got " .. #screen.segments)
end)

test("M1.3: t1:undo removes t1 segment, t2 segments unaffected", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    -- Python gotcha test sequence from ROADMAP 1.3
    t1:_push_undo(); t1:forward(100); t1:_commit_undo_segments()
    t2:_push_undo(); t2:forward(100); t2:_commit_undo_segments()
    t1:_push_undo(); t1:left(90);     t1:_commit_undo_segments()
    t2:_push_undo(); t2:left(90);     t2:_commit_undo_segments()
    t1:_push_undo(); t1:forward(100); t1:_commit_undo_segments()
    t2:_push_undo(); t2:forward(100); t2:_commit_undo_segments()

    local function count_lines(tid)
        local n = 0
        for _, s in ipairs(screen:visible_segments()) do
            if s.type == "line" and s.turtle_id == tid then n = n + 1 end
        end
        return n
    end

    assert(count_lines(t1.turtle_id) == 2, "t1 should have 2 lines before undo")
    assert(count_lines(t2.turtle_id) == 2, "t2 should have 2 lines before undo")

    -- Undo t1's second forward
    t1:undo()
    assert(count_lines(t1.turtle_id) == 1, "t1 should have 1 line after first undo")
    assert(count_lines(t2.turtle_id) == 2, "t2 lines unchanged after t1:undo()")

    -- Undo t1's left turn (no segment; state restoration only)
    t1:undo()
    assert(count_lines(t1.turtle_id) == 1, "t1 still has 1 line (turn had no segment)")
    assert(count_lines(t2.turtle_id) == 2, "t2 still unaffected")

    -- Undo t1's first forward
    t1:undo()
    assert(count_lines(t1.turtle_id) == 0, "t1 should have 0 lines after third undo")
    assert(count_lines(t2.turtle_id) == 2, "t2 completely untouched throughout")
end)

test("M1.3: undo heading restored after turn undo", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    t1:_push_undo(); t1:left(90); t1:_commit_undo_segments()
    h.assert_heading(t1, 90)

    t1:undo()
    h.assert_heading(t1, 0)
end)

test("M1.3: undo stack exhausted returns nil", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local result = t1:undo()
    assert(result == nil, "undo on empty stack should return nil")
end)

test("M1.3: clear wipes undo history and hidden indices", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)

    t1:_push_undo(); t1:forward(100); t1:_commit_undo_segments()
    t1:undo()
    assert(next(t1._hidden_indices) ~= nil, "should have hidden indices before clear")

    t1:clear()
    assert(next(t1._hidden_indices) == nil, "clear should wipe hidden indices")
    assert(#t1._undo_stack == 0, "clear should wipe undo stack")
end)

----------------------------------------------------------------
-- M1.4: Fill isolation between turtles
----------------------------------------------------------------

test("M1.4: t2 drawing during t1 open fill does not contaminate t1 vertices", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:begin_fill()
    t1:forward(100); t1:left(90)

    -- t2 draws while t1's fill is open
    t2:forward(150); t2:left(90); t2:forward(150)

    t1:forward(100); t1:left(90)
    t1:forward(100); t1:left(90)
    t1:forward(100); t1:left(90)
    t1:end_fill()

    -- Find t1's fill segment
    local fill = nil
    for _, s in ipairs(screen:visible_segments()) do
        if s.type == "fill" and s.turtle_id == t1.turtle_id then fill = s end
    end
    assert(fill ~= nil, "t1 fill segment should exist")

    -- All fill vertices should be t1's movements only (4 corners of a square)
    -- t2's movements must not appear in t1's fill_vertices
    for _, v in ipairs(fill.vertices) do
        -- t2 moved along y=0 to x=150; t1 moved in a square
        -- The simplest check: none of t1's vertices should have x=150 (that's t2's)
        assert(math.abs(v[1]) <= 101, "fill vertex x=" .. v[1] .. " looks like t2's")
    end
end)

test("M1.4: fill_vertices are independent per turtle", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:begin_fill()
    t2:begin_fill()

    t1:forward(50)
    t2:forward(200)

    -- t1's fill_vertices should only contain t1's position
    assert(#t1.fill_vertices == 2, "t1 should have 2 fill vertices (start + after forward)")
    h.assert_near(t1.fill_vertices[2][1], 50, 0.001, "t1 vertex is at x=50")

    assert(#t2.fill_vertices == 2, "t2 should have 2 fill vertices")
    h.assert_near(t2.fill_vertices[2][1], 200, 0.001, "t2 vertex is at x=200")
end)

----------------------------------------------------------------
-- M1.5: turtle.Turtle() constructor
----------------------------------------------------------------

-- NOTE: turtle.Turtle() requires require("turtle") which opens a window.
-- We test it through core.lua directly for the unit-level behavior.
-- turtle.Turtle() is tested via the multi-turtle API in integration.

test("M1.5: Core.new(screen) creates turtles with distinct IDs", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)
    local t3 = Core.new(screen)
    assert(t1.turtle_id == 1)
    assert(t2.turtle_id == 2)
    assert(t3.turtle_id == 3)
end)

test("M1.5: each turtle has independent position and heading", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:forward(100)
    t2:left(90)
    t2:forward(50)

    h.assert_pos(t1, 100, 0)
    h.assert_pos(t2, 0, 50)
    h.assert_heading(t1, 0)
    h.assert_heading(t2, 90)
end)

test("M1.5: each turtle has independent pen state", function()
    local screen = Screen.new()
    local t1 = Core.new(screen)
    local t2 = Core.new(screen)

    t1:pencolor("red")
    t2:pencolor("blue")
    t1:pensize(5)

    local r1 = t1:pencolor()
    local r2, _, b2 = t2:pencolor()
    h.assert_near(r1, 1, 0.001, "t1 pen is red")
    h.assert_near(b2, 1, 0.001, "t2 pen is blue")
    h.assert_near(r2, 0, 0.001, "t2 pen is not red")
    assert(t1:pensize() == 5, "t1 pensize is 5")
    assert(t2:pensize() == 2, "t2 pensize unchanged")
end)

h.run("test_multiturtle")

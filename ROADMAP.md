# ROADMAP.md — Implementation Plan for Claude Code

## How to Use This Document

This is an ordered task list for Claude Code sessions. Work top-to-bottom.
Each milestone ends with a concrete test: either a Lua script that should
produce correct output or a set of unit tests that should pass.

Reference CLAUDE.md for architecture context. Reference ARCHITECTURE.md
for design decisions. When working on Turtle Geometry exercises, the human
will paste the specific exercise text.

---

## Milestone 1: Fix Core Bugs (get existing code working correctly)

### 1.1 Fix speed() having no visible effect
- Trace: `turtle.speed(n)` → `core:speed(n)` → `core.speed_setting` → 
  `renderer:frame_delay()` → `renderer:sleep()` → `ray.wait()`
- The animated wrappers in `turtle.lua` (animated_forward, animated_right, etc.)
  use `renderer:frame_delay()` and `renderer:sleep()` but the timing may be wrong.
- `ray.wait()` calls Raylib's `WaitTime(seconds)` which might interact badly
  with Raylib's internal frame timing / `SetTargetFPS(60)`.
- **Test:** `speed(1)` should produce visibly slow drawing. `speed(10)` should be
  visibly fast but not instant. `speed(0)` should be instant.

### ✅ 1.2 Fix speed(0) batch rendering
- When `speed(0)`, no per-command rendering happens. All drawing is deferred to
  `turtle.done()` which calls `renderer:request_full_redraw()` then `mainloop()`.
- Verify this works: the window should open, show the complete drawing, and stay open.
- **Done:** All examples (poly.lua, circle_flower.lua, spiral.lua, star.lua)
  use speed(0) and correctly defer all drawing to turtle.done().

### ✅ 1.3 Verify circle() produces correct geometry
- `core:circle(radius, extent, steps)` decomposes into turn/move pairs.
- The polygon approximation should close properly (total turning = extent).
- Positive radius = center to the LEFT of turtle, CCW arc.
- Negative radius = center to the RIGHT, CW arc.
- **Done:** `animated_circle` in turtle.lua correctly decomposes into
  left(step_angle/2) / forward(step_len) / left(step_angle/2) steps.
  circle_flower.lua demonstrates circle() working correctly.

### ✅ 1.4 Verify fill works
- `begin_fill()` / draw shape / `end_fill()` should produce a filled polygon.
- **Done:** star.lua demonstrates filled shapes with fillcolor("gold"),
  begin_fill()/end_fill(). Core logs fill_polygon segments correctly.

---

## Milestone 2: Turtle Geometry Chapter 1 — POLY and Variations

### ✅ 2.1 Implement POLY
```lua
local function poly(side, angle)
    local total = 0
    repeat
        forward(side)
        right(angle)
        total = total + angle
    until math.abs(total % 360) < 0.001 and total > 0
end
```
- **Done:** examples/poly.lua has the correct closure-checking implementation.
  Tests poly(100, 144) (5-pointed star) as a visual demo.

### 2.2 Implement INSPI (Chapter 1 variation)
```lua
local function inspi(side, angle, inc)
    local total = 0
    repeat
        forward(side)
        right(angle)
        total = total + angle
        angle = angle + inc
    until math.abs(total % 360) < 0.001 and total > 0
end
```
- This won't always close — add a maximum iteration guard.
- Test with several parameter combinations from the book.

### 2.3 Add examples/ files for each working program

---

## Milestone 3: Turtle Geometry Chapter 1 Exercises

Work through the exercises at the end of Chapter 1. The human will paste
exercise text. Key exercises:

- Exercises on POLY closure (when does total turning = multiple of 360?)
- DOUBLEPOLY — two alternating side lengths
- POLYSPI — POLY with incrementing side length
- INSPI variations
- Exploration: what angle inputs produce what symmetries?

Each working exercise becomes an example file.

---

## Milestone 4: Core API Completeness

### ✅ 4.1 Verify all Python turtle aliases work
- `fd`, `bk`, `rt`, `lt`, `pu`, `pd`, `st`, `ht`, `seth`
- **Done:** All aliases exported as globals in turtle.lua.

### ✅ 4.2 Named colors
- `pencolor("red")`, `pencolor("cornflowerblue")`, etc.
- **Done:** 140+ CSS/SVG colors in turtle/colors.lua; require path works
  from student scripts via `require("turtle.colors")` inside core.lua.

### ✅ 4.3 pencolor() / fillcolor() as getters
- `pencolor()` with no args should return current color.
- **Done:** Both functions call `table.unpack(self.pen_color)` /
  `table.unpack(self.fill_color)` when called with no arguments.

### ✅ 4.4 write() positioning
- Text should appear at turtle position.
- **Done:** core:write() logs a "text" segment at {self.x, self.y} with
  alignment options ("left", "center", "right").

### ✅ 4.5 dot() sizing
- Default size should be `max(pensize+4, pensize*2)`.
- **Done:** core:dot() uses `math.max(self.pen_size + 4, self.pen_size * 2)`
  as the default size.

---

## Milestone 5: Turtle Geometry Chapters 2-3

### 5.1 Chapter 2: Procedures (Lua functions)
- Students define their own procedures using `local function`.
- POLY as a procedure, INSPI as a procedure.
- Nested procedure calls.
- No new API needed — this is about Lua the language.

### 5.2 Chapter 3: Feedback, Growth, and Growth Patterns
- EQSPI (equiangular spiral): `side = side + increment` each step.
- Nested polygons.
- Recursive procedures (tree, Koch curve).
- Hilbert curve (Chapter 3, section 3.3).
- These exercise recursion and variables heavily.
- **Test:** Koch snowflake at depth 4 should render cleanly.
- **Test:** Hilbert curve at depth 5 should render cleanly.

---

## Milestone 6: Turtle Geometry Chapter 4 — Topology

### 6.1 Total Turning / Closed Path Theorem
- Verify: any simple closed path has total turning ±360°.
- Students can test this by logging total turning.
- Consider adding a `total_turning()` query function (not in Python turtle,
  but useful for the curriculum).

### 6.2 Self-crossing paths
- Winding numbers.
- Programs that cross themselves.
- Fill behavior on self-crossing paths (even-odd rule vs nonzero).

---

## Milestone 7: Animation and Interaction Polish

### 7.1 Speed tuning
- speed(1) through speed(10) should feel good.
- Calibrate against Python turtle's speed for familiarity.

### 7.2 Window title shows script name
- If possible, show the running script's filename in the title bar.

### 7.3 Keyboard shortcuts
- ESC to close window (already works via Raylib).
- Consider: spacebar to pause/resume animation.

### 7.4 Window resize handling
- Canvas should redraw correctly on resize.
- Currently triggers full redraw via resize_canvas — verify this works.

---

## Milestone 8: Stamps and Undo

### 8.1 Verify stamp/clearstamp/clearstamps
- `stamp()` draws turtle shape at current position, returns ID.
- `clearstamp(id)` removes it (triggers full redraw from log).
- `clearstamps(n)` removes first/last/all n stamps.
- **Test:** Stamp every 50 pixels along a line, then clearstamps(2).

### 8.2 Undo support (stretch goal)
- `undo()` removes the last segment from the log and redraws.
- Requires tracking undo-able boundaries in the segment log.
- Not in initial scope but architecturally straightforward.

---

## Milestone 9: Error Handling and Student Experience

### 9.1 Graceful error messages
- If student script has a Lua error, it should print clearly to terminal.
- The window should not crash — ideally it stays open showing what was
  drawn before the error.

### 9.2 Infinite loop guard
- Detect programs that run too long without yielding.
- The web version used `debug.sethook` — same approach works here.
- Set a configurable timeout (e.g., 10 seconds of CPU time).

### 9.3 Undefined variable detection
- Lua silently returns `nil` for undefined globals.
- Consider a `__index` metatable on the sandbox environment that
  warns on access to undefined names.
- This is a curriculum feature (teaching moment about typos).

---

## Milestone 10: LuaLS Autocomplete and IDE Integration

### 10.1 Verify annotations.lua works with VS Code
- Open a student script in VS Code with LuaLS installed.
- `forward(` should show parameter hints.
- `pencolor(` should show the docstring.
- Configure LuaLS workspace.library to include the turtle annotations path.

### 10.2 Write a .vscode/settings.json template
- Pre-configured LuaLS settings for the turtle library.
- Students copy this into their project.

---

## Milestone 11: Packaging and Distribution

### 11.1 LuaRocks rockspec
- `luaturtle-scm-1.rockspec` that builds `turtleray.so` and installs
  `turtle.lua` + `turtle/*.lua`.
- Depends on system Raylib (via pkg-config or Homebrew).

### 11.2 macOS LuaRocks package with precompiled binary
- Build `turtleray.so` for arm64 and x86_64 (universal binary).
- Publish to LuaRocks.

### 11.3 Linux package
- Build against system Raylib from package manager.
- Test on Ubuntu/Debian.

### 11.4 Windows package
- Cross-compile or build with MinGW.
- Test on Windows 10/11.

---

## Milestone 12: Curriculum Content (Parallel Track)

This runs alongside the implementation work. Each unit in the curriculum
framework (see lua-turtle-curriculum.md, summarized below) needs:

- Example programs in `examples/curriculum/unitNN/`
- Exercise prompts (markdown or comments in Lua files)
- Solution files (separate directory)

### Priority curriculum units (use as road test):
1. Unit 1: Lines and Turns
2. Unit 2: The Square (loops)
3. Unit 3: Regular Polygons (POLY, exterior angle theorem)
4. Unit 4: Variables and Functions
5. Unit 5: Circles and Arcs
6. Unit 6: Spirals (POLYSPI, INSPI, EQSPI)

### Later curriculum units (after implementation is stable):
7. Unit 7: Coordinates and Cartesian Connection
8. Unit 8: Trigonometry
9. Unit 9: Multi-turtle (requires multi-turtle API)
10. Unit 10: Functions as Graphs

---

## Milestone 13: Multi-Turtle (Future)

### 13.1 Design the multi-turtle API
- Python: `t1 = turtle.Turtle(); t2 = turtle.Turtle()`
- Lua equivalent: metatables, method syntax `t1:forward(100)`
- Each turtle has its own core state but shares the renderer/canvas.
- Segment log entries tagged with turtle ID.

### 13.2 Implement and test
- Two turtles drawing simultaneously.
- Different colors, different speeds.
- Chase-and-evade programs (Turtle Geometry Chapter 3).

---

## Milestone 14: Web Port Preparation (Future)

### 14.1 Document what's shared
- `turtle/core.lua` — shared verbatim
- `turtle/colors.lua` — shared verbatim
- `turtle/annotations.lua` — shared verbatim
- `tests/test_*.lua` (core tests) — shared verbatim
- `turtle/renderer.lua` — web-specific replacement
- `turtle.lua` — minor differences (no globals export on web, different init)

### 14.2 Research WebTigerPython's rAF solution
- How they handle synchronous-looking Python in the browser.
- Apply similar approach for Lua + Canvas2D.

---

## Notes for Claude Code Sessions

- Always run from the project root (`~/Desktop/luaturtledesktop` or wherever).
- `turtleray.so` must be in the cwd for `require("turtleray")` to find it.
- Core tests (`tests/test_*.lua`) don't need Raylib — run them freely.
- Visual tests (examples/) need the window — verify visually.
- When fixing bugs, check both speed(0) and speed(5) behavior.
- The segment log is append-only. Mutations happen via clear/reset (log a clear
  entry) or clearstamp (mark stamp as cleared, trigger full redraw).
- Raylib's coordinate system is top-left y-down. The renderer handles the
  transform. Core always works in center-origin y-up.

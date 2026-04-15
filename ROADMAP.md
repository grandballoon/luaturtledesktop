# ROADMAP.md — Implementation Plan

## How to Use This Document

This is an ordered task list for Claude Code sessions. Work top-to-bottom.
Each milestone ends with a concrete test. Reference CLAUDE.md for architecture
context. When working on Turtle Geometry exercises, the human will paste the
specific exercise text.

Milestones marked ✅ are complete. Milestones marked 🔄 are in progress.

---

## Milestone 1: Multi-Turtle Refactor

This is pure Lua, renderer-independent. Do it against the existing Raylib
renderer — correctness matters, not rendering quality.

**Before starting:** Read REFACTOR.md. Apply Refactor 1 (functor-style
turtle.lua), Refactor 3 (decomposed visible_segments), and Refactor 5
(documented signatures) during this milestone. These are cheaper to do
now than to retrofit later.

### 1.1 Introduce screen.lua

Extract shared state from core.lua into a new `turtle/screen.lua`:
- Segment log (append-only list, shared across all turtles)
- Background color
- Turtle registry (list of living cores)
- `visible_segments()` — now handles per-turtle clear boundaries and cleared stamps

Core.new() takes a screen reference. Core appends to screen's segment log
with `turtle_id` on each entry.

**Test:** Create two cores sharing one screen. Both append segments.
`screen:visible_segments()` returns segments from both.

### 1.2 Per-turtle clear and reset

- `core:clear()` logs `{type = "clear", turtle_id = N}`.
- `visible_segments()` finds per-turtle clear boundaries: for each turtle,
  find its most recent clear entry and hide that turtle's segments before it,
  while leaving other turtles' segments visible.
- `core:reset()` resets only the calling turtle's state and clears only its
  segments.
- `bgcolor()` moves to screen.lua (it belongs to the Screen, not any turtle).

**Test:** Replicate Python gotcha tests:
- t1 draws, t2 draws, t1:clear() — t1's lines gone, t2's lines remain.
- t1 draws, t2 draws, t1:reset() — t1 at origin with defaults, t2 untouched.
- bgcolor() called on screen, not on any turtle.

### 1.3 Per-turtle undo with interleaving

Redesign undo to work with shared segment log:
- `_push_undo()` records state snapshot + which segment indices this command
  will add (recorded after the command, not before).
- `core:undo()` restores state snapshot and marks those segment indices as
  hidden (a set, like `_cleared_stamps`).
- `visible_segments()` filters hidden-by-undo segments.
- This correctly handles interleaving: t1:undo() only affects t1's segments,
  even if t2 appended segments in between.

**Test:** Replicate Python gotcha test:
- t1:forward(100), t2:forward(100), t1:left(90), t2:left(90),
  t1:forward(100), t2:forward(100).
- t1:undo() removes t1's second forward. t2 completely untouched.
- t1:undo() again removes t1's left turn. t2 still untouched.

### 1.4 Fill isolation

Verify fill vertex accumulation is per-turtle. t2 drawing during t1's
open fill must not contaminate t1's fill polygon.

**Test:** Replicate Python gotcha test:
- t1:begin_fill(), t1:forward(100), t1:left(90).
- t2:forward(150), t2:left(90), t2:forward(150).
- t1:forward(100), t1:left(90), t1:forward(100), t1:left(90),
  t1:forward(100), t1:end_fill().
- t1's fill is a clean square. t2's lines are separate.

### 1.5 Turtle() constructor and API

- `turtle.Turtle()` creates a new core registered with the default screen.
- Returns a wrapper object with method-style access: `t:forward(100)`.
- The default turtle (created during `require("turtle")`) has its methods
  exported as globals.
- Animated wrappers in turtle.lua work for both the default turtle and
  additional turtles.

**Test:** Run the Python "tracer/update simultaneous movement" pattern:
```lua
screen.tracer(0)
t1 = turtle.Turtle()
t2 = turtle.Turtle()
t1:color("red")
t2:color("blue")
for i = 1, 100 do
    t1:forward(3); t1:left(3)
    t2:forward(3); t2:right(3)
    screen.update()
end
```

### 1.6 Update existing tests

- Add `tests/test_multiturtle.lua` covering all the above.
- Verify existing single-turtle tests still pass (they should — single-turtle
  is just the default turtle on a screen with one turtle).

---

## Milestone 2: Replace Raylib with Cairo + SDL2

**Before starting:** Read GOTCHAS.md (especially the Cairo and SDL2
sections) and REFACTOR.md Refactor 2 (explicit core accessors). When
writing the new renderer.lua, use `core:get_head_state()` from the start
instead of reading core fields directly.

### 2.1 Write turtlecairo.c

New C binding exposing ~25 functions to Lua:
- **SDL2 windowing:** init_window, close_window, window_should_close,
  poll_events, get_screen_width, get_screen_height, set_window_title, wait.
- **Cairo drawing:** create_canvas, draw_line, draw_filled_polygon,
  draw_filled_circle, draw_arc, draw_text, measure_text, clear_canvas,
  present_frame.
- **Canvas management:** begin_canvas, end_canvas (for persistent offscreen
  canvas pattern).

Cairo handles anti-aliasing, alpha, and thick lines natively.
No supersampling, no SDL2_gfx.

Same binding style as turtleray.c: minimal, not general-purpose.

**Test:** `examples/hello_cairo.lua` — opens window, draws red line, green
text, blue circle. Visual verification.

### 2.2 Update renderer.lua

Replace `ray.*` calls with new `cairo.*` calls. The renderer's structure
(persistent canvas + incremental draw + full redraw from log + turtle head
overlay) stays the same.

The premultiplied alpha difference between Cairo and SDL2 surfaces must be
handled in turtlecairo.c, not in renderer.lua.

**Test:** All existing examples (square, star, spiral, circle_flower, poly,
shapes) produce correct output. Visual verification against Raylib output.

### 2.3 Update Makefile

Link against SDL2 and Cairo instead of Raylib.

```makefile
LDFLAGS = -lSDL2 -lcairo
```

Platform detection for include/lib paths (Homebrew on macOS, pkg-config
on Linux, manual paths on Windows).

### 2.4 Delete Raylib artifacts

Remove turtleray.c, hello_raylib.lua. Update README.md dependencies section.

---

## Milestone 3: Custom Lua Interpreter for REPL

### 3.1 Create luaturtle.c

Fork `lua.c` (the standard Lua 5.4 interpreter, ~600 lines).
Modify the input loop to pump SDL2 events while waiting for terminal input:

- Replace `lua_readline` with a version that does non-blocking stdin reads
  interleaved with `SDL_PollEvent` + re-rendering.
- When the turtle window exists and is initialized, pump events and re-render
  between input characters.
- When no window exists (pre-`require("turtle")`), behave like standard Lua.

**Test:** `luaturtle -i -e 'require("turtle")'` — type `forward(100)`,
see it draw. Type `right(90)`. Type `forward(100)`. Window stays responsive
between commands. ESC or window close exits.

### 3.2 Script mode

`luaturtle myscript.lua` — identical to current behavior. Script runs,
`turtle.done()` enters idle event loop.

**Test:** All existing examples work identically to `lua myscript.lua`.

### 3.3 Build and distribute luaturtle

The `luaturtle` binary bundles: Lua 5.4 interpreter + turtlecairo.so +
turtle.lua + turtle/*.lua. This is what gets distributed — users download
one thing, run it.

Makefile target: `make luaturtle`

---

## Milestone 4: Animated Undo

**Before starting:** Read REFACTOR.md Refactor 4 (undo returns a
description). Design the undo return shape before implementing the
animation.

### 4.1 Implement visual line reversal

When `undo()` is called on a line segment, the execution host (turtle.lua)
animates the turtle retracing the line backward before restoring the state
snapshot. This mirrors Python turtle's undo behavior.

- Determine the segment type being undone (line, turn, fill, etc.)
- For lines: animate the turtle moving backward along the line, erasing it
- For turns: animate the reverse turn
- For other types (fill, dot, stamp, text): instant removal is acceptable

**Test:** Draw a square with `speed(3)`. Call `undo()` four times. Each
forward is visually reversed (turtle retraces the line). Each turn is
visually reversed.

---

## Milestone 5: Turtle Geometry Road Test

Work through exercises from *Turtle Geometry* (Abelson & diSessa) Chapters 1-4
using the multi-turtle, REPL-capable system:

### 5.1 Chapter 1: POLY, INSPI, variations
### 5.2 Chapter 2: Procedures (Lua functions)
### 5.3 Chapter 3: Feedback, Growth, Growth Patterns (Koch, Hilbert, trees)
### 5.4 Chapter 4: Topology (total turning, winding numbers, self-crossing)
### 5.5 Multi-turtle exercises: chase-and-evade (Chapter 3)

Each working exercise becomes an example file in `examples/`.

---

## Milestone 6: Packaging and Distribution

**Before starting:** Read GOTCHAS.md thoroughly. Every platform has
distribution-specific issues documented there. Budget time for
codesigning and notarization (macOS), SmartScreen (Windows), and
glibc/AppImage concerns (Linux).

### 6.1 macOS

- Build universal binary (arm64 + x86_64).
- Create `.app` bundle with bundled dylibs (SDL2, Cairo, pixman).
- Codesign + notarize (requires Apple Developer ID, $99/year).
- Distribute as `.dmg`.

### 6.2 Linux

- Build against system SDL2 + Cairo.
- Create AppImage (self-contained, no installation needed).
- Test on Ubuntu/Debian.

### 6.3 Windows

- Build with MinGW or MSVC.
- Ship `luaturtle.exe` + `SDL2.dll` + `cairo.dll` in a zip.
- Optionally: static link for single-exe distribution.
- Code signing (Authenticode) to avoid SmartScreen warnings.

---

## Milestone 7: Curriculum Content (Parallel Track)

Runs alongside implementation. Each unit needs example programs, exercise
prompts, and solution files.

### Priority units (road test):
1. Lines and Turns
2. The Square (loops)
3. Regular Polygons (POLY, exterior angle theorem)
4. Variables and Functions
5. Circles and Arcs
6. Spirals (POLYSPI, INSPI, EQSPI)

### Later units:
7. Coordinates and Cartesian Connection
8. Trigonometry
9. Multi-turtle
10. Functions as Graphs

---

## Milestone 8: Web Version (Separate Repo)

**Before starting:** Read GOTCHAS.md web section (SharedArrayBuffer
headers, Atomics.wait restrictions, browser compatibility).

### 8.1 Set up web repo

New repo: `luaturtleweb` (or similar).
Copy shared files: `core.lua`, `screen.lua`, `colors.lua`, test suite.

### 8.2 Web Worker + Wasmoon execution host

Lua runs in a Web Worker via Wasmoon. User code executes synchronously
in the worker. Turtle commands send draw instructions to the main thread
via `postMessage`. Worker blocks via `Atomics.wait` for animation frames.
Main thread notifies via `Atomics.notify` when frame is rendered.

### 8.3 Canvas2D renderer

Main thread renders using Canvas2D. Same persistent canvas / damage-and-repair
pattern. Reads the segment log shape (sent from worker as serialized data).

### 8.4 IDE shell

CodeMirror editor, run/stop buttons, console output. Both script mode
(run entire program) and REPL mode (execute one line at a time from a
console input).

---

## Notes for Claude Code Sessions

- Always run from the project root.
- Core tests (`tests/test_*.lua`) don't need Cairo/SDL2 — run them freely.
- Visual tests (examples/) need the window — verify visually.
- When fixing bugs, check both speed(0) and speed(5) behavior.
- The segment log is append-only. Mutations happen via clear (log a clear
  entry), clearstamp (mark as cleared), or undo (mark as hidden).
- Segment log entries carry `turtle_id` for multi-turtle support.
- Cairo's coordinate system has y-up by default, but when drawing to an
  image surface the y-axis is top-down. The renderer handles the transform.
- The premultiplied alpha difference between Cairo and SDL2 is handled in
  the C binding, not in Lua.

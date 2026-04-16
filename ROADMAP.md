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
## Milestone 3: REPL as Lua module (readline callback interface)

**Before starting:** Read DECISIONS.md #6 and GOTCHAS.md Readline section.
The REPL is a Lua module backed by a small C binding. It does not fork
the standard Lua interpreter.

### 3.1 Write turtle_readline.c

Minimal C binding (~150 lines) wrapping GNU readline's alternate (callback)
interface. Exposes to Lua:

- `readline.install_handler(prompt, callback)` — wraps
  `rl_callback_handler_install`. Stash the Lua callback via `luaL_ref`.
- `readline.read_char()` — wraps `rl_callback_read_char`. Reads one
  character, dispatches to readline's state machine, invokes callback
  only when a full line is ready.
- `readline.stdin_has_input(timeout_ms)` — wraps `select()` on fd 0 with
  a short timeout so the event loop doesn't burn CPU.
- `readline.remove_handler()` — wraps `rl_callback_handler_remove`.
- `readline.add_history(line)` — wraps `add_history` for up-arrow recall.

Link with `-lreadline` in the Makefile. Note: readline's state is global,
so `turtle_readline` is not reentrant — do not run two REPLs
simultaneously.

**Test:** Minimal smoke test — install a handler, type a line, verify
the callback fires with the right string.

### 3.2 Write turtle/repl.lua

REPL event loop in Lua. Structure: render → check input → execute. Render
every iteration (~100 Hz given the 10ms stdin timeout) so the window stays
responsive whether the user is typing, thinking, or away from the keyboard.

See MILESTONE_3.md for the full module source.

Behavior: `load(line)` first, fall back to `load("return " .. line)` so
bare expressions print their value (matches standard Lua REPL `=` behavior).
`exit` or `quit` ends the loop. Errors print but don't kill the REPL.

### 3.3 Script mode unchanged

`lua myscript.lua` works exactly as it does after M2. No changes needed —
script mode never touched the REPL.

**Test:** All existing examples continue to run via `lua myscript.lua`.

### 3.4 Entry point

Canonical invocation: `lua -e 'require("turtle.repl").start()'`.
Ship a trivial shell script `luaturtle`:

```sh
#!/bin/sh
exec lua -e 'require("turtle.repl").start()' "$@"
```

### Acceptance test

Launch the REPL. Type `forward(100)` — window appears, turtle draws. Type
`right(90)`. Type `forward(100)`. Drag the window to resize — redraw happens
smoothly during drag. Press up arrow — previous line appears for editing.
Type `exit` — REPL terminates, window closes.
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

## Milestone 6: Packaging and Distribution (LuaRocks)

**Decision:** LuaRocks-only distribution for now. No bundled interpreter.
Users install Lua 5.4 + readline themselves and `luarocks install luaturtle`.
A bundled per-platform binary remains a future option but is not in scope.

**Before starting:** Read GOTCHAS.md. Cross-platform Cairo/SDL2 concerns
still apply to the compiled `.so` files.

### 6.1 LuaRocks rockspec

Ship:
- `turtlecairo.so` (built from `turtlecairo.c`, links SDL2 + Cairo)
- `turtle_readline.so` (built from `turtle_readline.c`, links readline)
- The `turtle/` Lua directory (core.lua, screen.lua, repl.lua, colors.lua, annotations.lua)
- `turtle.lua`
- `luaturtle` shell script (installed to bin path)

Rockspec declares external dependencies: SDL2, Cairo, readline. Users
install these via their system package manager (Homebrew, apt, etc.)
before running `luarocks install`.

### 6.2 Platform notes

- **macOS:** Homebrew provides SDL2, Cairo, readline. No codesigning
  concerns at the LuaRocks layer — users link against their own installed
  libraries. Document Homebrew install commands in README.
- **Linux:** SDL2, Cairo, readline are in every major distro. AppImage
  concerns do not apply. Document apt/dnf install commands.
- **Windows:** Blocked on the readline decision (WinEditLine/libedit vs.
  Windows console API via `#ifdef`). Document as unsupported for now in
  README; track in GOTCHAS.md.

### 6.3 Future: bundled distribution

Left open as a later milestone. If bundled distribution is pursued, it
becomes "standard `lua` binary + our `.so` files + our `.lua` files in a
folder" — not a forked interpreter. This is a packaging convenience, not
an architectural commitment.
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

# Architecture

## Overview

Lua Turtle Desktop is a synchronous turtle graphics library for Lua 5.4.
The student's script is the main program. It runs top-to-bottom. Drawing
commands open a window (lazily, on first draw call), draw immediately, and
return. The window stays open after the script ends.

This is the desktop counterpart to the browser-based Lua Turtle (luaturtleweb).
The two implementations share API surface and coordinate conventions but have
independent codebases — the browser version uses an action queue and
requestAnimationFrame; this version executes synchronously.

## Technology Stack

- **Language:** Lua 5.4 (PUC-Rio reference implementation)
- **GUI toolkit:** IUP 3.32+ (Tecgraf/PUC-Rio)
- **2D graphics:** CD 5.14+ Canvas Draw (Tecgraf/PUC-Rio)
- **Alpha/AA:** Context Plus drivers (GDI+ on Windows, Cairo on Linux/macOS)
- **Editor:** External (VS Code recommended, with LuaLS for autocomplete)
- **Distribution:** LuaRocks package depending on iuplua and iuplua-cd

## Key Decisions

### Why IUP+CD (not Raylib, SDL2, LÖVE, etc.)

IUP and CD are made by the same institution that created Lua (Tecgraf/PUC-Rio).
Lua bindings are first-class, not afterthoughts. CD provides professional 2D
vector graphics (anti-aliased lines, native arcs, filled polygons, text, alpha
via context plus drivers). IUP provides cross-platform windowing with native
controls.

Raylib was considered but has no production-quality Lua 5.4 binding on LuaRocks.
SDL2's Lua binding is stale. LÖVE requires a framework-owns-the-main-loop
architecture incompatible with the "write a script, hit run" UX.

### Why synchronous (not queued)

On desktop, the student's script IS the main thread. `forward(100)` can
directly: update state, draw to the CD canvas, flush the display, sleep for
animation, and return. No action queue, no dissolution pattern, no coroutines
needed for basic use.

The action queue from the web version existed to work around the browser's
requestAnimationFrame constraint. That constraint doesn't exist here.

### Why track Python turtle's API

The Python turtle API is battle-tested by millions of students. Tracking it
for the core ~30 commands gives free mental-model transfer for students and
teachers moving between Python and Lua. We diverge freely on:
- Object model (Lua idioms, not Python classes)
- Window management (no Tkinter ceremony)
- Event system (IUP callbacks, not Tkinter)

Warts are kept where the cost of divergence exceeds the cost of the wart
(e.g., `speed(0)` = fastest is confusing but widely known).

## Execution Model

### Script mode (primary)

```
lua myscript.lua
```

The turtle module initializes lazily. First drawing command creates the IUP
dialog + CD canvas. Subsequent commands draw incrementally. When the script
ends, `turtle.done()` (or an atexit hook) enters `IupMainLoop()` to keep the
window open until the user closes it.

### REPL mode

```
lua -i -e 'require("turtle")'
```

The IUP window persists between inputs. `IupLoopStep()` is called between
REPL inputs to keep the window responsive. The CD canvas retains all drawing
between commands.

### Animated mode

For `speed(n)` where n > 0, drawing commands break movement into small steps:
- Move a small increment
- Draw the line segment to the CD canvas
- Flush the double buffer
- Sleep briefly (or call `IupLoopStep()` + busy-wait)
- Repeat

For `speed(0)`, commands execute instantly with no animation.

## Module Structure

```
luaturtledesktop/
├── README.md
├── ARCHITECTURE.md          # this file
├── turtle.lua               # user-facing API module
├── turtle/
│   ├── core.lua             # state machine, segment log, stamp registry
│   ├── renderer.lua         # IUP+CD rendering backend
│   ├── colors.lua           # named color table
│   └── annotations.lua      # LuaLS type stubs for IDE autocomplete
├── tests/
│   ├── run_tests.sh
│   ├── test_helpers.lua
│   ├── test_position.lua
│   ├── test_pen.lua
│   ├── test_segments.lua
│   ├── test_circle_arc.lua
│   ├── test_fill.lua
│   ├── test_stamps.lua
│   └── test_programs.lua
├── examples/
│   ├── square.lua
│   ├── star.lua
│   ├── spiral.lua
│   ├── circle_flower.lua
│   └── poly.lua             # Turtle Geometry Chapter 1 exercises
└── luaturtle-scm-1.rockspec
```

### turtle.lua (entry point)

The module returned by `require("turtle")`. On load, it:
1. Requires turtle.core and turtle.renderer
2. Exposes all API functions as module fields AND as globals
   (so both `turtle.forward(100)` and `forward(100)` work)
3. Defers window creation until first drawing command

### turtle/core.lua

Pure Lua, no dependencies. Owns:
- Position (x, y) in turtle-space
- Heading (angle in degrees, 0=east, CCW positive)
- Pen state (down, color with alpha, size)
- Fill state (recording vertices between begin_fill/end_fill)
- Segment log (append-only list of {type, data} records)
- Stamp registry (segment log entries tagged with stamp IDs)
- Background color

Does NOT own rendering. Calls renderer methods to draw.

### turtle/renderer.lua

IUP+CD backend. Owns:
- IUP dialog and canvas widget
- CD canvas (double-buffered, context plus enabled)
- Coordinate transform (turtle-space to screen-space)
- Drawing primitives (line, arc, polygon, text)
- Animation timing (sleep/flush between incremental steps)
- Event loop management (IupMainLoop, IupLoopStep)
- Full redraw from segment log (for clearstamp, window resize)

### turtle/colors.lua

Named color lookup table. Maps "red" → {1, 0, 0, 1}, etc.
Includes all 140 CSS/SVG named colors (same set Python turtle uses via Tk).

### turtle/annotations.lua

LuaLS (sumneko) type annotation file. Provides autocomplete and hover docs
in VS Code without any extension. Not loaded at runtime.

## Segment Log

The segment log is an append-only list of drawing records:

```lua
{ type = "line",    from = {x,y}, to = {x,y}, color = {r,g,b,a}, width = n }
{ type = "arc",     center = {x,y}, radius = n, start_angle = a, extent = a, color = ..., width = ... }
{ type = "fill",    vertices = {{x,y}, ...}, color = {r,g,b,a} }
{ type = "stamp",   id = n, shape_vertices = {{x,y}, ...}, color = ..., fill_color = ... }
{ type = "dot",     pos = {x,y}, size = n, color = {r,g,b,a} }
{ type = "text",    pos = {x,y}, content = "...", font = ..., color = ... }
{ type = "clear",   turtle_id = n }  -- marks a clear boundary
```

The renderer maintains a "committed up to" index. On each draw command, it
renders only new entries. On clearstamp or window resize, it replays the
entire log (skipping cleared stamps) to reconstruct the canvas.

## Coordinate System

- Core works in turtle-space: center origin, y-up, angles in degrees
- 0° = east, 90° = north, counter-clockwise positive
- Renderer transforms to screen-space: top-left origin, y-down
- Transform: screen_x = center_x + turtle_x, screen_y = center_y - turtle_y
- CD's default coordinate system is bottom-left y-up, so the transform is
  actually just a translation to center the origin (CD handles the y-flip)

## Animation and Timing

Animation speed follows Python turtle's convention:
- speed(0) = instant (no animation)
- speed(1) = slowest
- speed(10) = fastest
- Default: speed(5) — deliberately not specified yet, will tune during testing

Between animation steps, the renderer calls `IupLoopStep()` to keep the
window responsive (prevents "not responding" on the OS level) and uses
`os.clock()` busy-wait or `IupFlush()` + sleep for frame pacing.

## Alpha Transparency

CD supports alpha via Context Plus drivers:
- Windows: GDI+ (`cdUseContextPlus(1)`)
- Linux: Cairo context plus
- macOS: Cairo context plus

The renderer enables context plus at canvas creation time. Colors throughout
the system carry 4 components (r, g, b, a). The API accepts both:
- `pencolor(r, g, b)` — alpha defaults to 1 (opaque)
- `pencolor(r, g, b, a)` — explicit alpha

Channel values auto-detected: all <= 1 → 0-1 range; any > 1 → 0-255 range.

## Testing

Core tests use plain Lua 5.4 assertions against a renderer stub (same
pattern as the web version). No IUP/CD dependency for core tests.

Renderer tests require IUP+CD installed and are run separately.

Integration tests run complete programs (Turtle Geometry exercises, Python
turtle examples) and verify they execute without error.

## Future: Web Port

When porting back to the web, the approach will follow WebTigerPython's
solution to the rAF problem. The desktop and web versions will be separate
repos with shared API surface and coordinate conventions. Good documentation
and testing are the bridge, not shared code.

Free wins for the web port:
- Segment log format is renderer-agnostic
- API surface is identical
- Coordinate conventions are identical
- Named color table is pure Lua, shared directly
- LuaLS annotations are shared directly
- Test suite (core tests) is shared directly

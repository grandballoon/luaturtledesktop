# ARCHITECTURE.md

## Overview

Lua Turtle Desktop is a synchronous turtle graphics library for Lua 5.4.
The student's script is the main program. It runs top-to-bottom. Drawing
commands open a window (lazily, on first draw call), draw immediately, and
return. The window stays open after the script ends.

This is the desktop counterpart to a future browser-based Lua Turtle.
The two implementations share core logic (`core.lua`, `screen.lua`,
`colors.lua`) and the test suite. They have independent execution hosts
and renderers. The user-facing API and behavior are identical.

## Technology Stack

- **Language:** Lua 5.4 (PUC-Rio reference implementation)
- **Windowing & events:** SDL2
- **2D drawing:** Cairo
- **Editor:** External (VS Code recommended, with LuaLS for autocomplete)
- **Distribution:** Platform-specific binaries bundling Lua + libraries

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│              User's Lua Script              │
│    forward(100); right(90); forward(100)    │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│           turtle.lua (execution host)        │
│  Animation timing, undo snapshots, speed,    │
│  animated undo, globals export, REPL glue    │
└───────┬──────────────────────────┬──────────┘
        │                          │
┌───────▼────────┐    ┌────────────▼───────────┐
│   core.lua     │    │     screen.lua          │
│  (per-turtle)  │───▶│  (shared state)         │
│  Position,     │    │  Segment log,           │
│  heading, pen, │    │  bg_color,              │
│  fill, undo    │    │  turtle registry,       │
│                │    │  visible_segments()     │
└────────────────┘    └────────────┬───────────┘
                                   │
                      ┌────────────▼───────────┐
                      │   renderer.lua          │
                      │   Reads segment log,    │
                      │   calls turtlecairo.c   │
                      └────────────┬───────────┘
                                   │
                      ┌────────────▼───────────┐
                      │    turtlecairo.c        │
                      │  SDL2: window, events   │
                      │  Cairo: lines, fills,   │
                      │  circles, text, alpha   │
                      └────────────────────────┘
```

## Key Decisions and Rationale

### Why Cairo + SDL2 (not Raylib, not IUP+CD, not platform-native)

**Raylib** was the original renderer. It works well for script mode but has
a fundamental limitation: no non-blocking event processing. The only way to
pump OS events is through `BeginDrawing/EndDrawing`. This makes REPL mode
impossible — the window freezes while Lua waits for terminal input.

**IUP+CD** (Tecgraf/PUC-Rio) was considered for its Lua heritage. CD provides
excellent 2D graphics with alpha (via Context Plus drivers). However, IUP+CD
has limited availability on modern package managers and a less active
maintenance community than SDL2 or Cairo.

**Platform-native** (CoreGraphics + Direct2D + Cairo/X11) gives the best
rendering quality per-platform but triples the windowing code. For a
one-person project, three windowing backends is too much maintenance surface.

**Cairo + SDL2** was chosen because:
- Cairo provides native anti-aliased thick lines, alpha compositing, filled
  polygons, and text — the exact drawing primitives turtle needs, without
  supersampling hacks or SDL2_gfx.
- SDL2 provides cross-platform windowing with `SDL_PollEvent` for REPL mode.
- The pairing mirrors the web architecture (Browser + Canvas2D), creating
  a clean conceptual symmetry between desktop and web.
- Both libraries are well-packaged on all three target platforms (Homebrew,
  apt, vcpkg).

### Why synchronous execution (not queued)

On desktop, the student's script IS the main thread. `forward(100)` can
directly: update state, draw to the Cairo canvas, present via SDL2, sleep
for animation, and return. No action queue, no coroutines needed for basic use.

The web version will achieve the same synchronous user experience using
the WebTigerPython approach: Lua runs in a Web Worker, turtle commands
block the worker via `Atomics.wait`, the main thread animates and notifies.
The core code is identical — only the "how do we pause between animation
steps" differs (sleep on desktop, `Atomics.wait` on web).

### Why a shared segment log with turtle IDs (not per-turtle logs)

Multiple turtles share one append-only segment log. Each entry carries a
`turtle_id`. This design was chosen because:
- `visible_segments()` can return all segments in draw order for the renderer.
- Per-turtle `clear()` works by logging a `{type="clear", turtle_id=N}` and
  filtering in `visible_segments()`.
- Undo works by marking segment indices as hidden, not by truncating the log.
- The renderer replays one log, drawing everything in the order it was created.
  This naturally handles z-ordering (later segments draw on top).

### Why per-turtle undo uses index marking (not log truncation)

With a shared log, truncating on undo would remove other turtles' segments
that were appended after the undone command. Instead, each turtle's undo
stack records which segment indices it added. Undo marks those indices as
hidden. `visible_segments()` filters them, same as it filters cleared stamps.
This correctly handles interleaved multi-turtle commands.

### Why bgcolor belongs to Screen, not Turtle

Python turtle places `bgcolor()` on the Screen object, not on any individual
turtle. This is correct — background color is a property of the canvas, not
of any turtle's pen state. In the API, `bgcolor()` is a module-level function
that routes to the Screen.

## Execution Model

### Script mode (primary)

```
luaturtle myscript.lua
```

The turtle module initializes lazily. First drawing command creates the SDL2
window + Cairo canvas. Subsequent commands draw incrementally. When the script
ends, `turtle.done()` enters `SDL_PollEvent` loop to keep the window open.

### REPL mode

```
luaturtle -i -e 'require("turtle")'
```

Uses a custom Lua interpreter (`luaturtle`) that pumps SDL2 events while
waiting for terminal input. Each line executes synchronously, renders, and
returns to the prompt. The window stays responsive between inputs.

### Animated mode

For `speed(n)` where n > 0, drawing commands break movement into small steps:
- Move a small increment
- Draw the line segment to the Cairo canvas
- Present via SDL2
- Sleep briefly
- Repeat

For `speed(0)`, commands execute instantly with no animation.

Multi-turtle animation is sequential per-command (t1's forward completes,
then t2's forward starts). For simultaneous movement, use `tracer(0)` +
manual `screen.update()` calls in a loop — same pattern as Python turtle.

## Segment Log

The segment log is an append-only list of drawing records:

```lua
{ type = "line",  turtle_id = 1, from = {x,y}, to = {x,y}, color = {r,g,b,a}, width = n }
{ type = "arc",   turtle_id = 1, center = {x,y}, radius = n, start_angle = a, extent = a, ... }
{ type = "fill",  turtle_id = 1, vertices = {{x,y}, ...}, color = {r,g,b,a} }
{ type = "stamp", turtle_id = 1, id = n, pos = {x,y}, heading = a, ... }
{ type = "dot",   turtle_id = 1, pos = {x,y}, size = n, color = {r,g,b,a} }
{ type = "text",  turtle_id = 1, pos = {x,y}, content = "...", font = ..., color = ... }
{ type = "clear", turtle_id = 1 }
```

The renderer maintains a "committed up to" index. On each draw command, it
renders only new entries. On clear/clearstamp/undo/resize, it replays the
entire visible log to reconstruct the canvas.

## Coordinate System

- Core works in turtle-space: center origin, y-up, angles in degrees
- 0° = east, 90° = north, counter-clockwise positive
- Renderer transforms to screen-space: top-left origin, y-down
- Transform: screen_x = center_x + turtle_x, screen_y = center_y - turtle_y

## Web Port Architecture (Future)

When porting to the web, the approach follows WebTigerPython's solution:

- Lua runs in a Web Worker via Wasmoon (Lua 5.4 compiled to WASM)
- Canvas2D renders on the main thread
- Communication via `postMessage` + `SharedArrayBuffer` + `Atomics.wait`
- `core.lua`, `screen.lua`, `colors.lua` are shared verbatim
- Execution host and renderer are web-specific

The desktop and web versions will be separate repos with shared core logic.
Good documentation and testing are the bridge, not shared code in the
execution host or renderer layers.

## Testing

Core tests use plain Lua 5.4 assertions against screen/core with no
renderer dependency. No Cairo/SDL2 needed for core tests.

Multi-turtle tests verify behavior against Python turtle's actual behavior,
validated via test scripts run against CPython.

Visual tests (examples/) require the window and are verified visually.

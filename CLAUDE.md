# CLAUDE.md — Lua Turtle Desktop

## What This Is

A desktop turtle graphics library for Lua 5.4 using Raylib for rendering. Students write normal Lua scripts, a graphics window appears. Inspired by Python's `turtle` module and Seymour Papert's *Mindstorms*.

## Architecture

- **turtle.lua** — Entry point (`require("turtle")`). Wires core + renderer, exports all API functions as globals.
- **turtle/core.lua** — Pure Lua state machine. Position, heading, pen state, fill state, segment log, stamps. No rendering dependencies. Testable with plain Lua.
- **turtle/renderer.lua** — Raylib backend. Window, persistent render texture (offscreen canvas), coordinate transform (turtle-space center-origin y-up → screen-space top-left y-down), incremental + full redraw from segment log.
- **turtleray.c** — C binding exposing ~30 Raylib functions to Lua 5.4. NOT a general Raylib binding — only what turtle needs.
- **turtle/colors.lua** — 140+ CSS/SVG named colors.
- **turtle/annotations.lua** — LuaLS type stubs for VS Code autocomplete (not loaded at runtime).

## Build

```bash
make                    # builds turtleray.so
make test               # runs core tests (no Raylib needed)
lua examples/square.lua # run from project root (turtleray.so must be in cwd)
```

Requires: Lua 5.4, Raylib 5.5 (both via Homebrew on macOS).

## Key Design Decisions

- **Synchronous execution.** `forward(100)` draws and returns. No action queue, no coroutines.
- **Track Python turtle API** for core ~30 commands. Same function names, same parameter conventions.
- **Segment log** — append-only list in `core.segments`. Renderer draws incrementally (new segments only) or replays the full log on clear/resize/clearstamp.
- **Render texture** — Raylib RenderTexture2D acts as persistent canvas. Drawing commands draw to it; each frame blits it to screen plus the ephemeral turtle head overlay.
- **speed(0)** = instant mode, no per-command rendering. `turtle.done()` triggers a full redraw then enters the window loop. speed(1-10) = animated with per-step rendering and sleep.
- **Globals exported** — `require("turtle")` injects `forward`, `right`, `pencolor`, etc. into `_G` so students can write bare function calls.
- **`goto` is reserved in Lua** — use `setpos(x, y)` instead (Python turtle also supports this alias).

## Coordinate System

- Core: center origin (0,0), y-up, angles in degrees, 0° = east, CCW positive
- Screen: top-left origin, y-down (Raylib default)
- Transform in renderer: `screen_x = width/2 + turtle_x`, `screen_y = height/2 - turtle_y`

## Known Issues / Current Work

- **speed() has no visible effect** — `speed_setting` is set on core but `renderer:frame_delay()` and the animated step logic in `turtle.lua` need debugging. The delay values may be too small or `renderer:sleep()` (which calls `ray.wait()`) may not be working as expected with Raylib's frame timing.
- **Window must be closed with ESC or window close button** — `turtle.done()` enters `mainloop()`.
- **Tests must run from project root** — `package.path` assumes `./?.lua;./turtle/?.lua;`.

## File Conventions

- All turtle API functions are defined in `turtle.lua` as wrappers around `core` methods.
- Core methods take `self` (OOP style): `core:forward(100)`.
- The animated wrappers in `turtle.lua` handle the speed/render/sleep logic.
- C binding functions use snake_case matching Raylib convention: `ray.draw_line(...)`.
- Colors are {r, g, b, a} tables in 0-1 range internally. The C binding expects 0-255 integers.

## Testing

```bash
lua tests/test_position.lua   # from project root
lua tests/test_pen.lua
```

Core tests use `turtle/core.lua` directly with no Raylib dependency. Test helpers are in `tests/test_helpers.lua`.

## Road Test Goal

Work through exercises from *Turtle Geometry* (Abelson & diSessa) Chapters 1-4:
- POLY, INSPI, variations
- Circle/arc constructions
- Closed path theorem exercises
- Symmetry and recursion

If these all work correctly, the library is road-tested.

## Python Turtle API Coverage

Implemented: forward/fd, back/bk, right/rt, left/lt, circle, setpos, setx, sety, setheading/seth, home, teleport, penup/pu, pendown/pd, pensize/width, pencolor, fillcolor, color, begin_fill, end_fill, filling, dot, write, stamp, clearstamp, clearstamps, clear, reset, bgcolor, position/pos, xcor, ycor, heading, isdown, isvisible, towards, distance, showturtle/st, hideturtle/ht, speed, tracer, update, done/mainloop, bye.

Not yet implemented: shape, shapesize, tilt, undo, degrees/radians mode, setworldcoordinates, onkey/onclick/ondrag events, textinput/numinput.

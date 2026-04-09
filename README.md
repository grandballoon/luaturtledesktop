# Lua Turtle (Desktop)

A desktop turtle graphics library for Lua 5.4, inspired by Python's `turtle` module and Seymour Papert's *Mindstorms*.

Students write normal Lua scripts. A graphics window appears. No framework, no special launcher — just `lua myfile.lua`.

```lua
local turtle = require("turtle")

forward(100)
right(90)
forward(100)

turtle.done()
```

## Architecture

- **turtle.lua** — User-facing API module. Manages turtle state, segment log, stamps, and rendering via IUP+CD.
- **IUP** — Portable GUI toolkit (Tecgraf/PUC-Rio). Creates the graphics window and handles events.
- **CD (Canvas Draw)** — 2D graphics library (Tecgraf/PUC-Rio). Draws lines, arcs, polygons, text with anti-aliasing and alpha transparency.
- **Context Plus drivers** — GDI+ on Windows, Cairo on Linux/macOS. Required for alpha color support.

The student never sees IUP or CD. They see `forward`, `right`, `pencolor`.

## Design Principles

- **Track Python turtle's API** for the core ~30 commands. Diverge on object model and window management where Lua idioms are better.
- **Synchronous execution.** `forward(100)` draws and returns. No action queue, no coroutines required for basic use.
- **Animated drawing** via incremental steps with sleeps between. The canvas is persistent — new drawing adds to existing content.
- **REPL-compatible.** The window persists between interactive commands.
- **Segment log** — append-only record of all drawing operations. Supports `clearstamp()`, `clear()`, `undo()` via redraw-from-log.

## Dependencies

- Lua 5.4
- IUP 3.32+ with Lua binding (`iuplua`)
- CD 5.14+ with Lua binding (`cdlua`, `iupluacd`)
- Context Plus libraries (`cdluacontextplus` for Cairo/GDI+)

### Install via LuaRocks (Linux x86_64)

```sh
luarocks install iuplua
luarocks install iuplua-cd
```

macOS and Windows: install IUP/CD from [Tecgraf SourceForge](https://sourceforge.net/projects/iup/files/) or use the (forthcoming) platform-specific LuaRocks packages.

## Coordinate System

- Center origin (0, 0) at screen center
- Y-up (positive y goes up)
- Angles in degrees, 0° = east, counter-clockwise positive
- Standard math convention (matches Python turtle's "standard" mode)

## Status

Early development. Working toward running the exercises from *Turtle Geometry* (Abelson & diSessa) as the road test.

## License

MIT

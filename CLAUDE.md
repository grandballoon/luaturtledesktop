# CLAUDE.md — Lua Turtle Desktop

## What This Is

A desktop turtle graphics library for Lua 5.4 using Cairo (drawing) and SDL2 (windowing/events). Students write normal Lua scripts, a graphics window appears. Inspired by Python's `turtle` module and Seymour Papert's *Mindstorms*.

A separate web-based version (Canvas2D + Wasmoon) will live in a different repo. The two implementations share `core.lua`, `screen.lua`, `colors.lua`, and the test suite. They have independent execution hosts and renderers. The user-facing API and behavior must be identical across both.

## Architecture

```
[User code] → [turtle.lua (execution host)] → [Core (pure state machine)] → [Segment log]
                                                                                   ↓
                                                                          [Renderer reads log, draws]
```

- **turtle.lua** — Entry point (`require("turtle")`). Execution host: manages animation timing, speed, undo snapshots, REPL integration. Exports all API functions as globals. Creates a default Screen and default Turtle.
- **turtle/screen.lua** — Shared state: segment log (append-only), background color, turtle registry. One Screen per window. Owns `visible_segments()` logic including per-turtle clear boundaries and cleared stamp filtering.
- **turtle/core.lua** — Per-turtle state machine. Position, heading, pen state, fill state, visibility. Appends to the Screen's shared segment log with `turtle_id` tags. No rendering dependencies. Testable with plain Lua.
- **turtlecairo.c** — C binding exposing Cairo drawing + SDL2 windowing to Lua 5.4. NOT a general binding — only what turtle needs. Handles coordinate transform (turtle-space center-origin y-up → screen-space top-left y-down).
- **turtle/colors.lua** — 140+ CSS/SVG named colors.
- **turtle/annotations.lua** — LuaLS type stubs for VS Code autocomplete (not loaded at runtime).

### Why Cairo + SDL2

- **Cairo** provides native anti-aliased thick lines, alpha compositing, filled polygons, and text rendering. No supersampling hacks. Professional vector graphics quality from a C API. This maps directly to the segment log: lines, fills, dots, text, arcs.
- **SDL2** provides cross-platform windowing, event handling, and — critically — `SDL_PollEvent` for non-blocking event processing, which enables REPL mode. SDL2 handles macOS/Windows/Linux window creation without platform-specific code.
- **Together** they mirror the web architecture: SDL2 is to the desktop what the Browser is to the web. Cairo is to the desktop what Canvas2D is to the web. Same shape, different platforms.

### Why not Raylib (previous renderer)

Raylib has no non-blocking event processing. The only way to pump OS events is through `BeginDrawing/EndDrawing`. This makes REPL mode impossible — the window becomes unresponsive while Lua waits for terminal input. This is a fundamental architectural mismatch that cannot be worked around cleanly.

## Key Design Decisions

- **Synchronous execution.** `forward(100)` draws and returns. No action queue, no coroutines. The web version will achieve the same synchronous-from-user-perspective behavior via Web Worker + `Atomics.wait` (the WebTigerPython approach).
- **Track Python turtle API** for core ~30 commands. Same function names, same parameter conventions, same multi-turtle behavior. Verified against Python's actual behavior for: animation interleaving (sequential), per-turtle clear/reset, per-turtle undo with interleaving, fill isolation between turtles, bgcolor on Screen not Turtle, tracer/update for simultaneous movement.
- **Segment log** — append-only list of `{type, turtle_id, ...}` records. Renderer draws incrementally (new segments only) or replays the full log on clear/resize/clearstamp/undo.
- **Per-turtle undo** — each turtle's undo stack records which segment indices it added. Undo marks those segments as hidden (like cleared stamps) rather than truncating the shared log. This correctly handles interleaved multi-turtle commands. Animated undo (visual reversal) is an execution-host concern, not a core concern.
- **Globals exported** — `require("turtle")` injects `forward`, `right`, `pencolor`, etc. into `_G`.
- **`goto` is reserved in Lua** — use `setpos(x, y)` instead.
- **Renderer is a leaf dependency.** The core, screen, segment log, API surface, and execution model are renderer-independent. The segment log shape IS the abstraction between core and renderer. No `Renderer` interface/adapter pattern — `turtlecairo.c` knows it uses Cairo, `renderer.js` (web) knows it uses Canvas2D. Both read the same log shape.

## Module Structure

```
├── turtle.lua               # execution host: animation, undo, globals
├── turtle/
│   ├── screen.lua           # shared state: segment log, bg_color, turtle registry
│   ├── core.lua             # per-turtle state machine
│   ├── repl.lua             # REPL event loop (SDL2 + readline interleaved)
│   ├── colors.lua           # named color table
│   └── annotations.lua      # LuaLS type stubs
├── turtlecairo.c            # C binding: Cairo drawing + SDL2 windowing
├── turtle_readline.c        # C binding: GNU readline alternate interface
├── luaturtle                # shell script: exec lua -e 'require("turtle.repl").start()' "$@"
```

## Coordinate System

- Core: center origin (0,0), y-up, angles in degrees, 0° = east, CCW positive
- Screen: top-left origin, y-down
- Transform in renderer: `screen_x = width/2 + turtle_x`, `screen_y = height/2 - turtle_y`

## Build

```bash
make                    # builds turtlecairo.so
make test               # runs core tests (no Cairo/SDL2 needed)
lua examples/square.lua # run from project root
```

Requires: Lua 5.4, SDL2, Cairo (all via Homebrew on macOS, apt on Linux).

## Multi-Turtle Architecture

- **Screen** owns the shared segment log, background color, and a list of registered turtles.
- **Core** (one per turtle) owns position, heading, pen state, fill state. Appends to the Screen's shared log with `turtle_id` on each entry.
- `turtle.Turtle()` creates a new Core, registers it with the Screen, returns a wrapper with method-style access (`t:forward(100)`).
- The default turtle's methods are exported as globals (`forward(100)`).
- `t:clear()` logs `{type = "clear", turtle_id = N}`. `visible_segments()` respects per-turtle clear boundaries.
- `t:reset()` resets only that turtle's state and clears only its segments.
- `bgcolor()` routes to the Screen, not to any turtle.
- Fill vertices accumulate per-turtle. `t2` drawing during `t1`'s open fill does not contaminate `t1`'s fill polygon.

## Undo Architecture

- Each core's `_push_undo()` records: turtle state snapshot + list of segment indices this command will add.
- `core:undo()` restores the state snapshot and marks those segment indices as hidden (a set, like `_cleared_stamps`).
- `visible_segments()` filters hidden segments, same as it filters cleared stamps.
- Animated undo (visual line reversal) is handled by `turtle.lua`, not core. The execution host enqueues a reverse animation before applying the state restoration.
- `clear()` and `reset()` wipe that turtle's undo stack.

## REPL Mode

REPL mode is provided by a Lua module (`turtle.repl`) backed by a small C binding (`turtle_readline.c`) that wraps GNU readline's alternate interface (`rl_callback_handler_install`, `rl_callback_read_char`). The REPL's event loop interleaves `SDL_PollEvent` with `rl_callback_read_char`. Users invoke it with `lua -e 'require("turtle.repl").start()'` — no custom interpreter. A `luaturtle` shell script wraps this invocation for convenience.

Script mode: `lua myscript.lua` — runs script, enters idle event loop via `turtle.done()`. The script mode path never touches the REPL.
REPL mode: `luaturtle` or `lua -e 'require("turtle.repl").start()'` — each line executes synchronously, window stays responsive between inputs.

## Web Version (Future, Separate Repo)

- Lua runs in a Web Worker via Wasmoon (Lua 5.4 in WASM).
- Canvas2D renders on the main thread.
- Communication via `postMessage` + `SharedArrayBuffer` + `Atomics.wait` (WebTigerPython pattern).
- User code executes synchronously in the worker. Turtle commands block the worker, main thread animates, worker resumes. Identical user experience to desktop.
- Shares: `core.lua`, `screen.lua`, `colors.lua`, test suite.
- Separate: execution host (JS), renderer (Canvas2D), editor (CodeMirror or similar).

## Testing

```bash
lua tests/test_position.lua   # from project root
lua tests/test_pen.lua
```

Core tests use `turtle/core.lua` and `turtle/screen.lua` directly. No Cairo/SDL2 dependency. Test helpers in `tests/test_helpers.lua`.

Multi-turtle tests verify: per-turtle clear, per-turtle reset, per-turtle undo with interleaving, fill isolation, bgcolor on Screen, animation sequencing (sequential per-command).

## Python Turtle API Coverage

Implemented: forward/fd, back/bk, right/rt, left/lt, circle, setpos, setx, sety, setheading/seth, home, teleport, penup/pu, pendown/pd, pensize/width, pencolor, fillcolor, color, begin_fill, end_fill, filling, dot, write, stamp, clearstamp, clearstamps, clear, reset, bgcolor, position/pos, xcor, ycor, heading, isdown, isvisible, towards, distance, showturtle/st, hideturtle/ht, speed, tracer, update, done/mainloop, bye, undo, setundobuffer, undobufferentries.

Not yet implemented: multi-turtle (`Turtle()` constructor), shape, shapesize, tilt, degrees/radians mode, setworldcoordinates, onkey/onclick/ondrag events, textinput/numinput.

## Related Documents

- **ROADMAP.md** — Ordered implementation plan. Work top-to-bottom.
- **ARCHITECTURE.md** — Detailed architecture, segment log format, execution model.
- **DECISIONS.md** — Why each major decision was made and what was rejected.
- **GOTCHAS.md** — Platform-specific issues, distribution concerns, breaking changes to expect at packaging time. **Read before any cross-platform or distribution work.**
- **REFACTOR.md** — Modularity improvements (Harper-style). Describes five refactors to tighten module interfaces: functor-style turtle.lua, explicit core accessors, decomposed visible_segments(), undo return descriptions, documented signatures. **Consult when implementing Milestones 1-4.**

## Do Not

- Suggest Raylib (replaced — no non-blocking event processing)
- Add a `Renderer` interface or adapter pattern (segment log shape is the abstraction)
- Make the core depend on any renderer or platform concept
- Put animation logic in core.lua (belongs in turtle.lua, the execution host)
- Share renderer code between desktop and web (they have different renderers by design)
- Add build steps beyond `make` (no webpack, no bundler)

# DECISIONS.md — Architecture Decision Log

This document records key decisions made during the architecture planning
phase (April 2026). Each entry captures the decision, the alternatives
considered, and why this choice was made.

---

## 1. Renderer: Cairo + SDL2

**Decision:** Replace Raylib with Cairo (drawing) + SDL2 (windowing/events).

**Alternatives considered:**
- **Raylib (status quo):** Zero external dependencies, excellent static linking
  story. BUT: no `PollEvents` function — window freezes when Lua blocks on
  input. This makes REPL mode architecturally impossible without hacks.
- **SDL2 + SDL2_gfx:** SDL2 handles windowing and events cleanly. But
  SDL2_gfx's thick lines are not anti-aliased (only 1px `aalineRGBA` is AA).
  Requires 2x supersampling hack for acceptable line quality.
- **Platform-native (CoreGraphics / Direct2D / Cairo+X11):** Best rendering
  quality per platform. But triples the windowing code — three event loops,
  three window creation paths, Objective-C required on macOS. Too much
  maintenance for one developer.
- **Cairo standalone (no SDL2):** Eliminates one dependency. But requires
  writing platform-specific windowing code for all three OSes. Same tripling
  problem as platform-native, just with shared drawing code.
- **IUP+CD (Tecgraf/PUC-Rio):** Lua heritage, good CD graphics. But limited
  modern package manager availability and smaller maintenance community.

**Why Cairo + SDL2:**
- Cairo provides native anti-aliased thick lines, alpha, filled polygons, text.
  No supersampling. Professional vector graphics quality.
- SDL2 provides cross-platform windowing with `SDL_PollEvent` (REPL support).
- Mirrors the web architecture: SDL2↔Browser, Cairo↔Canvas2D.
- Both well-packaged on macOS/Linux/Windows.

---

## 2. Execution model: Synchronous core, platform-specific host

**Decision:** The core (`core.lua`) is always synchronous — `forward(100)`
updates state and appends to the segment log immediately. Animation timing,
rendering triggers, and event pumping are the execution host's responsibility.

**Why:** This allows the same core to work on desktop (synchronous + sleep)
and web (synchronous in Web Worker + `Atomics.wait`). The core doesn't
know whether it's being driven by `turtle.lua` on desktop or by a Web Worker
execution host. The segment log is the interface.

---

## 3. Multi-turtle: Shared segment log with turtle IDs

**Decision:** All turtles append to one shared segment log. Each entry carries
a `turtle_id` field. A `screen.lua` module owns the shared log and turtle
registry.

**Alternatives considered:**
- **Per-turtle segment logs:** Each turtle owns its own log. Simpler per-turtle
  operations, but the renderer must merge logs to draw in correct z-order.
  Per-turtle clear is trivial but cross-turtle z-ordering is lost.

**Why shared log:** Preserves draw order (z-ordering). Per-turtle clear works
via `{type="clear", turtle_id=N}` markers in the log. `visible_segments()`
handles filtering. The renderer replays one log — simple.

---

## 4. Undo: Index marking, not log truncation

**Decision:** Undo marks segment indices as hidden rather than truncating the
shared log. Each turtle's undo stack records which indices it added.

**Why:** With a shared log, truncating on undo would remove other turtles'
segments that were interleaved. Marking indices as hidden is surgically
per-turtle. `visible_segments()` filters hidden indices, same mechanism as
cleared stamps. Verified that this matches Python turtle's per-turtle undo
behavior.

---

## 5. Animated undo: Execution host concern

**Decision:** Animated undo (visual line reversal) is handled by `turtle.lua`,
not by `core.lua`. The core's `undo()` does the state restoration. The
execution host enqueues a reverse animation before calling `core:undo()`.

**Why:** Animation is an execution host concern everywhere else (animated
forward, animated turn). Undo animation follows the same pattern. The core
remains a pure state machine.

---

## 6. REPL: Lua module with readline callback interface

**Decision:** Ship the REPL as a Lua module (`turtle.repl`) backed by a
small C binding (`turtle_readline.c`) that wraps GNU readline's alternate
(callback) interface. An event loop interleaves `SDL_PollEvent` with
`rl_callback_read_char`.

**Alternatives considered:**
- **Custom Lua interpreter (fork `lua.c`):** Modify the standard
  interpreter's input loop to pump `SDL_PollEvent` between characters.
  No readline dependency. BUT: requires tracking Lua 5.4 patch releases,
  distribution requires a custom binary instead of a module, REPL becomes
  a binary artifact rather than a library feature. Forks the standard
  Lua interpreter — a commitment we don't want to make for what is
  fundamentally a library.
- **debug.sethook:** Fires between Lua instructions, but NOT while blocked
  on `fgets` (waiting for terminal input). Window freezes at the prompt.
- **Background thread for window:** Move SDL2 to a dedicated thread. Clean
  but adds thread synchronization complexity. Also blocked by macOS's
  main-thread requirement for UI.

**Why readline callback interface:**
- Doesn't fork the standard Lua interpreter — works with any Lua 5.4 host.
- REPL is a library feature, not a binary artifact. Distribution is
  standard `lua` + our `.so` + our `.lua` files.
- Cleaner modular story: `turtle.repl` is the desktop execution host;
  on web, the CodeMirror `onSubmit` handler is the execution host. Both
  route through `load(source)` → `pcall(chunk)` → render. The symmetry
  is real instead of aspirational.
- readline is nearly universal on macOS/Linux. Windows needs a separate
  decision (WinEditLine/libedit drop-in vs. `#ifdef` to Windows console
  API) — deferred, see GOTCHAS.md.

---

## 7. Web version: Separate repo, shared core

**Decision:** The web version will be a separate repository. It shares
`core.lua`, `screen.lua`, `colors.lua`, and the test suite. It has its own
execution host (JS + Web Worker) and renderer (Canvas2D).

**Why:** Desktop and web have genuinely different execution hosts and
renderers. Forcing them into one repo would create artificial coupling.
The segment log shape and the Lua API surface are the contracts. Good tests
are the bridge, not shared runtime code.

---

## 8. Web execution: WebTigerPython pattern

**Decision:** The web version will run Lua in a Web Worker via Wasmoon.
Turtle commands block the worker via `SharedArrayBuffer` + `Atomics.wait`.
The main thread renders with Canvas2D and notifies via `Atomics.notify`.

**Why:** This gives the web version the same synchronous user experience as
desktop. `forward(100)` blocks the worker until animation finishes, then
returns. User code reads top-to-bottom, no callbacks, no promises.
WebTigerPython proved this approach works in production with 800+ daily users.

---

## 9. No Renderer interface/abstraction

**Decision:** No `Renderer` interface, no adapter pattern, no factory.
`turtlecairo.c` knows it uses Cairo. `renderer.js` (web) knows it uses
Canvas2D. The segment log shape is the abstraction.

**Why:** The segment log already defines what the renderer must draw: lines,
fills, dots, text, stamps, turtle heads. Any renderer that can draw these
shapes from the log data satisfies the contract. Adding a formal `Renderer`
interface on top would be abstraction for abstraction's sake. Per Koppel's
principles: the design is already embedded in the data structure.

---

## 10. Python turtle API as specification

**Decision:** Track Python turtle's API for the core ~30 commands. Match
behavior exactly, verified by running equivalent test scripts against
CPython's turtle module.

**Why:** Python turtle is battle-tested by millions of students. Matching it
gives free mental-model transfer for students and teachers. Multi-turtle
behavior (animation interleaving, per-turtle clear/reset/undo, fill isolation,
bgcolor ownership, tracer/update pattern) was validated against Python before
any implementation decisions were made.

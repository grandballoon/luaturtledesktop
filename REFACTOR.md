# REFACTOR.md — Modularity Improvements

This document describes structural refactors to improve the modularity of
the codebase, inspired by Bob Harper's "Modules Matter Most" principle.
These are not rewrites — they're tightening of existing interfaces.

Harper's central insight: modularity has two halves. The well-known half is
"multiple implementations of one interface" (Cairo and Canvas2D both consume
the segment log). The neglected half is "multiple interfaces to one
implementation" (a module can be viewed through different signatures that
reveal different subsets of its capabilities).

In Lua, we can't enforce signatures with a type system. But we can design
as if we could: define explicit public interfaces, use accessor functions
instead of direct field access, and parameterize modules instead of
hardwiring dependencies.

---

## Refactor 1: Make turtle.lua a functor

### Problem

turtle.lua directly `require`s core, screen, renderer, and colors. This
means you can't substitute a test renderer or a different screen without
modifying turtle.lua or monkey-patching `require`.

### Current

```lua
-- turtle.lua (hardwired)
local Core = require("turtle.core")
local Renderer = require("turtle.renderer")
local core = Core.new()
local renderer = Renderer.new({ title = script_title() })
```

### Refactored

```lua
-- turtle.lua becomes a function from dependencies to API
local function make_turtle(screen, renderer)
    local core = Core.new(screen)
    -- all turtle API functions close over screen, core, renderer
    local turtle = {}
    turtle.forward = function(dist) ... end
    -- ...
    return turtle
end
return make_turtle
```

The entry point (luaturtle binary or init script) wires concrete modules:

```lua
local Screen = require("turtle.screen")
local Renderer = require("turtle.renderer")
local make_turtle = require("turtle")

local screen = Screen.new()
local renderer = Renderer.new({ title = "Lua Turtle", screen = screen })
local turtle = make_turtle(screen, renderer)

-- Export globals
for name, fn in pairs(turtle) do
    if type(fn) == "function" then _G[name] = fn end
end
```

### Why

- Tests can pass a stub renderer and real screen, or vice versa.
- The dependency graph becomes explicit in code, not hidden in `require`.
- A second entry point (web execution host) can wire different modules
  without changing turtle.lua.

### When

During Milestone 1 (multi-turtle refactor) or Milestone 2 (renderer swap).
Either is a natural point to make this change.

---

## Refactor 2: Explicit public interfaces on core

### Problem

renderer.lua reads core internal fields directly: `core.x`, `core.y`,
`core.angle`, `core.pen_color`, `core.visible`, `core.fill_color`. This
couples the renderer to core's internal representation. If core changes
how it stores position (e.g., to a table `{x, y}`), renderer breaks.

### Current

```lua
-- renderer.lua reaches into core internals
if self.core.visible then
    self:_draw_turtle_shape(
        self.core.x, self.core.y, self.core.angle,
        self.core.pen_color, self.core.fill_color
    )
end
```

### Refactored

```lua
-- core.lua exposes a public accessor
function Core:get_head_state()
    return {
        x = self.x,
        y = self.y,
        angle = self.angle,
        visible = self.visible,
        pen_color = {table.unpack(self.pen_color)},
        fill_color = {table.unpack(self.fill_color)},
        pen_size = self.pen_size,
    }
end
```

```lua
-- renderer.lua uses the accessor
for _, core in ipairs(screen.turtles) do
    local head = core:get_head_state()
    if head.visible then
        self:_draw_turtle_shape(
            head.x, head.y, head.angle,
            head.pen_color, head.fill_color, head.pen_size
        )
    end
end
```

### Why

- The renderer depends on a documented return shape, not on core internals.
- Core can change internal representation without breaking renderer.
- The web version's core already has `get_turtle_state()` — this unifies
  the desktop and web interfaces.

### When

During Milestone 2 (renderer swap). When writing the new renderer.lua
against Cairo, use accessors from the start instead of carrying forward
the direct field access.

---

## Refactor 3: Decompose visible_segments()

### Problem

`visible_segments()` in screen.lua will filter for three independent
concerns: per-turtle clear boundaries, cleared stamps, and undo-hidden
indices. Combining three filtering mechanisms in one function makes it
hard to test each independently and hard to add a fourth concern later.

### Current (planned)

```lua
function Screen:visible_segments()
    -- find per-turtle clear boundaries
    -- filter cleared stamps
    -- filter undo-hidden indices
    -- return results
end
```

### Refactored

```lua
-- Each filter: segment list → segment list
-- Each is independently testable

function Screen:_segments_after_clears()
    -- For each turtle, find its most recent clear entry.
    -- Return segments after each turtle's clear boundary.
    -- Other turtles' segments before this turtle's clear are kept.
end

function Screen:_filter_cleared_stamps(segments)
    -- Remove segments where type=="stamp" and id is in _cleared_stamps
end

function Screen:_filter_undo_hidden(segments)
    -- Remove segments whose index is in any turtle's _hidden_indices set
end

function Screen:visible_segments()
    local segs = self:_segments_after_clears()
    segs = self:_filter_cleared_stamps(segs)
    segs = self:_filter_undo_hidden(segs)
    return segs
end
```

### Why

- Each filter can be tested independently with a known input list.
- Adding a fourth filter (e.g., layer visibility) is a one-line change.
- The composed pipeline is `visible_segments()` — same public interface.
- Bugs in one filter don't obscure the others during debugging.

### When

During Milestone 1.2 (per-turtle clear) and 1.3 (per-turtle undo).
Build the filters incrementally as each feature is added.

---

## Refactor 4: Undo returns a description

### Problem

turtle.lua needs to know what kind of segment was undone to animate the
reversal (retrace a line, reverse a turn, etc.). Currently, turtle.lua
would have to inspect the segment log to figure out what was hidden.
This creates an implicit contract between core's undo internals and
turtle.lua's animation logic.

### Current (implicit)

```lua
-- turtle.lua guesses what was undone by inspecting segments
function turtle.undo()
    -- look at segments about to be hidden...
    -- determine animation type...
    core:undo()
    -- animate reversal...
end
```

### Refactored (explicit)

```lua
-- core:undo() returns a description of what was undone
function Core:undo()
    if #self._undo_stack == 0 then return nil end
    local snap = table.remove(self._undo_stack)

    -- Collect the segments being hidden for the undo description
    local undone_segments = {}
    for _, idx in ipairs(snap.segment_indices) do
        table.insert(undone_segments, self.screen.segments[idx])
    end

    -- Restore state and mark segments hidden
    -- ... (existing restoration logic) ...

    -- Return description for animated undo
    return {
        segments = undone_segments,
        previous_state = {
            x = snap.x,
            y = snap.y,
            angle = snap.angle,
        }
    }
end
```

```lua
-- turtle.lua consumes the description
function turtle.undo()
    local description = core:undo()
    if not description then return end

    -- Animate reversal based on description
    for i = #description.segments, 1, -1 do
        local seg = description.segments[i]
        if seg.type == "line" then
            animate_reverse_line(seg)
        elseif seg.type == "turn" then
            -- turns don't have segments, handled by state diff
        end
    end

    renderer:request_full_redraw()
    renderer:render()
end
```

### Why

- The contract is explicit: `undo()` returns a value of a known shape.
- turtle.lua doesn't need to understand undo internals.
- If undo's internal representation changes, the description acts as a
  stable interface between core and execution host.

### When

During Milestone 4 (animated undo). Design the return shape before
implementing the animation.

---

## Refactor 5: Document internal module signatures

### Problem

Lua can't enforce module interfaces. The "signatures" exist only in the
developer's head and in scattered comments. When a new developer (or
Claude Code) works on the code, they don't know which fields/methods are
public interface vs. internal implementation.

### Solution

Add a `SIGNATURES.md` or a comment block at the top of each module
listing its public interface explicitly:

```lua
-- turtle/core.lua
--
-- PUBLIC INTERFACE (stable, used by other modules):
--
--   Core.new(screen) → core instance
--
--   Movement:    core:forward(dist), core:back(dist),
--                core:right(angle), core:left(angle),
--                core:circle(radius, extent, steps)
--   Absolute:    core:setpos(x,y), core:setx(x), core:sety(y),
--                core:setheading(angle), core:home(), core:teleport(x,y)
--   Pen:         core:penup(), core:pendown(), core:pensize(w),
--                core:pencolor(...), core:fillcolor(...), core:color(...)
--   Fill:        core:begin_fill(), core:end_fill(), core:is_filling()
--   Drawing:     core:dot(...), core:write(...), core:stamp(),
--                core:clearstamp(id), core:clearstamps(n)
--   Canvas:      core:clear(), core:reset()
--   Queries:     core:position(), core:heading(), core:isdown(),
--                core:isvisible(), core:towards(x,y), core:distance(x,y),
--                core:xcor(), core:ycor(), core:speed(n)
--   Visibility:  core:showturtle(), core:hideturtle()
--   Undo:        core:_push_undo(), core:undo() → description|nil,
--                core:setundobuffer(n), core:undobufferentries()
--   Head state:  core:get_head_state() → {x, y, angle, visible, ...}
--
-- INTERNAL (do not use from other modules):
--
--   self.x, self.y, self.angle — use queries or get_head_state()
--   self.pen_color, self.fill_color — use pencolor()/fillcolor()
--   self._undo_stack — use undo API
--   self._hidden_indices — internal to undo system
--   self.filling, self.fill_vertices — internal to fill system
```

### Why

- Acts as a substitute for ML signatures in a dynamically typed language.
- Claude Code can distinguish public API from internals.
- Makes it obvious when a change crosses a module boundary.

### When

During Milestone 1. Add the interface comment blocks when creating
screen.lua and refactoring core.lua.

---

## Summary: Dependency Direction After Refactors

```
turtle.lua (execution host)
    RECEIVES: screen, renderer (as parameters — Refactor 1)
    CALLS: core public API, screen public API, renderer public API
    READS: undo descriptions (Refactor 4)

screen.lua (shared state)
    RECEIVES: nothing (standalone)
    EXPOSES: segment log, visible_segments() (Refactor 3), turtle registry
    DOES NOT DEPEND ON: core, renderer, turtle

core.lua (per-turtle state)
    RECEIVES: screen reference (for segment log)
    EXPOSES: public movement/pen/query API, get_head_state() (Refactor 2),
             undo() returning description (Refactor 4)
    DEPENDS ON: screen (append to segment log), colors (name lookup)
    DOES NOT DEPEND ON: renderer, turtle

renderer.lua
    RECEIVES: screen reference
    CALLS: screen:visible_segments(), core:get_head_state() (Refactor 2),
           turtlecairo.c functions
    DOES NOT DEPEND ON: turtle.lua, core internals

colors.lua (pure data)
    DEPENDS ON: nothing
```

All dependency arrows point downward. No cycles. turtle.lua is the only
module that depends on everything, and it does so through explicit
parameterization (Refactor 1), not hardwired requires.

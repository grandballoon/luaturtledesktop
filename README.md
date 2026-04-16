# Lua Turtle (Desktop)

A desktop turtle graphics library for Lua 5.4, inspired by Python's `turtle` module and Seymour Papert's *Mindstorms*.

Students write normal Lua scripts. A graphics window appears.

```lua
require("turtle")

speed(3)
for i = 1, 6 do
    forward(100)
    right(60)
end

done()
```

---

## Install

### macOS

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/grandballoon/luaturtledesktop/main/install.sh)"
```

Then reload your shell (`source ~/.zshrc` or open a new terminal).

<details>
<summary>What the script does</summary>

1. `brew install lua luarocks sdl2 cairo readline`
2. `luarocks install luaturtle` with Homebrew path hints
3. Adds `eval "$(luarocks path)"` to `~/.zshrc` (or `~/.bash_profile`) so
   installed rocks are findable by Lua

</details>

### Linux

```sh
sudo apt install lua5.4 libsdl2-dev libcairo2-dev libreadline-dev
luarocks install luaturtle
```

For Fedora/RHEL: replace `apt install` with `dnf install lua lua-devel SDL2-devel cairo-devel readline-devel`.

### Windows

Not yet supported. GNU readline on native Windows is an open problem
(see `GOTCHAS.md`). Tracked for a future release.

---

## Running

**Script mode** — run a script, window stays open until you close it:

```sh
lua myscript.lua
```

**REPL mode** — interactive window, type commands one at a time:

```sh
luaturtle
```

```
> forward(100)
> right(90)
> pencolor("red", 0.8)
> forward(100)
> exit
```

The `luaturtle` script is equivalent to:

```sh
lua -e 'require("turtle.repl").start()'
```

---

## API

Mirrors Python's `turtle` module. All commands are available as globals after
`require("turtle")`.

### Movement

| Command | Description |
|---------|-------------|
| `forward(n)` / `fd(n)` | Move forward `n` pixels |
| `back(n)` / `bk(n)` | Move backward `n` pixels |
| `right(deg)` / `rt(deg)` | Turn right |
| `left(deg)` / `lt(deg)` | Turn left |
| `circle(r)` / `circle(r, extent)` | Draw arc of radius `r` |
| `setpos(x, y)` | Jump to position (pen state respected) |
| `setx(x)` / `sety(y)` | Set one coordinate |
| `setheading(deg)` / `seth(deg)` | Set absolute heading |
| `home()` | Return to origin, heading east |
| `teleport(x, y)` | Jump without drawing (ignores pen state) |

### Pen

| Command | Description |
|---------|-------------|
| `penup()` / `pu()` | Lift pen |
| `pendown()` / `pd()` | Lower pen |
| `pensize(n)` / `width(n)` | Set line width |
| `pencolor(c)` / `pencolor(r,g,b)` | Set pen color |
| `pencolor("name", alpha)` | Named color with optional alpha (0–1) |
| `fillcolor(...)` | Set fill color (same syntax as pencolor) |
| `color(pen, fill)` | Set both at once |

### Fill

```lua
begin_fill()
for i = 1, 4 do forward(100); right(90) end
end_fill()
```

### Drawing extras

| Command | Description |
|---------|-------------|
| `dot(size)` / `dot(size, color)` | Draw a dot |
| `write(text)` | Write text at current position |
| `stamp()` | Stamp turtle shape onto canvas; returns id |
| `clearstamp(id)` | Remove a specific stamp |
| `clearstamps(n)` | Remove oldest `n` stamps (or all if `n` omitted) |

### Canvas

| Command | Description |
|---------|-------------|
| `clear()` | Erase this turtle's drawing, keep position |
| `reset()` | Erase and return to origin with defaults |
| `bgcolor(c)` / `bgcolor(r,g,b)` | Set background color |
| `undo()` | Undo last command (animated) |

### Visibility

```lua
hideturtle()  -- ht()
showturtle()  -- st()
```

### Speed

```lua
speed(0)   -- instant (no animation)
speed(1)   -- slowest
speed(10)  -- fastest (default: 5)
```

### Queries

```lua
position()    -- returns x, y
xcor()        -- returns x
ycor()        -- returns y
heading()     -- returns angle in degrees
isdown()      -- pen state
isvisible()
towards(x, y) -- heading toward point
distance(x, y)
```

### Multi-turtle

```lua
require("turtle")

t1 = turtle.Turtle()
t2 = turtle.Turtle()

t1:pencolor("red")
t2:pencolor("blue")

tracer(0)
for i = 1, 180 do
    t1:forward(2); t1:left(2)
    t2:forward(2); t2:right(2)
    update()
end
done()
```

### Colors

All color commands accept:

- Named string: `pencolor("red")`, `pencolor("dodgerblue")`
- Named string + alpha: `pencolor("red", 0.5)`
- RGB floats (0–1): `pencolor(1, 0, 0)`
- RGBA floats: `pencolor(1, 0, 0, 0.5)`
- RGB integers (0–255): `pencolor(255, 0, 0)`
- Table: `pencolor({1, 0, 0, 0.5})`

140+ CSS/SVG named colors are supported (`turtle/colors.lua`).

---

## Architecture

```
[User code] → [turtle.lua (execution host)] → [Core (state machine)] → [Segment log]
                                                                              ↓
                                                               [Renderer reads log, draws]
```

- **`turtle.lua`** — Entry point. Animation timing, undo, REPL integration. Exports API as globals.
- **`turtle/screen.lua`** — Shared state: segment log, background color, turtle registry.
- **`turtle/core.lua`** — Per-turtle state machine. No rendering dependencies; testable with plain Lua.
- **`turtlecairo.c`** — C binding: Cairo drawing + SDL2 windowing. Anti-aliased lines, alpha, fills, text.
- **`turtle_readline.c`** — C binding: GNU readline callback interface for REPL mode.
- **`turtle/repl.lua`** — REPL event loop (~100 Hz, interleaves SDL2 events with readline input).
- **`turtle/colors.lua`** — 140+ CSS/SVG named colors.

### Why Cairo + SDL2

Cairo provides anti-aliased thick lines, alpha compositing, filled polygons, and text rendering from a C API — no supersampling hacks. SDL2 provides cross-platform windowing and non-blocking event processing (`SDL_PollEvent`), which is required for REPL mode.

### Coordinate system

- Origin at center (0, 0)
- Y-up (positive y goes up)
- Angles in degrees, 0° = east, counter-clockwise positive

---

## Development

```sh
make        # build turtlecairo.so and turtle_readline.so
make test   # run core tests (no window needed)
make square # run the square example
make repl   # launch REPL
```

Tests use `turtle/core.lua` and `turtle/screen.lua` directly — no Cairo/SDL2 required. Run them freely.

---

## License

MIT — see `LICENSE`.

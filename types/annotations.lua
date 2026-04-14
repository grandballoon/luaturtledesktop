-- turtle/annotations.lua
-- LuaLS (sumneko) type stubs for VS Code autocomplete.
-- NOT loaded at runtime. Place in your workspace or configure LuaLS
-- to find it via settings.json: "Lua.workspace.library": ["path/to/this"]

---@meta

---@class turtle
local turtle = {}

-- Movement -----------------------------------------------------------

---Move the turtle forward by distance pixels in the direction it is heading.
---If the pen is down, draws a line.
---@param distance number
function forward(distance) end
fd = forward

---Move the turtle backward by distance pixels (opposite to heading).
---@param distance number
function back(distance) end
bk = back
backward = back

---Turn the turtle clockwise by angle degrees.
---@param angle number
function right(angle) end
rt = right

---Turn the turtle counter-clockwise by angle degrees.
---@param angle number
function left(angle) end
lt = left

---Draw a circle (or arc). Center is radius units to the LEFT of the turtle.
---Positive radius = CCW. extent = degrees of arc (default 360).
---steps = number of polygon segments (auto-calculated if nil).
---@param radius number
---@param extent? number
---@param steps? integer
function circle(radius, extent, steps) end

-- Absolute positioning -----------------------------------------------

---Move turtle to absolute position (x, y). Draws if pen is down.
---@param x number|table
---@param y? number
function setpos(x, y) end
setposition = setpos

---Set the turtle's x coordinate, leaving y unchanged.
---@param x number
function setx(x) end

---Set the turtle's y coordinate, leaving x unchanged.
---@param y number
function sety(y) end

---Set the turtle's heading to angle degrees. 0=east, 90=north.
---@param angle number
function setheading(angle) end
seth = setheading

---Move turtle to origin (0, 0) and set heading to 0.
function home() end

---Move turtle to (x, y) without drawing, regardless of pen state.
---@param x number|table
---@param y? number
function teleport(x, y) end

-- Pen control ---------------------------------------------------------

---Lift the pen. Subsequent movement will not draw.
function penup() end
pu = penup
up = penup

---Lower the pen. Subsequent movement will draw.
function pendown() end
pd = pendown
down = pendown

---Set or return the pen width.
---@param width? number
---@return number
function pensize(width) end
width = pensize

---Set or return the pen color. Accepts (r,g,b), (r,g,b,a), or a color name string.
---@param r? number|string
---@param g? number
---@param b? number
---@param a? number
function pencolor(r, g, b, a) end

---Set or return the fill color.
---@param r? number|string
---@param g? number
---@param b? number
---@param a? number
function fillcolor(r, g, b, a) end

---Set pen color and optionally fill color.
---@param pen? string|table
---@param fill? string|table
function color(pen, fill) end

-- Filling -------------------------------------------------------------

---Start recording vertices for a filled polygon.
function begin_fill() end

---Fill the polygon defined by vertices since begin_fill().
function end_fill() end

---Return true if currently recording fill vertices.
---@return boolean
function filling() end

-- Drawing extras ------------------------------------------------------

---Draw a circular dot at the current position.
---@param size? number
---@param r? number|string
---@param g? number
---@param b? number
---@param a? number
function dot(size, r, g, b, a) end

---Write text at the current turtle position.
---@param text any
---@param move? boolean
---@param align? string  "left", "center", or "right"
---@param font? table    {family, size, style}
function write(text, move, align, font) end

---Stamp the turtle shape at the current position. Returns a stamp ID.
---@return integer
function stamp() end

---Remove the stamp with the given ID.
---@param stamp_id integer
function clearstamp(stamp_id) end

---Clear first n stamps (positive), last n (negative), or all (nil).
---@param n? integer
function clearstamps(n) end

-- Canvas --------------------------------------------------------------

---Clear all drawing. Turtle position and state are preserved.
function clear() end

---Clear all drawing and reset turtle to center with default state.
function reset() end

---Set or return the background color.
---@param r? number|string
---@param g? number
---@param b? number
---@param a? number
function bgcolor(r, g, b, a) end

-- State queries -------------------------------------------------------

---Return the turtle's (x, y) position.
---@return number x, number y
function position() end
pos = position

---Return the turtle's x coordinate.
---@return number
function xcor() end

---Return the turtle's y coordinate.
---@return number
function ycor() end

---Return the turtle's heading in degrees.
---@return number
function heading() end

---Return true if the pen is down.
---@return boolean
function isdown() end

---Return true if the turtle is visible.
---@return boolean
function isvisible() end

---Return the angle toward the point (x, y) from the turtle.
---@param x number|table
---@param y? number
---@return number
function towards(x, y) end

---Return the distance from the turtle to the point (x, y).
---@param x number|table
---@param y? number
---@return number
function distance(x, y) end

-- Visibility ----------------------------------------------------------

---Show the turtle.
function showturtle() end
st = showturtle

---Hide the turtle.
function hideturtle() end
ht = hideturtle

-- Speed / Animation ---------------------------------------------------

---Set or return the animation speed. 0=instant, 1=slowest, 10=fastest.
---@param n? integer
---@return integer|nil
function speed(n) end

---Control screen update tracing. tracer(0) disables animation.
---@param n? integer
---@param delay? integer
function tracer(n, delay) end

---Force a screen update (used after tracer(0) batch drawing).
function update() end

-- Undo ---------------------------------------------------------------

---Undo the last turtle action. Can be called repeatedly.
function undo() end

---Set the maximum number of undoable actions (nil = unlimited).
---@param n? integer
function setundobuffer(n) end

---Return the number of available undo steps.
---@return integer
function undobufferentries() end

-- Event loop ----------------------------------------------------------

---Enter the main event loop. Keeps the window open until closed.
function done() end
mainloop = done

---Close the turtle graphics window.
function bye() end

return turtle

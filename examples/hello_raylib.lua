-- examples/hello_raylib.lua
-- Minimal test: open a window, draw some shapes, keep it open.
-- Run this FIRST to verify turtleray.so is built and working.
--
-- Expected: a window with a red line, green text, blue circle on black.
-- Close the window or press ESC to exit.
--
-- Usage: lua5.4 examples/hello_raylib.lua
--   (run from the project root, where turtleray.so is)

local ray = require("turtleray")

ray.init_window(800, 600, "Raylib + Lua — Hello World")

while not ray.window_should_close() do
    ray.begin_drawing()
    ray.clear(0, 0, 0, 255)

    -- Red line
    ray.draw_line(50, 550, 750, 50, 255, 0, 0, 255, 3.0)

    -- Green text
    ray.draw_text("Raylib + Lua works! Press ESC or close window to exit.", 50, 20, 20, 0, 255, 0, 255)

    -- Blue circle outline
    ray.draw_circle_lines(400, 300, 80, 0, 100, 255, 255)

    -- Yellow filled triangle
    ray.draw_triangle_fill(
        400, 200,
        350, 350,
        450, 350,
        255, 220, 0, 255
    )

    -- Semi-transparent white circle (tests alpha)
    ray.draw_circle(400, 300, 40, 255, 255, 255, 100)

    ray.end_drawing()
end

ray.close_window()
print("Done.")

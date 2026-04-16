-- turtle/repl.lua
-- Non-blocking REPL event loop.
-- Interleaves SDL2 event processing (via renderer:render) with GNU readline
-- input so the graphics window stays responsive while the user types.
--
-- Usage:
--   lua -e 'require("turtle.repl").start()'
-- Or via the luaturtle shell script.
--
-- Loop structure (runs at ~100 Hz with a 10 ms stdin timeout):
--   1. render()        — pump SDL2 events, redraw frame
--   2. stdin_has_input — check whether a character is waiting (non-blocking)
--   3. read_char()     — feed one char to readline's state machine
--   4. execute line    — if readline assembled a complete line, run it

local readline = require("turtle_readline")
local turtle   = require("turtle")

local function start()
    local current_line = nil

    readline.install_handler("> ", function(line)
        current_line = line
    end)

    while true do
        -- Pump SDL2 events and re-render the frame.
        -- renderer:render() calls os.exit(0) internally if the window is
        -- closed, so the window_should_close() check below is a belt-and-
        -- suspenders safety net for any future refactoring.
        turtle._renderer:render()
        if turtle._renderer:window_should_close() then break end

        -- Sleep up to 10 ms waiting for stdin input. This keeps the loop
        -- running at roughly 100 Hz without busy-spinning the CPU when the
        -- user is idle.
        if readline.stdin_has_input(10) then
            readline.read_char()
        end

        -- If readline assembled a complete line, execute it.
        if current_line then
            local line = current_line
            current_line = nil

            if line == "exit" or line == "quit" then break end

            -- Add to history only for non-empty, non-duplicate lines.
            readline.add_history(line)

            -- Try to compile as a statement first.
            local chunk, err = load(line, "=(repl)", "t", _ENV)
            if not chunk then
                -- Fall back to expression form (like the standard Lua REPL
                -- does when the line starts with '=', but automatic here).
                chunk, err = load("return " .. line, "=(repl)", "t", _ENV)
            end

            if chunk then
                local ok, result = pcall(chunk)
                if ok and result ~= nil then
                    print(result)
                elseif not ok then
                    print("error: " .. tostring(result))
                end
            else
                print("syntax error: " .. tostring(err))
            end
        end
    end

    readline.remove_handler()
end

return { start = start }

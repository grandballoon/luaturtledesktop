MILESTONE_3.md — REPL as Lua module (Solution B)
Supersedes the current Milestone 3 in ROADMAP.md. The REPL is no longer a
forked lua.c. It is a Lua module (turtle.repl) backed by a small C
binding (turtle_readline.c) that wraps GNU readline's alternate
(callback) interface. An event loop interleaves SDL_PollEvent with
rl_callback_read_char.
Distribution (M6) decision made: LuaRocks only for now. No bundled
interpreter. Users install Lua 5.4 + readline themselves and
luarocks install luaturtle. Bundled-binary distribution stays open as a
future option.
Windows readline decision: deferred. LuaRocks-only distribution means
Windows support is not blocking M3. Document as an open question in
GOTCHAS.md; decide before a Windows release.

Part 1 — New Milestone 3 spec
3.1 Write turtle_readline.c
Minimal C binding exposing readline's alternate interface to Lua. ~150 lines
of C plus -lreadline in the Makefile.
API:

readline.install_handler(prompt, callback) — wraps
rl_callback_handler_install. The callback is a Lua function that
receives a complete line when readline has one. Stash the Lua function
across C boundaries using the registry (luaL_ref).
readline.read_char() — wraps rl_callback_read_char. Reads one
character of input, dispatches to readline's internal state machine,
and only invokes your callback when a full line is ready. Gate this
with stdin_has_input from the Lua side to make it non-blocking at the
loop level.
readline.stdin_has_input(timeout_ms) — wraps select() on fd 0 with
a short timeout, so the event loop can sleep a few milliseconds between
SDL_PollEvent cycles without burning CPU.
readline.remove_handler() — wraps rl_callback_handler_remove for
cleanup.
readline.add_history(line) — wraps add_history so up-arrow recall
works.

Gotcha: readline's state is global (rl_instream, rl_outstream,
internal buffers). Fine for a single-REPL tool, but turtle_readline is
not reentrant — do not try to run two REPLs simultaneously.
3.2 Write turtle/repl.lua
REPL event loop in Lua. Structure: render → check input → execute.
Render happens every iteration (roughly 100 Hz with the 10ms stdin timeout),
so the window stays responsive regardless of whether the user is typing,
thinking, or has walked away from the keyboard.
lualocal readline = require("turtle_readline")
local turtle   = require("turtle")

local function start()
    local current_line = nil

    readline.install_handler("> ", function(line)
        current_line = line
    end)

    while true do
        -- Pump SDL2 events and re-render
        turtle._renderer:render()
        if turtle._renderer:window_should_close() then break end

        -- Check for stdin input (with ~10ms timeout to avoid CPU burn)
        if readline.stdin_has_input(10) then
            readline.read_char()
        end

        -- If a full line arrived, execute it
        if current_line then
            local line = current_line
            current_line = nil
            if line == "exit" or line == "quit" then break end

            readline.add_history(line)
            local chunk, err = load(line, "=(repl)", "t", _ENV)
            if not chunk then
                -- Try as expression (like standard Lua REPL does with '=')
                chunk, err = load("return " .. line, "=(repl)", "t", _ENV)
            end
            if chunk then
                local ok, result = pcall(chunk)
                if ok and result ~= nil then print(result)
                elseif not ok then print("error: " .. tostring(result)) end
            else
                print("syntax error: " .. tostring(err))
            end
        end
    end

    readline.remove_handler()
end

return { start = start }
3.3 Script mode continues to work unchanged
lua myscript.lua calls require("turtle"), the script runs,
turtle.done() enters the renderer's mainloop. No changes needed — this
path never touched the REPL.
3.4 Entry point
The canonical invocation is:
lua -e 'require("turtle.repl").start()'
For convenience, ship a trivial shell script luaturtle:
sh#!/bin/sh
exec lua -e 'require("turtle.repl").start()' "$@"
Three lines of shell instead of a forked interpreter.
Acceptance test

Launch the REPL (luaturtle or lua -e 'require("turtle.repl").start()').
Type forward(100) — window appears, turtle draws.
Type right(90).
Type forward(100).
Drag the window to resize — redraw happens smoothly during drag.
Press up arrow — previous line appears for editing.
Type exit — REPL terminates, window closes.
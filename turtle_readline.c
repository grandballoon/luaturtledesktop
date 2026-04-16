/*
 * turtle_readline.c
 * Minimal Lua 5.4 binding for GNU readline's alternate (callback) interface.
 * Exposes five functions so turtle/repl.lua can build a non-blocking REPL that
 * interleaves SDL2 event processing with terminal input.
 *
 * API exposed to Lua:
 *   readline.install_handler(prompt, callback)
 *       Wraps rl_callback_handler_install(). The callback is a Lua function
 *       that receives one string argument (the completed line) when readline
 *       has assembled a full line. The Lua function is pinned in the registry
 *       so it is not collected across C boundaries.
 *
 *   readline.read_char()
 *       Wraps rl_callback_read_char(). Reads one character from stdin and
 *       feeds it into readline's internal state machine. Only invokes the
 *       installed callback when a complete line is available. Must be called
 *       only after stdin_has_input() returns true so the call is non-blocking
 *       at the event-loop level.
 *
 *   readline.stdin_has_input(timeout_ms) -> boolean
 *       Wraps select() on fd 0 (stdin) with the given timeout in milliseconds.
 *       Returns true if at least one character is available to read. Used to
 *       sleep the REPL loop for ~10 ms between SDL_PollEvent cycles without
 *       burning CPU.
 *
 *   readline.remove_handler()
 *       Wraps rl_callback_handler_remove(). Releases the readline callback
 *       state and unpins the Lua callback from the registry. Call on exit.
 *
 *   readline.add_history(line)
 *       Wraps add_history(). Appends a non-empty line to readline's history
 *       so up-arrow recall works.
 *
 * Gotcha: readline's state (rl_instream, rl_outstream, internal line buffer)
 * is global. turtle_readline is NOT reentrant — do not install two handlers
 * simultaneously.
 *
 * Build:
 *   cc -shared -fPIC -o turtle_readline.so turtle_readline.c \
 *      -I/opt/homebrew/include/lua5.4 -lreadline \
 *      -undefined dynamic_lookup   # macOS only
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <readline/readline.h>
#include <readline/history.h>

#include <sys/select.h>
#include <stdlib.h>
#include <string.h>

/* ----------------------------------------------------------------
 * Global state
 * readline's callback interface does not support user-data pointers,
 * so we must stash the Lua state and registry reference globally.
 * Fine for a single-REPL tool.
 * ---------------------------------------------------------------- */

static lua_State *g_L            = NULL;
static int        g_callback_ref = LUA_NOREF;

/* ----------------------------------------------------------------
 * C line handler — called by readline when a complete line is ready.
 * 'line' is a malloc'd string (or NULL on EOF / Ctrl-D).
 * ---------------------------------------------------------------- */

static void c_line_handler(char *line) {
    if (line == NULL) {
        /* EOF: remove handler so the next read_char() call is a no-op */
        rl_callback_handler_remove();
        return;
    }

    if (g_L == NULL || g_callback_ref == LUA_NOREF) {
        free(line);
        return;
    }

    /* Push and call the Lua callback with the line string */
    lua_rawgeti(g_L, LUA_REGISTRYINDEX, g_callback_ref);
    lua_pushstring(g_L, line);
    free(line);
    /* pcall so a Lua error in the callback does not crash the process */
    if (lua_pcall(g_L, 1, 0, 0) != LUA_OK) {
        /* Print the error but keep going */
        fprintf(stderr, "[turtle_readline] callback error: %s\n",
                lua_tostring(g_L, -1));
        lua_pop(g_L, 1);
    }
}

/* ----------------------------------------------------------------
 * readline.install_handler(prompt, callback)
 * ---------------------------------------------------------------- */

static int l_install_handler(lua_State *L) {
    const char *prompt = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    /* Release any previously registered Lua callback */
    if (g_callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_callback_ref);
        g_callback_ref = LUA_NOREF;
    }

    /* Pin the new callback in the registry */
    lua_pushvalue(L, 2);
    g_callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    g_L = L;

    rl_callback_handler_install(prompt, c_line_handler);
    return 0;
}

/* ----------------------------------------------------------------
 * readline.read_char()
 * ---------------------------------------------------------------- */

static int l_read_char(lua_State *L) {
    (void)L;
    rl_callback_read_char();
    return 0;
}

/* ----------------------------------------------------------------
 * readline.stdin_has_input(timeout_ms) -> boolean
 * ---------------------------------------------------------------- */

static int l_stdin_has_input(lua_State *L) {
    int timeout_ms = (int)luaL_optinteger(L, 1, 10);

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(0, &fds);   /* stdin = fd 0 */

    struct timeval tv;
    tv.tv_sec  = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    int ret = select(1, &fds, NULL, NULL, &tv);
    lua_pushboolean(L, ret > 0);
    return 1;
}

/* ----------------------------------------------------------------
 * readline.remove_handler()
 * ---------------------------------------------------------------- */

static int l_remove_handler(lua_State *L) {
    (void)L;
    rl_callback_handler_remove();

    if (g_callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, g_callback_ref);
        g_callback_ref = LUA_NOREF;
    }
    g_L = NULL;
    return 0;
}

/* ----------------------------------------------------------------
 * readline.add_history(line)
 * ---------------------------------------------------------------- */

static int l_add_history(lua_State *L) {
    const char *line = luaL_checkstring(L, 1);
    /* Skip blank lines so they do not pollute history */
    if (line && *line) {
        add_history(line);
    }
    return 0;
}

/* ----------------------------------------------------------------
 * Module registration
 * ---------------------------------------------------------------- */

static const luaL_Reg turtle_readline_funcs[] = {
    {"install_handler", l_install_handler},
    {"read_char",       l_read_char},
    {"stdin_has_input", l_stdin_has_input},
    {"remove_handler",  l_remove_handler},
    {"add_history",     l_add_history},
    {NULL, NULL}
};

int luaopen_turtle_readline(lua_State *L) {
    luaL_newlib(L, turtle_readline_funcs);
    return 1;
}

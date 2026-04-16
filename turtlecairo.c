/*
 * turtlecairo.c
 * Cairo + SDL2 binding for Lua 5.4 turtle graphics.
 * Drop-in replacement for turtleray.c — same Lua API surface.
 *
 * Architecture:
 *   - Persistent canvas:  Cairo ARGB32 image surface + SDL streaming texture.
 *                         Segments (lines, fills, dots, text, stamps) are drawn
 *                         here and survive across frames.
 *   - Per-frame overlay:  Second Cairo surface cleared each frame.
 *                         Turtle heads (ephemeral) are drawn here.
 *   - Compositing:        end_drawing() uploads both surfaces via SDL_UpdateTexture,
 *                         fills background, blits canvas, alpha-blends overlay.
 *
 * Build (macOS/Homebrew):
 *   cc -shared -o turtlecairo.so turtlecairo.c \
 *      -I/opt/homebrew/include/lua5.4 \
 *      $(pkg-config --cflags --libs sdl2 cairo) \
 *      -undefined dynamic_lookup
 *
 * Usage from Lua:
 *   local cairo = require("turtlecairo")
 *   cairo.init_window(800, 600, "Turtle")
 *   cairo.create_canvas(800, 600)
 *   -- draw to persistent canvas:
 *   cairo.begin_canvas()
 *   cairo.draw_line(0, 0, 100, 100, 255, 0, 0, 255, 2)
 *   cairo.end_canvas()
 *   -- draw frame (overlay + present):
 *   cairo.begin_drawing()   -- clears overlay
 *   cairo.draw_circle(400, 300, 8, 255, 255, 255, 255)  -- turtle head on overlay
 *   cairo.clear(20, 20, 30, 255)  -- set background color
 *   cairo.end_drawing()     -- compose and present
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <SDL.h>
#include <cairo.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ----------------------------------------------------------------
 * Global state
 * ---------------------------------------------------------------- */

static SDL_Window   *g_window    = NULL;
static SDL_Renderer *g_sdl_rend  = NULL;
static int           g_should_close = 0;

/* Persistent canvas — turtle drawing lives here between frames */
static cairo_surface_t *g_canvas_surf = NULL;
static cairo_t         *g_canvas_cr   = NULL;
static SDL_Texture     *g_canvas_tex  = NULL;

/* Per-frame overlay — turtle heads, cleared each frame */
static cairo_surface_t *g_overlay_surf = NULL;
static cairo_t         *g_overlay_cr   = NULL;
static SDL_Texture     *g_overlay_tex  = NULL;

/* Active drawing context — points to canvas_cr or overlay_cr */
static cairo_t *g_active_cr = NULL;

/* Background color set by clear(), consumed in end_drawing() */
static double g_bg_r = 0.0, g_bg_g = 0.0, g_bg_b = 0.0, g_bg_a = 1.0;

/* ----------------------------------------------------------------
 * Helpers
 * ---------------------------------------------------------------- */

/* Colors arrive from Lua as 0-255 integers; convert to [0,1] for Cairo. */
static void set_source_rgba_255(cairo_t *cr, lua_State *L, int idx) {
    double r = (double)luaL_checkinteger(L, idx)         / 255.0;
    double g = (double)luaL_checkinteger(L, idx + 1)     / 255.0;
    double b = (double)luaL_checkinteger(L, idx + 2)     / 255.0;
    double a = (double)luaL_optinteger(L, idx + 3, 255)  / 255.0;
    cairo_set_source_rgba(cr, r, g, b, a);
}

/* Upload a Cairo ARGB32 surface to an SDL2 streaming texture.
 * Cairo ARGB32 pixel layout on little-endian is B,G,R,A in memory,
 * which matches SDL_PIXELFORMAT_ARGB8888. */
static void upload_surface_to_texture(cairo_surface_t *surf, SDL_Texture *tex) {
    cairo_surface_flush(surf);
    unsigned char *data   = cairo_image_surface_get_data(surf);
    int            stride = cairo_image_surface_get_stride(surf);
    SDL_UpdateTexture(tex, NULL, data, stride);
}

/* Apply good line-drawing defaults to a new cairo context. */
static void set_cairo_defaults(cairo_t *cr) {
    cairo_set_line_cap(cr,  CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    cairo_select_font_face(cr, "sans-serif",
        CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
}

/* ----------------------------------------------------------------
 * Window management
 * ---------------------------------------------------------------- */

static int l_init_window(lua_State *L) {
    int         w     = (int)luaL_checkinteger(L, 1);
    int         h     = (int)luaL_checkinteger(L, 2);
    const char *title = luaL_checkstring(L, 3);

    if (SDL_Init(SDL_INIT_VIDEO) != 0)
        return luaL_error(L, "SDL_Init failed: %s", SDL_GetError());

    g_window = SDL_CreateWindow(title,
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        w, h, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
    if (!g_window)
        return luaL_error(L, "SDL_CreateWindow failed: %s", SDL_GetError());

    g_sdl_rend = SDL_CreateRenderer(g_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!g_sdl_rend) {
        /* Fallback to software renderer */
        g_sdl_rend = SDL_CreateRenderer(g_window, -1, SDL_RENDERER_SOFTWARE);
        if (!g_sdl_rend)
            return luaL_error(L, "SDL_CreateRenderer failed: %s", SDL_GetError());
    }

    SDL_SetRenderDrawBlendMode(g_sdl_rend, SDL_BLENDMODE_BLEND);
    g_should_close = 0;
    return 0;
}

static int l_close_window(lua_State *L) {
    (void)L;
    if (g_canvas_cr)    { cairo_destroy(g_canvas_cr);             g_canvas_cr    = NULL; }
    if (g_canvas_surf)  { cairo_surface_destroy(g_canvas_surf);   g_canvas_surf  = NULL; }
    if (g_canvas_tex)   { SDL_DestroyTexture(g_canvas_tex);       g_canvas_tex   = NULL; }
    if (g_overlay_cr)   { cairo_destroy(g_overlay_cr);            g_overlay_cr   = NULL; }
    if (g_overlay_surf) { cairo_surface_destroy(g_overlay_surf);  g_overlay_surf = NULL; }
    if (g_overlay_tex)  { SDL_DestroyTexture(g_overlay_tex);      g_overlay_tex  = NULL; }
    if (g_sdl_rend)     { SDL_DestroyRenderer(g_sdl_rend);        g_sdl_rend     = NULL; }
    if (g_window)       { SDL_DestroyWindow(g_window);            g_window       = NULL; }
    SDL_Quit();
    return 0;
}

/* window_should_close() — drain SDL event queue, return true if quit requested */
static int l_window_should_close(lua_State *L) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT)
            g_should_close = 1;
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE)
            g_should_close = 1;
    }
    lua_pushboolean(L, g_should_close);
    return 1;
}

static int l_get_screen_width(lua_State *L) {
    int w = 0, h = 0;
    if (g_window) SDL_GetWindowSize(g_window, &w, &h);
    lua_pushinteger(L, w);
    return 1;
}

static int l_get_screen_height(lua_State *L) {
    int w = 0, h = 0;
    if (g_window) SDL_GetWindowSize(g_window, &w, &h);
    lua_pushinteger(L, h);
    return 1;
}

/* set_target_fps — no-op; SDL_RENDERER_PRESENTVSYNC handles timing */
static int l_set_target_fps(lua_State *L) {
    (void)L;
    return 0;
}

/* ----------------------------------------------------------------
 * Canvas management
 * ---------------------------------------------------------------- */

static void destroy_canvas_resources(void) {
    if (g_canvas_cr)    { cairo_destroy(g_canvas_cr);             g_canvas_cr    = NULL; }
    if (g_canvas_surf)  { cairo_surface_destroy(g_canvas_surf);   g_canvas_surf  = NULL; }
    if (g_canvas_tex)   { SDL_DestroyTexture(g_canvas_tex);       g_canvas_tex   = NULL; }
    if (g_overlay_cr)   { cairo_destroy(g_overlay_cr);            g_overlay_cr   = NULL; }
    if (g_overlay_surf) { cairo_surface_destroy(g_overlay_surf);  g_overlay_surf = NULL; }
    if (g_overlay_tex)  { SDL_DestroyTexture(g_overlay_tex);      g_overlay_tex  = NULL; }
    g_active_cr = NULL;
}

/* create_canvas(w, h) — (re)create canvas + overlay surfaces and textures */
static int l_create_canvas(lua_State *L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);

    destroy_canvas_resources();

    /* --- Canvas surface --- */
    g_canvas_surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    if (cairo_surface_status(g_canvas_surf) != CAIRO_STATUS_SUCCESS)
        return luaL_error(L, "cairo_image_surface_create failed (canvas)");
    g_canvas_cr = cairo_create(g_canvas_surf);
    set_cairo_defaults(g_canvas_cr);
    /* Clear to transparent */
    cairo_set_operator(g_canvas_cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(g_canvas_cr);
    cairo_set_operator(g_canvas_cr, CAIRO_OPERATOR_OVER);

    /* --- Overlay surface --- */
    g_overlay_surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    if (cairo_surface_status(g_overlay_surf) != CAIRO_STATUS_SUCCESS)
        return luaL_error(L, "cairo_image_surface_create failed (overlay)");
    g_overlay_cr = cairo_create(g_overlay_surf);
    set_cairo_defaults(g_overlay_cr);

    /* --- SDL textures (ARGB8888 matches Cairo ARGB32 on little-endian) --- */
    g_canvas_tex = SDL_CreateTexture(g_sdl_rend,
        SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);
    if (!g_canvas_tex)
        return luaL_error(L, "SDL_CreateTexture (canvas) failed: %s", SDL_GetError());
    SDL_SetTextureBlendMode(g_canvas_tex, SDL_BLENDMODE_BLEND);

    g_overlay_tex = SDL_CreateTexture(g_sdl_rend,
        SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);
    if (!g_overlay_tex)
        return luaL_error(L, "SDL_CreateTexture (overlay) failed: %s", SDL_GetError());
    SDL_SetTextureBlendMode(g_overlay_tex, SDL_BLENDMODE_BLEND);

    g_active_cr = g_canvas_cr;
    return 0;
}

/* begin_canvas() — route subsequent draw calls to the persistent canvas */
static int l_begin_canvas(lua_State *L) {
    (void)L;
    g_active_cr = g_canvas_cr;
    return 0;
}

/* end_canvas() — flush canvas surface (marks pixels as ready for upload) */
static int l_end_canvas(lua_State *L) {
    (void)L;
    if (g_canvas_surf) cairo_surface_flush(g_canvas_surf);
    return 0;
}

/* draw_canvas() — no-op; compositing is handled entirely in end_drawing() */
static int l_draw_canvas(lua_State *L) {
    (void)L;
    return 0;
}

/* clear_canvas(r, g, b, a) — wipe canvas with the given color (full-redraw path) */
static int l_clear_canvas(lua_State *L) {
    if (!g_canvas_cr) return 0;
    double r = (double)luaL_checkinteger(L, 1) / 255.0;
    double g = (double)luaL_checkinteger(L, 2) / 255.0;
    double b = (double)luaL_checkinteger(L, 3) / 255.0;
    double a = (double)luaL_optinteger(L, 4, 255) / 255.0;
    /* CLEAR zeroes all channels (including alpha) */
    cairo_set_operator(g_canvas_cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(g_canvas_cr);
    cairo_set_operator(g_canvas_cr, CAIRO_OPERATOR_OVER);
    /* Paint background color if not fully transparent */
    if (a > 0.0) {
        cairo_set_source_rgba(g_canvas_cr, r, g, b, a);
        cairo_paint(g_canvas_cr);
    }
    return 0;
}

/* resize_canvas(w, h) — recreate if size changed; returns bool */
static int l_resize_canvas(lua_State *L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    int cur_w = 0, cur_h = 0;
    if (g_canvas_surf) {
        cur_w = cairo_image_surface_get_width(g_canvas_surf);
        cur_h = cairo_image_surface_get_height(g_canvas_surf);
    }
    if (cur_w == w && cur_h == h) {
        lua_pushboolean(L, 0);
        return 1;
    }
    l_create_canvas(L);   /* args w, h are still on the stack */
    lua_pushboolean(L, 1);
    return 1;
}

/* ----------------------------------------------------------------
 * Drawing frame
 * ---------------------------------------------------------------- */

/* begin_drawing() — switch active context to overlay, clear overlay to transparent */
static int l_begin_drawing(lua_State *L) {
    (void)L;
    if (!g_overlay_cr) return 0;
    g_active_cr = g_overlay_cr;
    cairo_set_operator(g_overlay_cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(g_overlay_cr);
    cairo_set_operator(g_overlay_cr, CAIRO_OPERATOR_OVER);
    return 0;
}

/* end_drawing() — upload surfaces, fill background, compose, present */
static int l_end_drawing(lua_State *L) {
    (void)L;
    if (!g_sdl_rend) return 0;

    /* Fill background */
    SDL_SetRenderDrawColor(g_sdl_rend,
        (Uint8)(g_bg_r * 255),
        (Uint8)(g_bg_g * 255),
        (Uint8)(g_bg_b * 255),
        (Uint8)(g_bg_a * 255));
    SDL_RenderClear(g_sdl_rend);

    /* Blit persistent canvas */
    if (g_canvas_surf && g_canvas_tex) {
        upload_surface_to_texture(g_canvas_surf, g_canvas_tex);
        SDL_RenderCopy(g_sdl_rend, g_canvas_tex, NULL, NULL);
    }

    /* Alpha-blend overlay (turtle heads) on top */
    if (g_overlay_surf && g_overlay_tex) {
        cairo_surface_flush(g_overlay_surf);
        upload_surface_to_texture(g_overlay_surf, g_overlay_tex);
        SDL_RenderCopy(g_sdl_rend, g_overlay_tex, NULL, NULL);
    }

    SDL_RenderPresent(g_sdl_rend);
    return 0;
}

/* clear(r, g, b, a) — store background color; consumed by end_drawing() */
static int l_clear(lua_State *L) {
    g_bg_r = (double)luaL_checkinteger(L, 1) / 255.0;
    g_bg_g = (double)luaL_checkinteger(L, 2) / 255.0;
    g_bg_b = (double)luaL_checkinteger(L, 3) / 255.0;
    g_bg_a = (double)luaL_optinteger(L, 4, 255) / 255.0;
    return 0;
}

/* ----------------------------------------------------------------
 * Drawing primitives — all write to g_active_cr
 * ---------------------------------------------------------------- */

/* draw_line(x1, y1, x2, y2, r, g, b, a, thickness) */
static int l_draw_line(lua_State *L) {
    if (!g_active_cr) return 0;
    double x1    = luaL_checknumber(L, 1);
    double y1    = luaL_checknumber(L, 2);
    double x2    = luaL_checknumber(L, 3);
    double y2    = luaL_checknumber(L, 4);
    set_source_rgba_255(g_active_cr, L, 5);
    double thick = luaL_optnumber(L, 9, 2.0);
    cairo_set_line_width(g_active_cr, thick);
    cairo_move_to(g_active_cr, x1, y1);
    cairo_line_to(g_active_cr, x2, y2);
    cairo_stroke(g_active_cr);
    return 0;
}

/* draw_circle(cx, cy, radius, r, g, b, a) — filled dot */
static int l_draw_circle(lua_State *L) {
    if (!g_active_cr) return 0;
    double cx     = luaL_checknumber(L, 1);
    double cy     = luaL_checknumber(L, 2);
    double radius = luaL_checknumber(L, 3);
    set_source_rgba_255(g_active_cr, L, 4);
    cairo_arc(g_active_cr, cx, cy, radius, 0.0, 2.0 * M_PI);
    cairo_fill(g_active_cr);
    return 0;
}

/* draw_circle_lines(cx, cy, radius, r, g, b, a) — circle outline */
static int l_draw_circle_lines(lua_State *L) {
    if (!g_active_cr) return 0;
    double cx     = luaL_checknumber(L, 1);
    double cy     = luaL_checknumber(L, 2);
    double radius = luaL_checknumber(L, 3);
    set_source_rgba_255(g_active_cr, L, 4);
    cairo_arc(g_active_cr, cx, cy, radius, 0.0, 2.0 * M_PI);
    cairo_stroke(g_active_cr);
    return 0;
}

/*
 * draw_polygon_fill(points_table, r, g, b, a)
 * points_table = {{x1,y1}, {x2,y2}, ...}
 * Cairo fills the path correctly regardless of winding order.
 */
static int l_draw_polygon_fill(lua_State *L) {
    if (!g_active_cr) return 0;
    luaL_checktype(L, 1, LUA_TTABLE);
    int n = (int)luaL_len(L, 1);
    if (n < 3) return 0;

    set_source_rgba_255(g_active_cr, L, 2);

    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, 1, i + 1);       /* points[i+1] */
        lua_rawgeti(L, -1, 1);          /* x */
        double x = lua_tonumber(L, -1); lua_pop(L, 1);
        lua_rawgeti(L, -1, 2);          /* y */
        double y = lua_tonumber(L, -1); lua_pop(L, 1);
        lua_pop(L, 1);                  /* pop sub-table */

        if (i == 0)
            cairo_move_to(g_active_cr, x, y);
        else
            cairo_line_to(g_active_cr, x, y);
    }
    cairo_close_path(g_active_cr);
    cairo_fill(g_active_cr);
    return 0;
}

/*
 * draw_text(text, x, y, font_size, r, g, b, a)
 * x, y is the top-left of the text baseline box.
 * Internally adjusted so the text visual top aligns with y.
 */
static int l_draw_text(lua_State *L) {
    if (!g_active_cr) return 0;
    const char *text = luaL_checkstring(L, 1);
    double x         = luaL_checknumber(L, 2);
    double y         = luaL_checknumber(L, 3);
    double size      = luaL_checknumber(L, 4);
    set_source_rgba_255(g_active_cr, L, 5);
    cairo_set_font_size(g_active_cr, size);
    /* Adjust y: move baseline down by ascent so text top aligns with y */
    cairo_font_extents_t fe;
    cairo_font_extents(g_active_cr, &fe);
    cairo_move_to(g_active_cr, x, y + fe.ascent);
    cairo_show_text(g_active_cr, text);
    return 0;
}

/* measure_text(text, font_size) -> width */
static int l_measure_text(lua_State *L) {
    const char *text = luaL_checkstring(L, 1);
    double size      = luaL_checknumber(L, 2);
    cairo_t *cr = g_canvas_cr ? g_canvas_cr : g_overlay_cr;
    if (!cr) { lua_pushnumber(L, 0); return 1; }
    cairo_set_font_size(cr, size);
    cairo_text_extents_t ext;
    cairo_text_extents(cr, text, &ext);
    lua_pushnumber(L, ext.width);
    return 1;
}

/* Raylib-compat stubs — not needed by Cairo renderer but kept for API surface */
static int l_draw_ring(lua_State *L)          { (void)L; return 0; }
static int l_draw_sector(lua_State *L)        { (void)L; return 0; }
static int l_draw_triangle_fill(lua_State *L) { (void)L; return 0; }

/* ----------------------------------------------------------------
 * Input
 * ---------------------------------------------------------------- */

/* Key/mouse events are drained in window_should_close().
 * Individual query functions are stubs for API compatibility.
 * Proper event dispatch is a future milestone. */
static int l_is_key_pressed(lua_State *L) {
    (void)L;
    lua_pushboolean(L, 0);
    return 1;
}

static int l_get_mouse_x(lua_State *L) {
    int x = 0, y = 0;
    SDL_GetMouseState(&x, &y);
    lua_pushinteger(L, x);
    return 1;
}

static int l_get_mouse_y(lua_State *L) {
    int x = 0, y = 0;
    SDL_GetMouseState(&x, &y);
    lua_pushinteger(L, y);
    return 1;
}

static int l_is_mouse_button_pressed(lua_State *L) {
    (void)L;
    lua_pushboolean(L, 0);
    return 1;
}

/* ----------------------------------------------------------------
 * Timing
 * ---------------------------------------------------------------- */

static int l_get_time(lua_State *L) {
    lua_pushnumber(L, SDL_GetTicks() / 1000.0);
    return 1;
}

static int l_wait(lua_State *L) {
    double seconds = luaL_checknumber(L, 1);
    if (seconds > 0) SDL_Delay((Uint32)(seconds * 1000.0));
    return 0;
}

/* ----------------------------------------------------------------
 * Module registration
 * ---------------------------------------------------------------- */

static const luaL_Reg turtlecairo_funcs[] = {
    /* Window */
    {"init_window",              l_init_window},
    {"close_window",             l_close_window},
    {"window_should_close",      l_window_should_close},
    {"get_screen_width",         l_get_screen_width},
    {"get_screen_height",        l_get_screen_height},
    {"set_target_fps",           l_set_target_fps},

    /* Drawing frame */
    {"begin_drawing",            l_begin_drawing},
    {"end_drawing",              l_end_drawing},
    {"clear",                    l_clear},

    /* Primitives */
    {"draw_line",                l_draw_line},
    {"draw_circle",              l_draw_circle},
    {"draw_circle_lines",        l_draw_circle_lines},
    {"draw_ring",                l_draw_ring},
    {"draw_sector",              l_draw_sector},
    {"draw_triangle_fill",       l_draw_triangle_fill},
    {"draw_polygon_fill",        l_draw_polygon_fill},
    {"draw_text",                l_draw_text},
    {"measure_text",             l_measure_text},

    /* Canvas (persistent surface) */
    {"create_canvas",            l_create_canvas},
    {"begin_canvas",             l_begin_canvas},
    {"end_canvas",               l_end_canvas},
    {"draw_canvas",              l_draw_canvas},
    {"clear_canvas",             l_clear_canvas},
    {"resize_canvas",            l_resize_canvas},

    /* Input */
    {"is_key_pressed",           l_is_key_pressed},
    {"get_mouse_x",              l_get_mouse_x},
    {"get_mouse_y",              l_get_mouse_y},
    {"is_mouse_button_pressed",  l_is_mouse_button_pressed},

    /* Timing */
    {"get_time",                 l_get_time},
    {"wait",                     l_wait},

    {NULL, NULL}
};

int luaopen_turtlecairo(lua_State *L) {
    luaL_newlib(L, turtlecairo_funcs);

    /* SDL key constants */
    lua_pushinteger(L, SDLK_ESCAPE); lua_setfield(L, -2, "KEY_ESCAPE");
    lua_pushinteger(L, SDLK_SPACE);  lua_setfield(L, -2, "KEY_SPACE");
    lua_pushinteger(L, SDLK_RETURN); lua_setfield(L, -2, "KEY_ENTER");
    lua_pushinteger(L, SDLK_UP);     lua_setfield(L, -2, "KEY_UP");
    lua_pushinteger(L, SDLK_DOWN);   lua_setfield(L, -2, "KEY_DOWN");
    lua_pushinteger(L, SDLK_LEFT);   lua_setfield(L, -2, "KEY_LEFT");
    lua_pushinteger(L, SDLK_RIGHT);  lua_setfield(L, -2, "KEY_RIGHT");

    /* SDL mouse button constants */
    lua_pushinteger(L, SDL_BUTTON_LEFT);  lua_setfield(L, -2, "MOUSE_LEFT");
    lua_pushinteger(L, SDL_BUTTON_RIGHT); lua_setfield(L, -2, "MOUSE_RIGHT");

    return 1;
}

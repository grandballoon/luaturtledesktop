/*
 * turtleray.c
 * Minimal Raylib binding for Lua 5.4 turtle graphics.
 * Exposes only what the turtle renderer needs — not a general Raylib binding.
 *
 * Build (macOS/Homebrew):
 *   cc -shared -o turtleray.so turtleray.c \
 *      -I/opt/homebrew/include/lua5.4 \
 *      -I/opt/homebrew/include \
 *      -L/opt/homebrew/lib \
 *      -llua5.4 -lraylib \
 *      -framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo \
 *      -undefined dynamic_lookup
 *
 * Usage from Lua:
 *   local ray = require("turtleray")
 *   ray.init_window(800, 600, "Turtle")
 *   while not ray.window_should_close() do
 *       ray.begin_drawing()
 *       ray.clear(0, 0, 0, 255)
 *       ray.draw_line(0, 0, 100, 100, 255, 0, 0, 255, 2.0)
 *       ray.end_drawing()
 *   end
 *   ray.close_window()
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <raylib.h>
#include <rlgl.h>
#include <math.h>
#include <stdlib.h>

/* Supersampling scale for the persistent canvas.
 * The canvas RenderTexture is created at CANVAS_SCALE x the window size.
 * All drawing is scaled up by this factor via an rlgl matrix push, then
 * blitted back to the screen at 1x with bilinear filtering.
 * This gives effective anti-aliasing since Raylib's MSAA flag only applies
 * to the main framebuffer, not RenderTexture2D targets. */
#define CANVAS_SCALE 2

/* ----------------------------------------------------------------
 * Helpers
 * ---------------------------------------------------------------- */

static Color lua_tocolor(lua_State *L, int idx) {
    Color c;
    c.r = (unsigned char)luaL_checkinteger(L, idx);
    c.g = (unsigned char)luaL_checkinteger(L, idx + 1);
    c.b = (unsigned char)luaL_checkinteger(L, idx + 2);
    c.a = (unsigned char)luaL_optinteger(L, idx + 3, 255);
    return c;
}

/* ----------------------------------------------------------------
 * Window management
 * ---------------------------------------------------------------- */

static int l_init_window(lua_State *L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    const char *title = luaL_checkstring(L, 3);
    SetConfigFlags(FLAG_MSAA_4X_HINT | FLAG_WINDOW_RESIZABLE);
    InitWindow(w, h, title);
    SetTargetFPS(60);
    return 0;
}

static int l_close_window(lua_State *L) {
    (void)L;
    CloseWindow();
    return 0;
}

static int l_window_should_close(lua_State *L) {
    lua_pushboolean(L, WindowShouldClose());
    return 1;
}

static int l_get_screen_width(lua_State *L) {
    lua_pushinteger(L, GetScreenWidth());
    return 1;
}

static int l_get_screen_height(lua_State *L) {
    lua_pushinteger(L, GetScreenHeight());
    return 1;
}

static int l_set_target_fps(lua_State *L) {
    int fps = (int)luaL_checkinteger(L, 1);
    SetTargetFPS(fps);
    return 0;
}

/* ----------------------------------------------------------------
 * Drawing frame
 * ---------------------------------------------------------------- */

static int l_begin_drawing(lua_State *L) {
    (void)L;
    BeginDrawing();
    return 0;
}

static int l_end_drawing(lua_State *L) {
    (void)L;
    EndDrawing();
    return 0;
}

static int l_clear(lua_State *L) {
    Color c = lua_tocolor(L, 1);
    ClearBackground(c);
    return 0;
}

/* ----------------------------------------------------------------
 * Drawing primitives
 * ---------------------------------------------------------------- */

/* draw_line(x1, y1, x2, y2, r, g, b, a, thickness) */
static int l_draw_line(lua_State *L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    Color c = lua_tocolor(L, 5);
    float thick = (float)luaL_optnumber(L, 9, 2.0);
    /* Always use DrawLineEx: float coordinates avoid integer-snapping jaggies.
     * The 2x canvas supersampling + bilinear downscale provides anti-aliasing. */
    DrawLineEx((Vector2){x1, y1}, (Vector2){x2, y2}, thick, c);
    return 0;
}

/* draw_circle(cx, cy, radius, r, g, b, a) — filled */
static int l_draw_circle(lua_State *L) {
    float cx = (float)luaL_checknumber(L, 1);
    float cy = (float)luaL_checknumber(L, 2);
    float radius = (float)luaL_checknumber(L, 3);
    Color c = lua_tocolor(L, 4);
    /* DrawCircleV uses float center coords (vs DrawCircle which truncates to int) */
    DrawCircleV((Vector2){cx, cy}, radius, c);
    return 0;
}

/* draw_circle_lines(cx, cy, radius, r, g, b, a) — outline */
static int l_draw_circle_lines(lua_State *L) {
    float cx = (float)luaL_checknumber(L, 1);
    float cy = (float)luaL_checknumber(L, 2);
    float radius = (float)luaL_checknumber(L, 3);
    Color c = lua_tocolor(L, 4);
    DrawCircleLinesV((Vector2){cx, cy}, radius, c);
    return 0;
}

/* draw_ring(cx, cy, inner_radius, outer_radius, start_angle, end_angle, segments, r, g, b, a) */
static int l_draw_ring(lua_State *L) {
    float cx = (float)luaL_checknumber(L, 1);
    float cy = (float)luaL_checknumber(L, 2);
    float inner = (float)luaL_checknumber(L, 3);
    float outer = (float)luaL_checknumber(L, 4);
    float start = (float)luaL_checknumber(L, 5);
    float end_a = (float)luaL_checknumber(L, 6);
    int segs = (int)luaL_checkinteger(L, 7);
    Color c = lua_tocolor(L, 8);
    DrawRing((Vector2){cx, cy}, inner, outer, start, end_a, segs, c);
    return 0;
}

/* draw_sector(cx, cy, radius, start_angle, end_angle, segments, r, g, b, a) — filled arc */
static int l_draw_sector(lua_State *L) {
    float cx = (float)luaL_checknumber(L, 1);
    float cy = (float)luaL_checknumber(L, 2);
    float radius = (float)luaL_checknumber(L, 3);
    float start = (float)luaL_checknumber(L, 4);
    float end_a = (float)luaL_checknumber(L, 5);
    int segs = (int)luaL_checkinteger(L, 6);
    Color c = lua_tocolor(L, 7);
    DrawCircleSector((Vector2){cx, cy}, radius, start, end_a, segs, c);    return 0;
}

/* draw_triangle_fill(x1,y1, x2,y2, x3,y3, r,g,b,a) */
static int l_draw_triangle_fill(lua_State *L) {
    Vector2 v1 = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2) };
    Vector2 v2 = { (float)luaL_checknumber(L, 3), (float)luaL_checknumber(L, 4) };
    Vector2 v3 = { (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    Color c = lua_tocolor(L, 7);
    DrawTriangle(v1, v2, v3, c);
    return 0;
}

/*
 * draw_polygon_fill(points_table, r, g, b, a)
 * points_table = {{x1,y1}, {x2,y2}, ...}
 * Uses triangle fan from first vertex.
 */
static int l_draw_polygon_fill(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    int n = (int)luaL_len(L, 1);
    if (n < 3) return 0;

    Color c = lua_tocolor(L, 2);

    /* Read all points */
    Vector2 *pts = (Vector2 *)malloc(sizeof(Vector2) * n);
    if (!pts) return 0;

    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, 1, i + 1);       /* get points[i+1] */
        lua_rawgeti(L, -1, 1);          /* get x */
        pts[i].x = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
        lua_rawgeti(L, -1, 2);          /* get y */
        pts[i].y = (float)lua_tonumber(L, -1);
        lua_pop(L, 2);                  /* pop y and the sub-table */
    }

    /* Compute signed area via shoelace formula.
     * In screen space (y-down): area > 0 means CW, area < 0 means CCW.
     * Raylib's DrawTriangle requires CCW, so reverse vertices if CW. */
    float area = 0.0f;
    for (int i = 0, j = n - 1; i < n; j = i++) {
        area += pts[j].x * pts[i].y;
        area -= pts[i].x * pts[j].y;
    }
    if (area >= 0.0f) {
        for (int lo = 0, hi = n - 1; lo < hi; lo++, hi--) {
            Vector2 tmp = pts[lo];
            pts[lo] = pts[hi];
            pts[hi] = tmp;
        }
    }

    /* Triangle fan decomposition */
    for (int i = 1; i < n - 1; i++) {
        DrawTriangle(pts[0], pts[i], pts[i + 1], c);
    }

    free(pts);
    return 0;
}

/* draw_text(text, x, y, font_size, r, g, b, a) */
static int l_draw_text(lua_State *L) {
    const char *text = luaL_checkstring(L, 1);
    int x = (int)luaL_checknumber(L, 2);
    int y = (int)luaL_checknumber(L, 3);
    int size = (int)luaL_checkinteger(L, 4);
    Color c = lua_tocolor(L, 5);
    DrawText(text, x, y, size, c);
    return 0;
}

/* measure_text(text, font_size) -> width */
static int l_measure_text(lua_State *L) {
    const char *text = luaL_checkstring(L, 1);
    int size = (int)luaL_checkinteger(L, 2);
    lua_pushinteger(L, MeasureText(text, size));
    return 1;
}

/* ----------------------------------------------------------------
 * Render texture (for persistent canvas / double buffering)
 * ---------------------------------------------------------------- */

static RenderTexture2D canvas_rt = {0};
static int canvas_active = 0;
static int canvas_logical_w = 0;
static int canvas_logical_h = 0;

/* create_canvas(width, height) — create an offscreen render texture at 2x size */
static int l_create_canvas(lua_State *L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    if (canvas_active) {
        UnloadRenderTexture(canvas_rt);
    }
    canvas_logical_w = w;
    canvas_logical_h = h;
    canvas_rt = LoadRenderTexture(CANVAS_SCALE * w, CANVAS_SCALE * h);
    SetTextureFilter(canvas_rt.texture, TEXTURE_FILTER_BILINEAR);
    canvas_active = 1;

    /* Clear it to transparent */
    BeginTextureMode(canvas_rt);
    ClearBackground((Color){0, 0, 0, 0});
    EndTextureMode();

    return 0;
}

/* begin_canvas() — start drawing to the offscreen canvas (with 2x scale matrix) */
static int l_begin_canvas(lua_State *L) {
    (void)L;
    if (canvas_active) {
        BeginTextureMode(canvas_rt);
        rlPushMatrix();
        rlScalef(CANVAS_SCALE, CANVAS_SCALE, 1.0f);
    }
    return 0;
}

/* end_canvas() — stop drawing to the offscreen canvas */
static int l_end_canvas(lua_State *L) {
    (void)L;
    if (canvas_active) {
        rlPopMatrix();
        EndTextureMode();
    }
    return 0;
}

/* draw_canvas() — draw the offscreen canvas to the screen */
static int l_draw_canvas(lua_State *L) {
    (void)L;
    if (canvas_active) {
        /* RenderTexture is flipped vertically, so we draw with flipped source rect */
        Rectangle src = {
            0, 0,
            (float)canvas_rt.texture.width,
            -(float)canvas_rt.texture.height  /* flip Y */
        };
        Rectangle dst = {
            0, 0,
            (float)GetScreenWidth(),
            (float)GetScreenHeight()
        };
        DrawTexturePro(canvas_rt.texture, src, dst, (Vector2){0, 0}, 0, WHITE);
    }
    return 0;
}

/* clear_canvas(r, g, b, a) — clear the offscreen canvas */
static int l_clear_canvas(lua_State *L) {
    if (canvas_active) {
        Color c = lua_tocolor(L, 1);
        BeginTextureMode(canvas_rt);
        ClearBackground(c);
        EndTextureMode();
    }
    return 0;
}

/* resize_canvas(width, height) — recreate canvas if logical size changed */
static int l_resize_canvas(lua_State *L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    if (canvas_active) {
        /* Compare against logical dimensions, not the 2x texture dimensions */
        if (canvas_logical_w != w || canvas_logical_h != h) {
            UnloadRenderTexture(canvas_rt);
            canvas_logical_w = w;
            canvas_logical_h = h;
            canvas_rt = LoadRenderTexture(CANVAS_SCALE * w, CANVAS_SCALE * h);
            SetTextureFilter(canvas_rt.texture, TEXTURE_FILTER_BILINEAR);
            /* Clear new canvas */
            BeginTextureMode(canvas_rt);
            ClearBackground((Color){0, 0, 0, 0});
            EndTextureMode();
            lua_pushboolean(L, 1);  /* resized */
        } else {
            lua_pushboolean(L, 0);  /* no change */
        }
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/* ----------------------------------------------------------------
 * Input (for future interactive turtle / events)
 * ---------------------------------------------------------------- */

static int l_is_key_pressed(lua_State *L) {
    int key = (int)luaL_checkinteger(L, 1);
    lua_pushboolean(L, IsKeyPressed(key));
    return 1;
}

static int l_get_mouse_x(lua_State *L) {
    lua_pushinteger(L, GetMouseX());
    return 1;
}

static int l_get_mouse_y(lua_State *L) {
    lua_pushinteger(L, GetMouseY());
    return 1;
}

static int l_is_mouse_button_pressed(lua_State *L) {
    int btn = (int)luaL_checkinteger(L, 1);
    lua_pushboolean(L, IsMouseButtonPressed(btn));
    return 1;
}

/* ----------------------------------------------------------------
 * Timing
 * ---------------------------------------------------------------- */

static int l_get_time(lua_State *L) {
    lua_pushnumber(L, GetTime());
    return 1;
}

static int l_wait(lua_State *L) {
    double seconds = luaL_checknumber(L, 1);
    WaitTime(seconds);
    return 0;
}

/* ----------------------------------------------------------------
 * Module registration
 * ---------------------------------------------------------------- */

static const luaL_Reg turtleray_funcs[] = {
    /* Window */
    {"init_window",           l_init_window},
    {"close_window",          l_close_window},
    {"window_should_close",   l_window_should_close},
    {"get_screen_width",      l_get_screen_width},
    {"get_screen_height",     l_get_screen_height},
    {"set_target_fps",        l_set_target_fps},

    /* Drawing frame */
    {"begin_drawing",         l_begin_drawing},
    {"end_drawing",           l_end_drawing},
    {"clear",                 l_clear},

    /* Primitives */
    {"draw_line",             l_draw_line},
    {"draw_circle",           l_draw_circle},
    {"draw_circle_lines",     l_draw_circle_lines},
    {"draw_ring",             l_draw_ring},
    {"draw_sector",           l_draw_sector},
    {"draw_triangle_fill",    l_draw_triangle_fill},
    {"draw_polygon_fill",     l_draw_polygon_fill},
    {"draw_text",             l_draw_text},
    {"measure_text",          l_measure_text},

    /* Render texture (persistent canvas) */
    {"create_canvas",         l_create_canvas},
    {"begin_canvas",          l_begin_canvas},
    {"end_canvas",            l_end_canvas},
    {"draw_canvas",           l_draw_canvas},
    {"clear_canvas",          l_clear_canvas},
    {"resize_canvas",         l_resize_canvas},

    /* Input */
    {"is_key_pressed",        l_is_key_pressed},
    {"get_mouse_x",           l_get_mouse_x},
    {"get_mouse_y",           l_get_mouse_y},
    {"is_mouse_button_pressed", l_is_mouse_button_pressed},

    /* Timing */
    {"get_time",              l_get_time},
    {"wait",                  l_wait},

    {NULL, NULL}
};

int luaopen_turtleray(lua_State *L) {
    luaL_newlib(L, turtleray_funcs);

    /* Export some useful key constants */
    lua_pushinteger(L, KEY_ESCAPE); lua_setfield(L, -2, "KEY_ESCAPE");
    lua_pushinteger(L, KEY_SPACE);  lua_setfield(L, -2, "KEY_SPACE");
    lua_pushinteger(L, KEY_ENTER);  lua_setfield(L, -2, "KEY_ENTER");
    lua_pushinteger(L, KEY_UP);     lua_setfield(L, -2, "KEY_UP");
    lua_pushinteger(L, KEY_DOWN);   lua_setfield(L, -2, "KEY_DOWN");
    lua_pushinteger(L, KEY_LEFT);   lua_setfield(L, -2, "KEY_LEFT");
    lua_pushinteger(L, KEY_RIGHT);  lua_setfield(L, -2, "KEY_RIGHT");

    /* Mouse buttons */
    lua_pushinteger(L, MOUSE_BUTTON_LEFT);   lua_setfield(L, -2, "MOUSE_LEFT");
    lua_pushinteger(L, MOUSE_BUTTON_RIGHT);  lua_setfield(L, -2, "MOUSE_RIGHT");

    return 1;
}

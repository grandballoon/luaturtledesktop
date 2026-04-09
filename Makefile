# Makefile for turtleray — Raylib binding for Lua turtle graphics
#
# Usage:
#   make            — build turtleray.so
#   make clean      — remove build artifacts
#   make test       — run tests (core tests, no raylib needed)
#   make hello      — run the hello world example (needs raylib)

# Platform detection
UNAME := $(shell uname -s)

# Lua config
LUA_VERSION ?= 5.4
LUA ?= lua$(LUA_VERSION)

ifeq ($(UNAME),Darwin)
    # macOS / Homebrew
    LUA_INCDIR ?= /opt/homebrew/include/lua$(LUA_VERSION)
    LUA_LIBDIR ?= /opt/homebrew/lib
    RAYLIB_INCDIR ?= /opt/homebrew/include
    RAYLIB_LIBDIR ?= /opt/homebrew/lib
    SHARED_EXT = so
    SHARED_FLAGS = -shared -undefined dynamic_lookup
    PLATFORM_LIBS = -framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo
else ifeq ($(UNAME),Linux)
    # Linux
    LUA_INCDIR ?= /usr/include/lua$(LUA_VERSION)
    LUA_LIBDIR ?= /usr/lib
    RAYLIB_INCDIR ?= /usr/include
    RAYLIB_LIBDIR ?= /usr/lib
    SHARED_EXT = so
    SHARED_FLAGS = -shared
    PLATFORM_LIBS = -lGL -lm -lpthread -ldl -lrt -lX11
else
    # Windows (MinGW) — adjust paths as needed
    LUA_INCDIR ?= C:/lua54/include
    LUA_LIBDIR ?= C:/lua54/lib
    RAYLIB_INCDIR ?= C:/raylib/include
    RAYLIB_LIBDIR ?= C:/raylib/lib
    SHARED_EXT = dll
    SHARED_FLAGS = -shared
    PLATFORM_LIBS = -lopengl32 -lgdi32 -lwinmm
endif

CC ?= cc
CFLAGS = -O2 -fPIC -Wall -Wextra -I$(LUA_INCDIR) -I$(RAYLIB_INCDIR)
LDFLAGS = -L$(LUA_LIBDIR) -L$(RAYLIB_LIBDIR) -lraylib $(PLATFORM_LIBS)

TARGET = turtleray.$(SHARED_EXT)

.PHONY: all clean test hello

all: $(TARGET)

$(TARGET): turtleray.c
	$(CC) $(SHARED_FLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

test:
	cd . && $(LUA) tests/test_position.lua
	cd . && $(LUA) tests/test_pen.lua

hello: $(TARGET)
	$(LUA) examples/hello_raylib.lua

# Makefile for turtlecairo — Cairo + SDL2 binding for Lua turtle graphics
#
# Usage:
#   make            — build turtlecairo.so
#   make clean      — remove build artifacts
#   make test       — run core tests (no Cairo/SDL2 needed)
#   make square     — run the square example

# Platform detection
UNAME := $(shell uname -s)

# Lua config
LUA_VERSION ?= 5.4
LUA ?= lua$(LUA_VERSION)

ifeq ($(UNAME),Darwin)
    # macOS / Homebrew
    LUA_INCDIR   ?= /opt/homebrew/include/lua$(LUA_VERSION)
    LUA_LIBDIR   ?= /opt/homebrew/lib
    SHARED_EXT    = so
    SHARED_FLAGS  = -shared -undefined dynamic_lookup
    # Cairo and SDL2 via pkg-config
    PKG_CFLAGS   := $(shell pkg-config --cflags sdl2 cairo)
    PKG_LIBS     := $(shell pkg-config --libs   sdl2 cairo)
else ifeq ($(UNAME),Linux)
    # Linux
    LUA_INCDIR   ?= /usr/include/lua$(LUA_VERSION)
    LUA_LIBDIR   ?= /usr/lib
    SHARED_EXT    = so
    SHARED_FLAGS  = -shared
    PKG_CFLAGS   := $(shell pkg-config --cflags sdl2 cairo)
    PKG_LIBS     := $(shell pkg-config --libs   sdl2 cairo)
else
    # Windows (MinGW) — adjust paths as needed
    LUA_INCDIR   ?= C:/lua54/include
    LUA_LIBDIR   ?= C:/lua54/lib
    SHARED_EXT    = dll
    SHARED_FLAGS  = -shared
    PKG_CFLAGS    =
    PKG_LIBS      = -lSDL2 -lcairo
endif

CC     ?= cc
CFLAGS  = -O2 -fPIC -Wall -Wextra -I$(LUA_INCDIR) $(PKG_CFLAGS)
LDFLAGS = -L$(LUA_LIBDIR) $(PKG_LIBS)

TARGET = turtlecairo.$(SHARED_EXT)

.PHONY: all clean test square

all: $(TARGET)

$(TARGET): turtlecairo.c
	$(CC) $(SHARED_FLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET) turtleray.so

test:
	$(LUA) tests/test_position.lua
	$(LUA) tests/test_pen.lua
	$(LUA) tests/test_multiturtle.lua

square: $(TARGET)
	$(LUA) examples/square.lua

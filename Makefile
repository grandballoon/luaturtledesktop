# Makefile for turtlecairo — Cairo + SDL2 binding for Lua turtle graphics
#
# Usage:
#   make            — build turtlecairo.so and turtle_readline.so
#   make install    — install to LUA_SHAREDIR / LUA_LIBDIR / BINDIR
#   make clean      — remove build artifacts
#   make test       — run core tests (no Cairo/SDL2 needed)
#   make square     — run the square example
#
# Install path overrides (defaults use luarocks-compatible layout):
#   make install LUA_SHAREDIR=/usr/local/share/lua/5.4 \
#                LUA_LIBDIR=/usr/local/lib/lua/5.4    \
#                BINDIR=/usr/local/bin

# Platform detection
UNAME := $(shell uname -s)

# Lua config
LUA_VERSION ?= 5.4
LUA ?= lua$(LUA_VERSION)

ifeq ($(UNAME),Darwin)
    # macOS / Homebrew
    LUA_INCDIR        ?= /opt/homebrew/include/lua$(LUA_VERSION)
    LUA_LIBDIR        ?= /opt/homebrew/lib
    READLINE_INCDIR   ?= /opt/homebrew/opt/readline/include
    READLINE_LIBDIR   ?= /opt/homebrew/opt/readline/lib
    SHARED_EXT         = so
    SHARED_FLAGS       = -shared -undefined dynamic_lookup
    # Cairo and SDL2 via pkg-config
    PKG_CFLAGS        := $(shell pkg-config --cflags sdl2 cairo)
    PKG_LIBS          := $(shell pkg-config --libs   sdl2 cairo)
else ifeq ($(UNAME),Linux)
    # Linux
    LUA_INCDIR        ?= /usr/include/lua$(LUA_VERSION)
    LUA_LIBDIR        ?= /usr/lib
    READLINE_INCDIR   ?= /usr/include
    READLINE_LIBDIR   ?= /usr/lib
    SHARED_EXT         = so
    SHARED_FLAGS       = -shared
    PKG_CFLAGS        := $(shell pkg-config --cflags sdl2 cairo)
    PKG_LIBS          := $(shell pkg-config --libs   sdl2 cairo)
else
    # Windows (MinGW) — readline support deferred (see GOTCHAS.md)
    LUA_INCDIR        ?= C:/lua54/include
    LUA_LIBDIR        ?= C:/lua54/lib
    READLINE_INCDIR   ?=
    READLINE_LIBDIR   ?=
    SHARED_EXT         = dll
    SHARED_FLAGS       = -shared
    PKG_CFLAGS         =
    PKG_LIBS           = -lSDL2 -lcairo
endif

CC     ?= cc
CFLAGS  = -O2 -fPIC -Wall -Wextra -I$(LUA_INCDIR) $(PKG_CFLAGS)
LDFLAGS = -L$(LUA_LIBDIR) $(PKG_LIBS)

# readline flags (separate from Cairo/SDL2 so the cairo target stays clean)
READLINE_CFLAGS  = -I$(READLINE_INCDIR)
READLINE_LDFLAGS = -L$(READLINE_LIBDIR) -lreadline

TARGET          = turtlecairo.$(SHARED_EXT)
READLINE_TARGET = turtle_readline.$(SHARED_EXT)

# Install paths (override on command line)
LUA_SHAREDIR ?= $(shell $(LUA) -e "print(package.path:match('([^;]+/lua/$(LUA_VERSION))'))" 2>/dev/null || echo /usr/local/share/lua/$(LUA_VERSION))
LUA_CDIR     ?= $(shell $(LUA) -e "print(package.cpath:match('([^;]+/lua/$(LUA_VERSION))'))" 2>/dev/null || echo /usr/local/lib/lua/$(LUA_VERSION))
BINDIR       ?= /usr/local/bin

.PHONY: all clean test square repl install

all: $(TARGET) $(READLINE_TARGET)

$(TARGET): turtlecairo.c
	$(CC) $(SHARED_FLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(READLINE_TARGET): turtle_readline.c
	$(CC) $(SHARED_FLAGS) $(CFLAGS) $(READLINE_CFLAGS) -o $@ $< $(READLINE_LDFLAGS)

clean:
	rm -f $(TARGET) $(READLINE_TARGET) turtleray.so

test:
	$(LUA) tests/test_position.lua
	$(LUA) tests/test_pen.lua
	$(LUA) tests/test_multiturtle.lua

square: $(TARGET)
	$(LUA) examples/square.lua

repl: all
	$(LUA) -e 'require("turtle.repl").start()'

install: all
	install -d $(LUA_SHAREDIR)/turtle
	install -m 644 turtle.lua          $(LUA_SHAREDIR)/turtle.lua
	install -m 644 turtle/core.lua     $(LUA_SHAREDIR)/turtle/core.lua
	install -m 644 turtle/screen.lua   $(LUA_SHAREDIR)/turtle/screen.lua
	install -m 644 turtle/colors.lua   $(LUA_SHAREDIR)/turtle/colors.lua
	install -m 644 turtle/repl.lua     $(LUA_SHAREDIR)/turtle/repl.lua
	install -m 644 turtle/annotations.lua $(LUA_SHAREDIR)/turtle/annotations.lua
	install -d $(LUA_CDIR)
	install -m 755 $(TARGET)          $(LUA_CDIR)/$(TARGET)
	install -m 755 $(READLINE_TARGET) $(LUA_CDIR)/$(READLINE_TARGET)
	install -d $(BINDIR)
	install -m 755 luaturtle          $(BINDIR)/luaturtle

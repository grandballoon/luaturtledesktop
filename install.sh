#!/bin/sh
# install.sh — install Lua Turtle (Desktop) on macOS
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/grandballoon/luaturtledesktop/main/install.sh)"

set -e

echo "==> Installing dependencies via Homebrew..."
brew install lua luarocks sdl2 cairo readline

echo "==> Installing luaturtle via LuaRocks..."
luarocks install luaturtle \
    SDL2_DIR="$(brew --prefix sdl2)" \
    CAIRO_DIR="$(brew --prefix cairo)" \
    READLINE_DIR="$(brew --prefix readline)"

# Add luarocks path to shell profile if not already present
add_eval_line() {
    local profile="$1"
    local line='eval "$(luarocks path)"'
    if [ -f "$profile" ] && grep -qF 'luarocks path' "$profile"; then
        return
    fi
    echo "" >> "$profile"
    echo "# LuaRocks" >> "$profile"
    echo "$line" >> "$profile"
    echo "==> Added luarocks path to $profile"
}

if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
    add_eval_line "$HOME/.zshrc"
else
    add_eval_line "$HOME/.bash_profile"
fi

echo ""
echo "Done! Reload your shell, then try:"
echo ""
echo "  luaturtle          # start REPL"
echo "  lua myscript.lua   # run a script"
echo ""
echo "In any Lua script:"
echo ""
echo "  require('turtle')"
echo "  forward(100)"
echo "  done()"

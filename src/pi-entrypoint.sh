#!/bin/sh
# Registers globally-installed pi extensions with the user's pi profile
# on first run. We use local-path installs because the container's
# read-only root blocks `pi install npm:...` from rewriting
# /usr/local/lib/node_modules at runtime.
set -e

mkdir -p "$HOME/.pi/agent" "$HOME/.claude"

EXTENSIONS_MARKER="$HOME/.pi/agent/.extensions-registered"
if [ ! -f "$EXTENSIONS_MARKER" ]; then
    for ext in \
        /usr/local/lib/node_modules/@gotgenes/pi-anthropic-auth \
        /usr/local/lib/node_modules/pi-lens \
        /usr/local/lib/node_modules/pi-subagents \
        /usr/local/lib/node_modules/@juicesharp/rpiv-todo \
        /usr/local/lib/node_modules/@juicesharp/rpiv-web-tools \
        /usr/local/lib/node_modules/@casualjim/pi-superpowers
    do
        if [ -d "$ext" ]; then
            pi install "$ext" >/dev/null 2>&1 || true
        fi
    done
    : > "$EXTENSIONS_MARKER"
fi

exec pi "$@"

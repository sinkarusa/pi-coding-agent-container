#!/bin/sh
# Registers @gotgenes/pi-anthropic-auth with pi on first run so the
# Claude Pro/Max OAuth request-shaping is loaded automatically. The
# package is baked into the image via `npm install -g`; this only
# writes the per-profile registration that pi looks for in ~/.pi.
set -e

mkdir -p "$HOME/.pi/agent" "$HOME/.claude"

EXT_PATH="/usr/local/lib/node_modules/@gotgenes/pi-anthropic-auth"
MARKER="$HOME/.pi/agent/.anthropic-auth-registered"
# Register the globally-installed extension with pi via local-path install.
# We avoid `pi install npm:...` because the container's read-only root
# blocks npm from rewriting /usr/local/lib/node_modules at runtime.
if [ ! -f "$MARKER" ] && [ -d "$EXT_PATH" ]; then
    pi install "$EXT_PATH" >/dev/null 2>&1 || true
    : > "$MARKER"
fi

exec pi "$@"

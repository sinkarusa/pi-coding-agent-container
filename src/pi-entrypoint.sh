#!/bin/sh
# Registers globally-installed pi extensions with the user's pi profile
# on first run. We use local-path installs because the container's
# read-only root blocks `pi install npm:...` from rewriting
# /usr/local/lib/node_modules at runtime.
#
# pi-superpowers-plus and pi-subagents both register a tool named
# `subagent` and would conflict at load time. Standalone pi-subagents
# is the one with custom-agent discovery from .pi/agents/ — keep that
# one and disable pi-superpowers-plus's bundled copy via pi's
# per-resource filter syntax in settings.json.
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
        /usr/local/lib/node_modules/pi-superpowers-plus \
        /usr/local/lib/node_modules/@quintinshaw/pi-dynamic-workflows
    do
        if [ -d "$ext" ]; then
            pi install "$ext" >/dev/null 2>&1 || true
        fi
    done

    SETTINGS="$HOME/.pi/agent/settings.json"
    if [ -f "$SETTINGS" ]; then
        python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".pi/agent/settings.json"
data = json.loads(p.read_text())
pkgs = data.get("packages", [])
for i, entry in enumerate(pkgs):
    src = entry if isinstance(entry, str) else entry.get("source", "")
    if src.endswith("pi-superpowers-plus"):
        pkgs[i] = {"source": src, "extensions": ["-extensions/subagent/index.ts"]}
data["packages"] = pkgs
p.write_text(json.dumps(data, indent=2) + "\n")
PY
    fi

    : > "$EXTENSIONS_MARKER"
fi

exec pi "$@"

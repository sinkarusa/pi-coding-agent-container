#!/bin/sh
# Container entrypoint for the pi coding agent.
# Bootstraps extensions, pi settings, and search provider defaults, then
# hands off to pi. Each concern lives in its own named function so new
# init steps can be added without reading the existing ones.
set -e

# ---------------------------------------------------------------------------
# 1. Register globally-installed pi extensions (once per data volume).
#    We use local-path installs because the container's read-only root
#    blocks `pi install npm:...` from rewriting /usr/local/lib/node_modules.
# ---------------------------------------------------------------------------
register_extensions() {
	mkdir -p "$HOME/.pi/agent" "$HOME/.claude"

	# Build EXTS from the canonical extension list (single source of truth shared
	# with Dockerfile). Each line is `name@version` (or a bare `name`); npm uses
	# the version to pin the install, but the on-disk module dir is unversioned,
	# so strip a trailing @version before forming the path. The stripped `@` is
	# the rightmost one past index 1, leaving a scoped name's leading @scope intact.
	EXTS="$(awk '{
		name = $1
		at = 0
		for (i = length(name); i > 1; i--) {
			if (substr(name, i, 1) == "@") { at = i; break }
		}
		if (at > 1) name = substr(name, 1, at - 1)
		print "/usr/local/lib/node_modules/" name
	}' /usr/local/lib/extensions.txt | tr '\n' ' ') /usr/local/lib/node_modules/mattpocock-skills"

	EXTENSIONS_MARKER="$HOME/.pi/agent/.extensions-registered"
	CURRENT_HASH=$(echo "$EXTS" | sha256sum | cut -d' ' -f1)
	STORED_HASH=$(cat "$EXTENSIONS_MARKER" 2>/dev/null || echo "")

	if [ "$CURRENT_HASH" != "$STORED_HASH" ]; then
		# Reset the packages list before re-registering so removed extensions
		# don't persist across rebuilds.
		python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".pi/agent/settings.json"
data = json.loads(p.read_text()) if p.exists() else {}
data["packages"] = []
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2) + "\n")
PY
		for ext in $EXTS; do
			if [ -d "$ext" ]; then
				pi install "$ext" >/dev/null 2>&1 || echo "[warn] failed to register $ext" >&2
			fi
		done
		echo "$CURRENT_HASH" >"$EXTENSIONS_MARKER"
	fi
}

# ---------------------------------------------------------------------------
# 2. Patch pi models.json on every start (idempotent):
#    - Route all LLM inference through the credential-proxy sidecar so real
#      API keys never enter this container's address space.
#
#    Provider overrides (baseUrl/apiKey) are read from models.json, NOT
#    settings.json — pi's ModelRegistry loads them from ~/.pi/agent/models.json
#    (see config.getModelsJsonPath / model-registry.loadCustomModels). Writing
#    them to settings.json is silently ignored, so requests fall back to the
#    built-in upstreams (api.anthropic.com, openrouter.ai, …) with the "proxy"
#    placeholder as the key and fail with 401s.
#
#    apiKey "proxy" is the placeholder the credential-proxy swaps for the real
#    key. For Anthropic OAuth (Pro/Max) the access token from auth.json takes
#    precedence over this placeholder, and the proxy passes it through untouched.
# ---------------------------------------------------------------------------
patch_pi_settings() {
	python3 - <<'PY'
import json, pathlib

agent = pathlib.Path.home() / ".pi/agent"
agent.mkdir(parents=True, exist_ok=True)

models = agent / "models.json"
data = json.loads(models.read_text()) if models.exists() else {}

data["providers"] = {
    "anthropic":  {"baseUrl": "http://credential-proxy:8080/anthropic",          "apiKey": "proxy"},
    "openai":     {"baseUrl": "http://credential-proxy:8080/openai/v1",          "apiKey": "proxy"},
    "openrouter": {"baseUrl": "http://credential-proxy:8080/openrouter/api/v1",  "apiKey": "proxy"},
}

models.write_text(json.dumps(data, indent=2) + "\n")

# Drop the stale providers block from settings.json (it was never read there).
settings = agent / "settings.json"
if settings.exists():
    s = json.loads(settings.read_text())
    if s.pop("providers", None) is not None:
        settings.write_text(json.dumps(s, indent=2) + "\n")
PY
}

# ---------------------------------------------------------------------------
# 3. Install bundled TUI themes and make "darker" the default.
#    Themes are copied from the image (/usr/local/lib/themes, outside the
#    mounted volume) into $HOME/.pi/agent/themes on every start so image
#    rebuilds always ship the latest palette. The default theme is only set
#    when the user hasn't already chosen one, so a manual /settings pick or an
#    explicit "theme" in settings.json is never overwritten.
# ---------------------------------------------------------------------------
install_themes() {
	if [ -d /usr/local/lib/themes ]; then
		mkdir -p "$HOME/.pi/agent/themes"
		cp -f /usr/local/lib/themes/*.json "$HOME/.pi/agent/themes/" 2>/dev/null || true
	fi

	python3 - <<'PY'
import json, pathlib

p = pathlib.Path.home() / ".pi/agent/settings.json"
data = json.loads(p.read_text()) if p.exists() else {}
if not data.get("theme"):
    data["theme"] = "darker"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2) + "\n")
PY
}

# ---------------------------------------------------------------------------
# 4. Set the web search provider to SearXNG on every start.
#    /home/node/.config is a tmpfs (wiped on restart) so the default is
#    always written; interactive /web-tools overrides persist for the session.
# ---------------------------------------------------------------------------
default_search_provider() {
	python3 - <<'PY'
import json, pathlib

p = pathlib.Path.home() / ".config/rpiv-web-tools/config.json"
p.parent.mkdir(parents=True, exist_ok=True)

data = {"provider": "searxng"}
p.write_text(json.dumps(data, indent=2) + "\n")
PY
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
register_extensions
patch_pi_settings
install_themes
default_search_provider

exec pi "$@"

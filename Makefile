.PHONY: build run clean shell setup

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

export PARANOID_MODE ?= true
RANDOM_ID := $(shell openssl rand -hex 6 2>/dev/null || echo "default")
export SECRET_TARGET_PATH = /run/secrets/gh_$(RANDOM_ID)

WORKSPACE_DIR ?= $(PWD)/workspace
export WORKSPACE_DIR

setup:
	mkdir -p .pi-data .secrets .claude-data workspace src
	chmod 700 .pi-data .secrets .claude-data workspace
	touch .claude-data/.claude.json
	chmod 600 .claude-data/.claude.json
	@chmod 600 .secrets/github_token.txt 2>/dev/null || true
	touch .secrets/github_token.txt
	chmod 600 .secrets/github_token.txt
	@if [ -f .env ]; then grep "^GITHUB_TOKEN=" .env | cut -d '=' -f2- > .secrets/github_token.txt; fi
	chmod 000 .secrets/github_token.txt
	@python3 -c "\
import json, pathlib; \
p = pathlib.Path('.pi-data/agent/auth.json'); \
auth = json.loads(p.read_text()) if p.exists() else {}; \
cleaned = {k: v for k, v in auth.items() if isinstance(v, dict) and v.get('type') != 'api_key'}; \
changed = len(auth) - len(cleaned); \
(p.write_text(json.dumps(cleaned, indent=2) + '\n'), print(f'[setup] removed {changed} raw API key(s) from auth.json (OAuth entries kept)')) if changed else None"

build: setup
	docker compose build

update: setup
	docker compose build --no-cache

run: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose run --rm pi-agent

run-args: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose run --rm pi-agent $(args)

run-with-db: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose -f docker-compose.yml -f docker-compose.db.yml run --rm pi-agent

shell: setup
	HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose run --entrypoint /bin/bash --rm pi-agent

clean:
	docker compose down

## Show which LLM providers are configured in .env
providers:
	@echo "Configured LLM providers (via credential-proxy):"
	@python3 -c "\
import pathlib; \
lines = pathlib.Path('.env').read_text().splitlines() if pathlib.Path('.env').exists() else []; \
env = dict(l.split('=', 1) for l in lines if '=' in l and not l.startswith('#')); \
pairs = [('anthropic', 'ANTHROPIC_API_KEY'), ('openai', 'OPENAI_API_KEY'), ('openrouter', 'OPENROUTER_API_KEY'), ('github', 'GITHUB_TOKEN')]; \
found = [name for name, var in pairs if env.get(var, '').strip()]; \
print('  ' + ', '.join(found) if found else '  (none — add keys to .env and make run)')"

## Show help
help:
	@echo ""
	@echo "  make build       build the image"
	@echo "  make run         start pi"
	@echo "  make run-args    pass args to pi  (e.g. make args='--version' run-args)"
	@echo "  make shell       open a shell in the container"
	@echo "  make providers   show active LLM providers"
	@echo "  make clean       stop containers"
	@echo "  make update      force rebuild without cache"
	@echo ""
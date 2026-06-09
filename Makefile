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
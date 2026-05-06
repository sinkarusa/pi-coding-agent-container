# pi coding agent (dockerized)

Almost secure, containerized environment for running the [pi coding agent](https://github.com/badlogic/pi-mono). Designed for local execution with strict file-system isolation, privilege drop, and persistent storage.

## Quick Start

**1. Configuration**
```bash
cp .env.example .env
# Edit .env with your GitHub token and Git identity
```

**2. Build**
Compiles the image from source and strips OS privilege escalation binaries.
```bash
make build
```

**3. Run**
Starts the agent in interactive TUI mode.
```bash
make run
```

---

## Usage

**Passing Arguments**
Use the `run-args` target to pass specific flags, commands, or one-off prompts to the agent.
```bash
# Check version
make args="--version" run-args

# Trigger Copilot authentication
make args="/login" run-args

# Execute a direct prompt
make args="'Create a snake game in python'" run-args
```

**Claude Pro / Max as a pi provider (via `pi-anthropic-auth`)**
The image bakes in [`@gotgenes/pi-anthropic-auth`](https://github.com/gotgenes/pi-anthropic-auth), a pi extension that reshapes pi's Anthropic requests so they pass Anthropic's first-party classifier. Combined with pi's native `/login anthropic` flow, this lets you use Claude Opus / Sonnet / Haiku as a pi provider on your Pro or Max subscription. The extension is auto-registered on first launch.


```bash
make run                 # start pi
/login anthropic         # open the printed URL on host, paste the code back
/model                   # pick a Claude model — extension auto-shapes the request
```

Pi's Anthropic OAuth session is written to `~/.pi/agent/auth.json` and persisted via the bound `./.pi-data/` volume, so subsequent runs reuse the login. To verify the extensions actually loaded after first run, check the `packages` array in `./.pi-data/agent/settings.json`.

**Bundled pi extensions**

The image bakes in a curated extension set so pi behaves more like Claude Code out of the box. All are registered automatically on first launch via local-path `pi install` (the container's read-only root blocks `pi install npm:…` at runtime, so we install via npm globally at build time and register at runtime).

| Extension | What it adds |
|---|---|
| [`@gotgenes/pi-anthropic-auth`](https://github.com/gotgenes/pi-anthropic-auth) | Reshapes Anthropic requests so Pro/Max OAuth subscriptions work |
| [`pi-lens`](https://www.npmjs.com/package/pi-lens) | LSP, linters, formatters, type-checking — real-time code feedback |
| [`pi-subagents`](https://www.npmjs.com/package/pi-subagents) | Parallel sub-agent delegation (Claude Code's `Task` tool equivalent) |
| [`@juicesharp/rpiv-todo`](https://www.npmjs.com/package/@juicesharp/rpiv-todo) | Live TODO overlay that survives `/reload` and compaction |
| [`@juicesharp/rpiv-web-tools`](https://www.npmjs.com/package/@juicesharp/rpiv-web-tools) | Web search + fetch (Brave Search backend) |
| [`@casualjim/pi-superpowers`](https://github.com/casualjim/pi-superpowers) | obra's Superpowers methodology adapted for pi — Brainstorm → Plan → Execute → Verify → Review → Finish workflow guardrails |

Pi has no native permission system — every tool call runs without prompts. That's the equivalent of Claude Code's `--dangerously-skip-permissions`, on by default. If you ever want approval gating, install [`@gotgenes/pi-permission-system`](https://www.npmjs.com/package/@gotgenes/pi-permission-system).

**Working on a repo outside this directory**
Set `WORKSPACE_DIR` to any host path; the container mounts it at `/workspace`. Files are owned by your host UID, so `git`/`gh` Just Work.
```bash
# One-shot
make run WORKSPACE_DIR=/home/me/Repos/my-other-project

# Or export once for the shell session
export WORKSPACE_DIR=/home/me/Repos/my-other-project
make run
```
Default (`./workspace`) is used if unset.

> **First-run gotchas when pointing at an existing project**
>
> The container has `python3.11`, `uv`, `node 22`, `git`, `gh`, `gcc`, `build-essential`. Anything else has to be installed inside `/workspace` (the only writable, executable location your tools see).
>
> 1. **Stale virtualenv.** A `.venv/` created on your host points at host-Python paths that don't exist inside the container. On first session, tell the agent: *"Delete `.venv/` and re-run `uv sync` — the existing one was built outside the container."*
> 2. **Caches/state outside the workspace will silently fail.** The container is `read_only: true` everywhere except `/workspace`, the named volumes (`/home/node/.pi`, `/home/node/.claude`), and a few tmpfs mounts. Any code that writes to `~/.config/<app>/`, `~/.local/share/<app>/`, `~/.<app>/`, etc. will hit `EROFS`. Tell the agent: *"Move any user-home cache the project uses (e.g., `~/.foo/`) into the project (e.g., `./.foo-cache/`) and gitignore it."*
> 3. **Built artifacts in `/tmp` won't run.** `/tmp` is `tmpfs` with `noexec` (anti-compilation guard). Builds must produce binaries inside `/workspace` (or `node_modules`/`.venv`, both of which live there).
> 4. **Hosting an HTTP server on the host browser.** No ports are mapped by default. To expose port `3000`, add to `docker-compose.yml`:
>    ```yaml
>    ports:
>      - "3000:3000"
>    ```
> 5. **Reaching a service on your host machine.** From inside the container, `localhost` is the *container*. To reach a host service, add to `docker-compose.yml` under the service:
>    ```yaml
>    extra_hosts:
>      - "host.docker.internal:host-gateway"
>    ```
>    then connect to `http://host.docker.internal:<port>`.

**Suggested first prompt to the agent on a new project**
```
This repo is mounted at /workspace. The container is read-only outside
/workspace. Before running anything else:
  1. Delete .venv if present and run `uv sync` to rebuild against the
     container's Python 3.11.
  2. If the project caches anything under ~/ (e.g., ~/.<name>/), relocate
     it into ./.cache/ or similar inside the workspace and gitignore it.
Then read README.md and PRD.md (or equivalent) and continue from where
the project left off.
```

**Maintenance & Debugging**
```bash
# Access the container shell (runs as user 1000)
make shell

# Stop and remove running containers/networks
make clean

# Force rebuild the image without cache
make update
```

---

## Offline Mode (llama.cpp)

To run the agent completely offline using local models, configure the following files in your `.pi-data/agent/` directory:

**.pi-data/agent/models.json**
```json
{
  "providers": {
    "llama-cpp": {
      "baseUrl": "http://127.0.0.1:1337/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "models": [
        {
          "id": "gemma-4-26B-A4B-it-GGUF"
        }
      ]
    }
  }
}
```

**.pi-data/agent/settings.json**
```json
{
  "defaultProvider": "llama-cpp",
  "defaultModel": "gemma-4-26B-A4B-it-GGUF",
  "autocompleteMaxVisible": 7,
  "defaultThinkingLevel": "off"
}
```

---

## 🔒 Security Architecture & Paranoid Mode

This container implements a defense-in-depth architecture to sandbox the AI agent, ensuring it cannot leak credentials, modify its own access limits, or escalate privileges on your host machine.

### 1. Paranoid Mode (Active by Default)
The container uses a guardrail wrapper (`gh-guard.sh`) around the GitHub CLI. When `PARANOID_MODE=true` (set in `.env`), the agent is strictly blocked from executing dangerous repository or identity commands:
* **Blocked:** `gh auth`, `gh repo`, `gh secret`, `gh ssh-key`, `gh gpg-key`.
* This prevents a rogue agent from injecting a persistent backdoor key into your GitHub account.

### 2. The Micro-Vault (Token Isolation)
Your `GITHUB_TOKEN` is **never** exposed in environment variables where the agent can read it via `process.env`.
* The token is mapped as a Docker Secret into RAM (`tmpfs`) and locked to host permissions `000`.
* The container runs as a standard user (`UID 1000`).
* A custom C binary (`gh-vault`) uses SetUID to briefly elevate to root, read the token, pass it to the GitHub CLI, and immediately drop privileges. The agent natively receives `Permission Denied` if it attempts to read the file.

### 3. Dual Execution Firewalls
To prevent the agent from reading your Copilot `auth.json` or `.env` files, we implemented firewalls at both the OS and Application layers:
* **OS Syscall Firewall (`LD_PRELOAD`):** A custom C library (`fs-vault.so`) intercepts `open()` and `fopen()` syscalls at the Linux kernel level. If the agent spawns native child processes (like `cat`, `grep`, or `python`) to snoop on config directories, the kernel forces an `EACCES` permission error.
* **V8 Application Firewall:** A Node.js monkeypatch (`app-firewall.js`) intercepts the internal `fs` module. It analyzes the execution stack trace in real-time. If a file read/write request originates from the AI agent's tool directory, it throws a hard `[SYSTEM BLOCK]`. It only allows the core application (like the `/login` prompt) to touch credentials.

### 4. OS Binary Purge
During the Docker build phase, all native Linux privilege escalation vectors are physically deleted from the image:
* Removed: `su`, `mount`, `passwd`, `chsh`, `login`, `newgrp`, `unshare`, etc.
* The SetUID/SetGID execution bits are globally stripped (`chmod a-s`) from all remaining binaries on the filesystem.

### 5. Safe Persistence & Writable Space
* **UID/GID Mapping:** The `Makefile` dynamically passes your host User ID and Group ID into the container. Any files the agent writes to the `./workspace` mount will be owned by your host user, preventing root permission lockouts.
* **Anti-Compilation:** Writable temporary directories (`/tmp`, `/.npm`, `/.config`) are mounted using `tmpfs` with the `noexec` flag. This prevents the agent from downloading and executing statically compiled binaries to bypass the `LD_PRELOAD` firewall.


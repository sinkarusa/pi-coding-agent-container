# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim@sha256:813a7480f28fdadac1f7f5c824bcdad435b5bc1322a5968bbbdef8d058f9dff4 AS base

ENV NODE_ENV=production
ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_LOGLEVEL=warn

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    procps \
    build-essential \
    python3 \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# System Hardening: Purge Privilege Escalation Vectors
# -----------------------------------------------------------------------------
RUN rm -f /bin/su /usr/bin/su /bin/mount /usr/bin/mount /bin/umount /usr/bin/umount \
    /usr/bin/passwd /usr/bin/chsh /usr/bin/chfn /usr/bin/chage /usr/bin/gpasswd \
    /usr/bin/newgrp /bin/login /usr/bin/login /usr/bin/nsenter /usr/bin/unshare \
    /usr/bin/setpriv /bin/setpriv \
    && find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -exec chmod a-s {} + || true

RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# The GitHub CLI Guardrail & Vault
# -----------------------------------------------------------------------------
COPY src/gh-guard.sh /usr/local/bin/gh-guard
RUN chmod +x /usr/local/bin/gh-guard

COPY src/gh-vault.c /tmp/gh-vault.c
RUN gcc -O2 /tmp/gh-vault.c -o /usr/local/bin/gh \
    && chown root:root /usr/local/bin/gh \
    && chmod 4755 /usr/local/bin/gh \
    && rm /tmp/gh-vault.c

# -----------------------------------------------------------------------------
# The Global Syscall Firewall (LD_PRELOAD) - Blocks Child Processes
# -----------------------------------------------------------------------------
COPY src/fs-vault.c /tmp/fs-vault.c
RUN gcc -shared -fPIC -O2 /tmp/fs-vault.c -o /usr/local/lib/fs-vault.so -ldl \
    && rm /tmp/fs-vault.c \
    && echo "/usr/local/lib/fs-vault.so" > /etc/ld.so.preload

# -----------------------------------------------------------------------------
# Comprehensive Application-Layer Firewall (V8 Hook)
# -----------------------------------------------------------------------------
COPY src/app-firewall.js /usr/local/lib/app-firewall.js

# Force Node.js to load the firewall before initializing the agent
ENV NODE_OPTIONS="--require /usr/local/lib/app-firewall.js"
ENV UV_PYTHON_PREFERENCE=only-system

FROM base AS release

COPY --from=ghcr.io/astral-sh/uv:latest@sha256:3d868e555f8f1dbc324afa005066cd11e1053fc4743b9808ca8025283e65efa5 /uv /uvx /usr/local/bin/

# -----------------------------------------------------------------------------
# pi-lens tools — linters and formatters used by the coding agent
# -----------------------------------------------------------------------------

# shfmt — shell script formatter
RUN curl -fsSL "https://github.com/mvdan/sh/releases/download/v3.13.1/shfmt_v3.13.1_linux_amd64" \
    -o /usr/local/bin/shfmt && chmod +x /usr/local/bin/shfmt

# hadolint — Dockerfile linter
RUN curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v2.14.0/hadolint-linux-x86_64" \
    -o /usr/local/bin/hadolint && chmod +x /usr/local/bin/hadolint

# actionlint — GitHub Actions linter
RUN curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin actionlint

# gitleaks — secret scanner
RUN curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks

# ruff, yamllint, mypy — Python linting and type checking
# UV_TOOL_BIN_DIR puts the executables in /usr/local/bin so node user can find them
RUN UV_TOOL_BIN_DIR=/usr/local/bin uv tool install ruff \
    && UV_TOOL_BIN_DIR=/usr/local/bin uv tool install yamllint \
    && UV_TOOL_BIN_DIR=/usr/local/bin uv tool install mypy

COPY src/extensions.txt /usr/local/lib/extensions.txt

# Bundled TUI themes — installed into $HOME/.pi/agent/themes by the entrypoint
# (kept outside the mounted volume so image rebuilds ship the latest copy).
COPY src/themes/ /usr/local/lib/themes/

# Infrastructure packages (pi agent core + dev tools — not pi extensions)
RUN npm install -g \
    @earendil-works/pi-coding-agent@0.80.6 \
    @earendil-works/pi-ai@0.80.6 \
    @earendil-works/pi-tui@0.80.6 \
    @anthropic-ai/claude-code \
    typebox \
    yaml \
    jiti \
    @standard-schema/spec \
    typescript \
    typescript-language-server \
    pyright

# Extension packages — canonical list is /usr/local/lib/extensions.txt
# (kept in image so entrypoint can read at runtime)
RUN xargs npm install -g < /usr/local/lib/extensions.txt

RUN mkdir -p /home/node/.pi/agent \
    /home/node/.claude \
    /workspace \
    /home/node/.config \
    /home/node/.npm && \
    chown -R node:node /home/node/.pi \
    /home/node/.claude \
    /workspace \
    /home/node/.config \
    /home/node/.npm

# Pull mattpocock/skills from GitHub and patch package.json so pi can discover it
# (upstream is private:true and lacks the pi.skills field)
RUN git clone --filter=blob:none --no-checkout https://github.com/mattpocock/skills.git /tmp/mattpocock-skills \
    && git -C /tmp/mattpocock-skills checkout 5d78bd0903420f97c791f834201e550c765699f8 \
    && node -e "\
      const fs = require('fs'); \
      const p = JSON.parse(fs.readFileSync('/tmp/mattpocock-skills/package.json','utf8')); \
      delete p.private; \
      p.pi = { skills: ['skills'] }; \
      fs.writeFileSync('/tmp/mattpocock-skills/package.json', JSON.stringify(p, null, 2)); \
    " && \
    find /tmp/mattpocock-skills/skills -name 'SKILL.md' \
      -exec sed -i 's/^name: /name: mp-/' {} \; && \
    cp -r /tmp/mattpocock-skills /usr/local/lib/node_modules/mattpocock-skills && \
    rm -rf /tmp/mattpocock-skills

COPY src/pi-entrypoint.sh /usr/local/bin/pi-entrypoint
RUN chmod 0755 /usr/local/bin/pi-entrypoint

WORKDIR /workspace

USER node

# Force Git to use the secure CLI as its credential helper.
RUN git config --global credential.https://github.com.helper "" && \
    git config --global credential.https://github.com.helper "!/usr/bin/gh auth git-credential"

ENTRYPOINT ["/usr/local/bin/pi-entrypoint"]
CMD []

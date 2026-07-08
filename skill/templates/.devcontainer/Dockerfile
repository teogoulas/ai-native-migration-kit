# Baseline devcontainer image for AI-native repos.
#
# Deliberately stack-neutral — pre-installs only tools every AI-native repo
# benefits from (git, python for pre-commit, jq for the deterministic
# verifier). Add stack-specific installs in the block marked below.
#
# The bootstrap.sh script detects the target's stack and can suggest stack-
# specific FROM images (mcr.microsoft.com/devcontainers/{python,java,go,rust,...})
# during the interactive flow. If unsure, ubuntu-24.04 works for everything —
# just slower on first build.

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Baseline: tools every AI-native repo benefits from.
#   - git & git-lfs — checkout, symlink handling, LFS assets
#   - python3-pip   — required by pre-commit (the framework, not the hooks)
#   - jq            — required by ai-native-verify's JSON pipeline
#   - curl, ca-certificates — general-purpose bootstrap
#   - shellcheck    — lint the onboarding scripts themselves
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      git-lfs \
      python3-pip \
      python3-venv \
      jq \
      curl \
      ca-certificates \
      shellcheck \
    && rm -rf /var/lib/apt/lists/*

# pre-commit installed globally so any user in the container can invoke it.
RUN pip3 install --break-system-packages --no-cache-dir pre-commit

# ─────────────────────────────────────────────────────────────────────────
# STACK-SPECIFIC INSTALLS
# Add commands to install the target's language runtime, package manager,
# and test framework below. Examples:
#
#   # Node.js (Next.js, React, etc.)
#   RUN curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME=/usr/local/bin sh -
#
#   # Java + Maven
#   RUN apt-get install -y --no-install-recommends default-jdk maven
#
#   # Python via uv
#   RUN pip install --break-system-packages uv
#
#   # Go
#   RUN curl -L https://go.dev/dl/go1.23.0.linux-amd64.tar.gz | tar -C /usr/local -xz
#   ENV PATH="/usr/local/go/bin:${PATH}"
#
#   # Rust
#   RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
#
# Delete this block if the baseline is sufficient (e.g., a docs-only repo).
# ─────────────────────────────────────────────────────────────────────────

# Ensure the non-root user (created by the base image) has ownership of any
# volume-mounted workspace. The devcontainer.json's remoteUser=vscode picks
# this up.
USER vscode

#!/usr/bin/env bash
# setup-precommit.sh — activate the committed pre-commit hooks on a fresh clone.
#
# The rubric ships this together with .pre-commit-config.yaml because a
# committed config is inert until this runs (§Part 1 D18). Do not delete
# this script and leave the config — the pair only works together.
#
# Safe to run repeatedly; every step is idempotent.

set -euo pipefail

BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'
[[ -t 1 ]] || { BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""; }

log()  { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die()  { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────
# Preflight: verify we're in a repo with a config to activate.
# ─────────────────────────────────────────────────────────────────────────

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || die "not inside a git repository — cd into your project root and re-run"
cd "$REPO_ROOT"

if [[ ! -f .pre-commit-config.yaml && ! -f .pre-commit-config.yml ]]; then
  die ".pre-commit-config.yaml missing at $REPO_ROOT — nothing to activate"
fi

# ─────────────────────────────────────────────────────────────────────────
# Step 1: ensure the pre-commit framework itself is installed.
# ─────────────────────────────────────────────────────────────────────────

if command -v pre-commit >/dev/null 2>&1; then
  log "✓ pre-commit already installed ($(pre-commit --version))"
else
  log "→ installing pre-commit via pip3"
  if ! command -v pip3 >/dev/null 2>&1; then
    die "pip3 is required to install pre-commit — install Python 3 first"
  fi
  # --user keeps this out of any system-managed packages; --break-system-packages
  # is needed on newer Python installs (PEP 668) if not using --user in a venv.
  pip3 install --user pre-commit 2>/dev/null \
    || pip3 install --user --break-system-packages pre-commit \
    || die "pip3 install pre-commit failed — try 'pipx install pre-commit'"

  # Make sure the user bin is on PATH for the rest of this script.
  export PATH="$HOME/.local/bin:$PATH"
  command -v pre-commit >/dev/null 2>&1 \
    || die "pre-commit installed but not on PATH — add \$HOME/.local/bin to your shell profile"
fi

# ─────────────────────────────────────────────────────────────────────────
# Step 2: install the commit and commit-msg hooks.
# ─────────────────────────────────────────────────────────────────────────

log "→ installing pre-commit hook"
pre-commit install

log "→ installing commit-msg hook (Conventional Commits enforcement)"
pre-commit install --hook-type commit-msg

# Optionally: pre-push hook. Enable if the config has stages: [push] hooks.
if grep -qE 'stages:.*\bpush\b' .pre-commit-config.y*ml 2>/dev/null; then
  log "→ installing pre-push hook (config has push-stage hooks)"
  pre-commit install --hook-type pre-push
fi

# ─────────────────────────────────────────────────────────────────────────
# Step 3: run every hook against every file to establish a clean baseline.
# ─────────────────────────────────────────────────────────────────────────

log "→ running all hooks against all files (initial baseline)"
if pre-commit run --all-files; then
  log ""
  log "${BOLD}✓ pre-commit setup complete${RESET}"
  log ""
  log "  Hooks are now active. Every 'git commit' runs them automatically."
  log "  To run manually:      pre-commit run --all-files"
  log "  To bump hook versions: pre-commit autoupdate"
  log ""
else
  warn ""
  warn "⚠ some hooks failed on the initial run — fix the reported issues, then re-run:"
  warn ""
  warn "    pre-commit run --all-files"
  warn ""
  warn "  The hooks ARE installed and will fire on 'git commit'. This step just"
  warn "  verified the current tree is clean; a first-time repo often needs a"
  warn "  cleanup pass before it is."
  exit 1
fi

#!/usr/bin/env bash
# install.sh — symlink skill/ into ~/.claude/skills/ai-native-migration/.
#
# After running this, Claude Code sees the ai-native-migration skill on
# its next session and /ai-native-migration is invokable.
#
# Idempotent: re-run any time to refresh the symlink. Never modifies your
# clone — it only creates/updates ONE symlink under ~/.claude/skills/.

set -euo pipefail

BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
DIM=$'\033[90m'
RESET=$'\033[0m'
[[ -t 1 ]] || { BOLD=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""; }

log()  { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die()  { printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

_resolve_dir() {
  local src=$1
  while [[ -L $src ]]; do
    local dir; dir=$(cd -P "$(dirname "$src")" && pwd)
    src=$(readlink "$src"); [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

KIT_ROOT=$(_resolve_dir "${BASH_SOURCE[0]}")
readonly KIT_ROOT

usage() {
  cat <<EOF
install.sh — install ai-native-migration-kit into ~/.claude/skills/

Usage:
  install.sh [--uninstall] [--user-scope=<path>] [--force]

Options:
  --user-scope=<path>   Override ~/.claude/skills/. Default: \$HOME/.claude/skills/
  --uninstall           Remove the existing symlink and exit.
  --force               Overwrite an existing symlink or directory at the
                        install path without asking.
  --help                Print this message and exit.

What it does:
  1. Verifies dependencies (bash, git, jq, python3-recommended).
  2. Creates ~/.claude/skills/ai-native-migration/ as a symlink to $KIT_ROOT/skill.
  3. Verifies the install with a post-install self-test.

Uninstalling:
  install.sh --uninstall
EOF
}

USER_SCOPE=""
UNINSTALL=0
FORCE=0

while (( $# > 0 )); do
  case $1 in
    --help|-h)          usage; exit 0 ;;
    --user-scope=*)     USER_SCOPE=${1#--user-scope=} ;;
    --user-scope)       shift; USER_SCOPE=${1:-} ;;
    --uninstall)        UNINSTALL=1 ;;
    --force)            FORCE=1 ;;
    *)                  die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

# Default install location.
SKILLS_DIR=${USER_SCOPE:-"$HOME/.claude/skills"}
INSTALL_PATH="$SKILLS_DIR/ai-native-migration"

# ─────────────────────────────────────────────────────────────────────────
# Uninstall short-circuit
# ─────────────────────────────────────────────────────────────────────────

if (( UNINSTALL )); then
  if [[ -L $INSTALL_PATH ]]; then
    rm "$INSTALL_PATH"
    log "✓ removed symlink at $INSTALL_PATH"
    exit 0
  fi
  if [[ -e $INSTALL_PATH ]]; then
    warn "$INSTALL_PATH exists but is NOT a symlink — refusing to delete"
    warn "  If you want to remove it anyway: rm -rf '$INSTALL_PATH'"
    exit 1
  fi
  log "· nothing to uninstall (no symlink at $INSTALL_PATH)"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────
# Preflight: dependency check
# ─────────────────────────────────────────────────────────────────────────

printf '%sInstalling ai-native-migration-kit%s\n' "$BOLD" "$RESET"
printf '%s  from:  %s%s\n' "$DIM" "$KIT_ROOT" "$RESET"
printf '%s  to:    %s%s\n\n' "$DIM" "$INSTALL_PATH" "$RESET"

check_dep() {
  local cmd=$1
  local required=${2:-required}
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  %s✓%s %-12s %s%s%s\n' "$GREEN" "$RESET" "$cmd" "$DIM" "$($cmd --version 2>&1 | head -n1)" "$RESET"
    return 0
  fi
  if [[ $required == "required" ]]; then
    printf '  %s✗%s %-12s MISSING (required)\n' "$RED" "$RESET" "$cmd"
    return 1
  fi
  printf '  %s·%s %-12s missing (%s)\n' "$YELLOW" "$RESET" "$cmd" "$required"
  return 0
}

log "Dependency check:"
missing=0
check_dep bash     required   || (( ++missing ))
check_dep git      required   || (( ++missing ))
check_dep jq       required   || (( ++missing ))
check_dep python3  "recommended for JSON validity checks; a naive-grep fallback runs when python3 is absent"
check_dep node     "required for the workflow tests only — skippable if you never run tests/all.sh"

if (( missing > 0 )); then
  die "$missing required dependency(ies) missing — install them and re-run"
fi
printf '\n'

# ─────────────────────────────────────────────────────────────────────────
# Ensure ~/.claude/skills/ exists
# ─────────────────────────────────────────────────────────────────────────

if [[ ! -d $SKILLS_DIR ]]; then
  log "→ creating $SKILLS_DIR"
  mkdir -p "$SKILLS_DIR"
fi

# ─────────────────────────────────────────────────────────────────────────
# Handle existing install
# ─────────────────────────────────────────────────────────────────────────

SKILL_SRC="$KIT_ROOT/skill"
[[ -d $SKILL_SRC ]] || die "skill/ directory missing at $SKILL_SRC — is this a corrupted clone?"

if [[ -L $INSTALL_PATH ]]; then
  current_target=$(readlink "$INSTALL_PATH")
  if [[ $current_target == "$SKILL_SRC" ]]; then
    log "· symlink already points at this clone — nothing to do"
    installed=1
  else
    log "→ existing symlink points elsewhere ($current_target); refreshing"
    rm "$INSTALL_PATH"
    ln -s "$SKILL_SRC" "$INSTALL_PATH"
    installed=1
  fi
elif [[ -e $INSTALL_PATH ]]; then
  if (( FORCE )); then
    log "→ $INSTALL_PATH exists as a non-symlink; removing (--force)"
    rm -rf "$INSTALL_PATH"
    ln -s "$SKILL_SRC" "$INSTALL_PATH"
    installed=1
  else
    warn "$INSTALL_PATH exists and is NOT a symlink"
    warn "  Refusing to overwrite. Options:"
    warn "    - Rename or remove it manually, then re-run install.sh"
    warn "    - Re-run with --force to overwrite"
    exit 1
  fi
else
  log "→ creating symlink"
  ln -s "$SKILL_SRC" "$INSTALL_PATH"
  installed=1
fi

# ─────────────────────────────────────────────────────────────────────────
# Post-install verification
# ─────────────────────────────────────────────────────────────────────────

log ""
log "Post-install verification:"

# The symlink resolves.
if [[ -L $INSTALL_PATH ]] && [[ -d "$INSTALL_PATH/" ]]; then
  printf '  %s✓%s symlink resolves: %s → %s\n' "$GREEN" "$RESET" "$INSTALL_PATH" "$(readlink "$INSTALL_PATH")"
else
  die "install symlink does not resolve; something went wrong"
fi

# SKILL.md is reachable via the install path.
if [[ -f "$INSTALL_PATH/SKILL.md" ]]; then
  printf '  %s✓%s SKILL.md reachable via install path\n' "$GREEN" "$RESET"
else
  die "SKILL.md not reachable via $INSTALL_PATH"
fi

# ai-native-verify is executable via the install path.
if [[ -x "$INSTALL_PATH/scripts/ai-native-verify" ]]; then
  printf '  %s✓%s ai-native-verify executable\n' "$GREEN" "$RESET"
else
  die "ai-native-verify not executable at $INSTALL_PATH/scripts/"
fi

# Run --version as a smoke test.
if version=$("$INSTALL_PATH/scripts/ai-native-verify" --version 2>&1); then
  printf '  %s✓%s smoke test: %s\n' "$GREEN" "$RESET" "$version"
else
  die "ai-native-verify --version failed"
fi

log ""
log "$(printf '%s✓ Installed.%s' "$BOLD" "$RESET")"
printf '\n'
printf 'Next steps:\n'
printf '  1. Start a NEW Claude Code session (existing sessions do not pick up new skills).\n'
printf '  2. Invoke /ai-native-migration <path-to-any-repo> to run an audit.\n'
printf '  3. To run just the deterministic layer without Claude Code:\n'
printf '       %s/scripts/ai-native-verify <path-to-any-repo>\n' "$INSTALL_PATH"
printf '\n'
printf 'To uninstall: %s --uninstall\n' "$0"

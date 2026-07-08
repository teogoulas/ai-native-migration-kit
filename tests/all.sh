#!/usr/bin/env bash
# tests/all.sh — run every test harness the kit ships.
#
# Two harnesses today:
#   1. verify.test.sh — regression tests for ai-native-verify (bash + jq)
#   2. workflow.test.mjs — unit tests for the workflow's pure logic (node)
#
# Both run in seconds. Exit code is non-zero if any harness fails.
# This is the entry point CI (.github/workflows/ci.yml.pending) calls.

set -euo pipefail

_resolve_dir() {
  local src=$1
  while [[ -L $src ]]; do
    local dir; dir=$(cd -P "$(dirname "$src")" && pwd)
    src=$(readlink "$src"); [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
TEST_DIR=$(_resolve_dir "${BASH_SOURCE[0]}")

BOLD=$'\033[1m'
RESET=$'\033[0m'
[[ -t 1 ]] || { BOLD=""; RESET=""; }

printf '\n%s=== ai-native-verify regression tests ===%s\n' "$BOLD" "$RESET"
bash "$TEST_DIR/verify.test.sh"

printf '\n%s=== workflow unit tests ===%s\n' "$BOLD" "$RESET"
node "$TEST_DIR/workflow.test.mjs"

printf '\n%sAll test harnesses passed.%s\n' "$BOLD" "$RESET"

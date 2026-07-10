#!/usr/bin/env bash
# tests/common.test.sh — unit tests for lib/common.sh helpers.
#
# Covers the additions from spec 02 P-4:
#   - SCOPE_* constants
#   - aggregate_verdicts (rubric §5.2 default rule)
#   - list_workspace_roots (cache populates from detect-workspaces.sh)
#   - in_each_workspace (callback iteration)
#
# The existing helpers (json_escape, file_contains, verdict constants)
# are exercised indirectly by verify.test.sh; no need to duplicate.
#
# Runs in seconds. Wired into tests/all.sh.
#
# Usage:
#   bash tests/common.test.sh              # run all tests
#   bash tests/common.test.sh --verbose    # print details on pass

set -uo pipefail
# Not using -e: we need to run assertions individually and continue on failure.

# ---------- locate the kit ----------

_resolve_dir() {
  local src=$1
  while [[ -L $src ]]; do
    local dir; dir=$(cd -P "$(dirname "$src")" && pwd)
    src=$(readlink "$src"); [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
TEST_DIR=$(_resolve_dir "${BASH_SOURCE[0]}")
KIT_ROOT=$(cd "$TEST_DIR/.." && pwd)
COMMON_SH="$KIT_ROOT/plugins/ai-native-migration/scripts/lib/common.sh"

[[ -r $COMMON_SH ]] || { printf 'error: common.sh not readable at %s\n' "$COMMON_SH" >&2; exit 3; }

# Source common.sh into this test process.
# shellcheck source=/dev/null
. "$COMMON_SH"

VERBOSE=0
[[ ${1:-} == "--verbose" ]] && VERBOSE=1

# ---------- assertion framework ----------

PASS_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=()

if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_GRAY=""; C_BOLD=""; C_RESET=""
fi

pass() { (( ++PASS_COUNT )); printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
fail() {
  (( ++FAIL_COUNT )); FAIL_NAMES+=("$1")
  printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1"
  printf '    %sexpected:%s %s\n' "$C_GRAY" "$C_RESET" "$2"
  printf '    %sactual:  %s %s\n' "$C_GRAY" "$C_RESET" "$3"
}

assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi }

section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }

# ---------- SCOPE_* constants ----------

section "SCOPE_* constants exposed by common.sh"
{
  assert_eq "SCOPE_ROOT_ONLY"     "root-only"     "$SCOPE_ROOT_ONLY"
  assert_eq "SCOPE_PER_WORKSPACE" "per-workspace" "$SCOPE_PER_WORKSPACE"
  assert_eq "SCOPE_ROOT_PRIMARY"  "root-primary"  "$SCOPE_ROOT_PRIMARY"
}

# ---------- aggregate_verdicts — rubric §5.2 default rule ----------

section "aggregate_verdicts — §5.2 default rule"
{
  assert_eq "all pass → pass" \
    "pass" \
    "$(printf 'pass\npass\npass\n' | aggregate_verdicts)"

  assert_eq "one pass one fail → partial" \
    "partial" \
    "$(printf 'pass\nfail\n' | aggregate_verdicts)"

  assert_eq "pass + partial → partial" \
    "partial" \
    "$(printf 'pass\npartial\n' | aggregate_verdicts)"

  assert_eq "all fail → fail" \
    "fail" \
    "$(printf 'fail\nfail\n' | aggregate_verdicts)"

  assert_eq "fail + partial (no pass) → partial" \
    "partial" \
    "$(printf 'fail\npartial\n' | aggregate_verdicts)"

  assert_eq "all n/a → n/a" \
    "n/a" \
    "$(printf 'n/a\nn/a\n' | aggregate_verdicts)"

  assert_eq "empty input → n/a" \
    "n/a" \
    "$(printf '' | aggregate_verdicts)"

  assert_eq "single pass → pass" \
    "pass" \
    "$(printf 'pass\n' | aggregate_verdicts)"

  assert_eq "single fail → fail" \
    "fail" \
    "$(printf 'fail\n' | aggregate_verdicts)"

  # Mixed n/a with real verdicts — n/a doesn't count as either pass or fail.
  assert_eq "pass + n/a → partial (not-all-pass)" \
    "partial" \
    "$(printf 'pass\nn/a\n' | aggregate_verdicts)"

  assert_eq "fail + n/a → fail" \
    "fail" \
    "$(printf 'fail\nn/a\n' | aggregate_verdicts)"
}

# ---------- emit_per_workspace format ----------

section "emit_per_workspace — tab-separated fragment"
{
  out=$(emit_per_workspace "packages/api" "pass" "src/test/ present")
  assert_eq "emit_per_workspace format" \
    $'packages/api\tpass\tsrc/test/ present' \
    "$out"
}

# ---------- list_workspace_roots — cache populates from detector ----------

section "list_workspace_roots — cache populates on real fixture"
{
  # Reset cache — test isolation.
  _WORKSPACES_LOADED=0
  _WORKSPACES_TYPE=""
  _WORKSPACES_ROOT_PATHS=()
  _WORKSPACES_ROOT_STACKS=()
  _WORKSPACES_JSON=""

  # ai-native-verify sets TARGET; simulate.
  # shellcheck disable=SC2034
  TARGET="$TEST_DIR/fixtures/monorepos/pnpm-basic"

  list_workspace_roots

  assert_eq "cache flag set after call" 1 "$_WORKSPACES_LOADED"
  assert_eq "workspace type parsed"     "pnpm" "$_WORKSPACES_TYPE"
  assert_eq "root count: 3"             3 "${#_WORKSPACES_ROOT_PATHS[@]}"
  # Order is glob-expansion order (packages/* before apps/*, alphabetically within).
  assert_eq "first root path"           "packages/api" "${_WORKSPACES_ROOT_PATHS[0]:-}"
  assert_eq "first root stack"          "node"         "${_WORKSPACES_ROOT_STACKS[0]:-}"
}

section "list_workspace_roots — second call short-circuits (cache hit)"
{
  # After the previous section, cache is populated. Simulate a second call:
  # if list_workspace_roots re-runs the detector, the count would double or
  # the type would refresh. We assert both stay identical.
  before_count=${#_WORKSPACES_ROOT_PATHS[@]}
  before_type=$_WORKSPACES_TYPE
  list_workspace_roots
  assert_eq "cache-hit: count unchanged" "$before_count" "${#_WORKSPACES_ROOT_PATHS[@]}"
  assert_eq "cache-hit: type unchanged"  "$before_type"  "$_WORKSPACES_TYPE"
}

section "list_workspace_roots — flat repo emits type=none, empty roots"
{
  _WORKSPACES_LOADED=0
  _WORKSPACES_TYPE=""
  _WORKSPACES_ROOT_PATHS=()
  _WORKSPACES_ROOT_STACKS=()
  _WORKSPACES_JSON=""
  # shellcheck disable=SC2034
  TARGET="$TEST_DIR/fixtures/empty"

  list_workspace_roots

  assert_eq "flat repo: type=none"       "none" "$_WORKSPACES_TYPE"
  assert_eq "flat repo: 0 roots"         0 "${#_WORKSPACES_ROOT_PATHS[@]}"
}

# ---------- in_each_workspace — callback iteration ----------

section "in_each_workspace — invokes callback once per root"
{
  _WORKSPACES_LOADED=0
  _WORKSPACES_TYPE=""
  _WORKSPACES_ROOT_PATHS=()
  _WORKSPACES_ROOT_STACKS=()
  _WORKSPACES_JSON=""
  # shellcheck disable=SC2034
  TARGET="$TEST_DIR/fixtures/monorepos/yarn-workspaces"

  visited=()
  _record() { visited+=("$1"); }
  in_each_workspace _record

  assert_eq "in_each_workspace: 2 visits" 2 "${#visited[@]}"
  # The paths are just packages/bar and packages/foo (alphabetical by glob).
  assert_eq "first visited" "packages/bar" "${visited[0]:-}"
  assert_eq "second visited" "packages/foo" "${visited[1]:-}"
}

section "in_each_workspace — flat repo: callback never called"
{
  _WORKSPACES_LOADED=0
  _WORKSPACES_TYPE=""
  _WORKSPACES_ROOT_PATHS=()
  _WORKSPACES_ROOT_STACKS=()
  _WORKSPACES_JSON=""
  # shellcheck disable=SC2034
  TARGET="$TEST_DIR/fixtures/empty"

  visited=()
  _record() { visited+=("$1"); }
  in_each_workspace _record

  assert_eq "flat repo: 0 visits" 0 "${#visited[@]}"
}

# ---------- report ----------

printf '\n%s%s%s  ' "$C_BOLD" "results" "$C_RESET"
if (( FAIL_COUNT == 0 )); then
  printf '%s%d passed%s\n' "$C_GREEN" "$PASS_COUNT" "$C_RESET"
  exit 0
fi
printf '%s%d passed%s, %s%d failed%s\n' "$C_GREEN" "$PASS_COUNT" "$C_RESET" "$C_RED" "$FAIL_COUNT" "$C_RESET"
printf 'failed:\n'
for n in "${FAIL_NAMES[@]}"; do printf '  - %s\n' "$n"; done
exit 1

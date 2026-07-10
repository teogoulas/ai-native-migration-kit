#!/usr/bin/env bash
# tests/detect-workspaces.test.sh — regression harness for detect-workspaces.sh.
#
# One assertion per fixture under tests/fixtures/monorepos/. Each fixture is
# built to trigger a specific detector; the assertions confirm:
#   - the emitted `type` field
#   - the count of enumerated roots
#   - one root path (the first, alphabetically) as a spot-check
#   - per-workspace stack for the cross-stack fixture
#
# Runs in seconds. Non-zero exit code on any failure. Wired into
# tests/all.sh alongside verify.test.sh and workflow.test.mjs.
#
# Usage:
#   bash tests/detect-workspaces.test.sh              # run all tests
#   bash tests/detect-workspaces.test.sh --verbose    # print details on pass

set -euo pipefail

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
DETECT="$KIT_ROOT/plugins/ai-native-migration/scripts/detect-workspaces.sh"
FIXTURES="$TEST_DIR/fixtures/monorepos"

[[ -x $DETECT ]] || { printf 'error: detect-workspaces.sh not executable at %s\n' "$DETECT" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { printf 'error: python3 is required to run detect-workspaces.test.sh (used for JSON assertions)\n' >&2; exit 3; }

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

# ---------- helpers ----------

# jq-free JSON field readers via python3.
json_get() {
  # json_get <json> <dotted.path>
  local j=$1 p=$2
  python3 - "$p" <<PY 2>/dev/null || true
import json, sys
data = json.loads('''$j''')
node = data
for k in sys.argv[1].split('.'):
    if isinstance(node, dict) and k in node:
        node = node[k]
    else:
        node = None
        break
if node is None: sys.exit(0)
if isinstance(node, (dict, list)):
    print(json.dumps(node))
else:
    print(node)
PY
}

# Number of items in the roots[] array.
roots_count() {
  python3 -c "import json, sys; print(len(json.loads(sys.stdin.read()).get('roots', [])))" <<<"$1" 2>/dev/null
}

# First root path (roots are emitted in glob-expansion order — deterministic).
first_root_path() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
rs = d.get('roots') or []
if rs and isinstance(rs[0], dict): print(rs[0].get('path', ''))
" <<<"$1" 2>/dev/null
}

# Nth root path.
nth_root_path() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
rs = d.get('roots') or []
i = $2
if i < len(rs) and isinstance(rs[i], dict): print(rs[i].get('path', ''))
" <<<"$1" 2>/dev/null
}

# Nth root stack.stack.
nth_root_stack() {
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
rs = d.get('roots') or []
i = $2
if i < len(rs) and isinstance(rs[i], dict):
    st = rs[i].get('stack') or {}
    print(st.get('stack', ''))
" <<<"$1" 2>/dev/null
}

# Run the detector, capture stdout, and assert exit code.
run_detect() {
  local fixture=$1
  set +e
  JSON_OUT=$("$DETECT" "$fixture" 2>/dev/null)
  EXIT_CODE=$?
  set -e
}

# ---------- test sections ----------

section "Preflight"
{
  # Nonexistent path exits 1.
  set +e
  "$DETECT" /nonexistent/path/nowhere >/dev/null 2>&1
  code=$?
  set -e
  assert_eq "preflight: missing path exits 1" 1 "$code"

  # Missing arg exits 1.
  set +e
  "$DETECT" >/dev/null 2>&1
  code=$?
  set -e
  assert_eq "preflight: no arg exits 1" 1 "$code"
}

section "Flat repo — no monorepo topology"
{
  # Reuse an existing flat fixture that we know is not a monorepo.
  run_detect "$KIT_ROOT/tests/fixtures/empty"
  assert_eq "empty fixture exits 0" 0 "$EXIT_CODE"
  assert_eq "empty fixture: type=none" "none" "$(json_get "$JSON_OUT" type)"
  assert_eq "empty fixture: 0 roots" 0 "$(roots_count "$JSON_OUT")"
}

section "JS family: pnpm-workspace.yaml"
{
  run_detect "$FIXTURES/pnpm-basic"
  assert_eq "pnpm-basic: type=pnpm"   "pnpm" "$(json_get "$JSON_OUT" type)"
  assert_eq "pnpm-basic: 3 roots"     3      "$(roots_count "$JSON_OUT")"
  # The first workspace by glob order (packages/* before apps/*) is packages/api.
  assert_eq "pnpm-basic: first root"  "packages/api" "$(first_root_path "$JSON_OUT")"
}

section "JS family: yarn workspaces (yarn.lock present)"
{
  run_detect "$FIXTURES/yarn-workspaces"
  assert_eq "yarn: type=yarn"         "yarn" "$(json_get "$JSON_OUT" type)"
  assert_eq "yarn: 2 roots"           2      "$(roots_count "$JSON_OUT")"
}

section "JS family: npm workspaces (no yarn.lock)"
{
  run_detect "$FIXTURES/npm-workspaces"
  assert_eq "npm: type=npm"           "npm"  "$(json_get "$JSON_OUT" type)"
  assert_eq "npm: 2 roots"            2      "$(roots_count "$JSON_OUT")"
}

section "JS family: lerna with packages field"
{
  run_detect "$FIXTURES/lerna-basic"
  assert_eq "lerna: type=lerna"       "lerna" "$(json_get "$JSON_OUT" type)"
  assert_eq "lerna: 2 roots"          2       "$(roots_count "$JSON_OUT")"
}

section "JS family: nx layered on pnpm"
{
  run_detect "$FIXTURES/nx-basic"
  assert_eq "nx: type=nx"             "nx"   "$(json_get "$JSON_OUT" type)"
  assert_eq "nx: 2 roots enumerated from underlying pnpm" 2 "$(roots_count "$JSON_OUT")"
}

section "JS family: turbo layered on npm workspaces"
{
  run_detect "$FIXTURES/turbo-basic"
  assert_eq "turbo: type=turbo"       "turbo" "$(json_get "$JSON_OUT" type)"
  assert_eq "turbo: 2 roots"          2       "$(roots_count "$JSON_OUT")"
}

section "JS family: rush explicit projects"
{
  run_detect "$FIXTURES/rush-basic"
  assert_eq "rush: type=rush"         "rush" "$(json_get "$JSON_OUT" type)"
  assert_eq "rush: 1 root"            1      "$(roots_count "$JSON_OUT")"
  assert_eq "rush: first root"        "projects/foo" "$(first_root_path "$JSON_OUT")"
}

section "JVM family: gradle multi-module"
{
  run_detect "$FIXTURES/gradle-multi"
  assert_eq "gradle: type=gradle-multi" "gradle-multi" "$(json_get "$JSON_OUT" type)"
  assert_eq "gradle: 2 roots"           2              "$(roots_count "$JSON_OUT")"
}

section "JVM family: maven multi-module"
{
  run_detect "$FIXTURES/maven-multi"
  assert_eq "maven: type=maven-multi"  "maven-multi" "$(json_get "$JSON_OUT" type)"
  assert_eq "maven: 2 roots"           2             "$(roots_count "$JSON_OUT")"
}

section "Rust: cargo workspaces"
{
  run_detect "$FIXTURES/cargo-ws"
  assert_eq "cargo: type=cargo"       "cargo" "$(json_get "$JSON_OUT" type)"
  assert_eq "cargo: 2 roots"          2       "$(roots_count "$JSON_OUT")"
}

section "Go: go.work"
{
  run_detect "$FIXTURES/go-work"
  assert_eq "go-work: type=go-work"   "go-work" "$(json_get "$JSON_OUT" type)"
  assert_eq "go-work: 2 roots"        2         "$(roots_count "$JSON_OUT")"
}

section "PHP: composer path repos"
{
  run_detect "$FIXTURES/composer-multi"
  assert_eq "composer: type=composer-multi" "composer-multi" "$(json_get "$JSON_OUT" type)"
  assert_eq "composer: 1 root"              1                "$(roots_count "$JSON_OUT")"
}

section "Bazel: detect-only (Q-06 resolution)"
{
  run_detect "$FIXTURES/bazel-basic"
  assert_eq "bazel: type=bazel"       "bazel" "$(json_get "$JSON_OUT" type)"
  assert_eq "bazel: 0 roots (enumeration deferred)" 0 "$(roots_count "$JSON_OUT")"
}

section "Cross-stack: workspaces expose distinct stacks (Q-04 resolution)"
{
  run_detect "$FIXTURES/cross-stack"
  # Fixture: settings.gradle with :api (Java via build.gradle) and :web-ui (Node via package.json).
  assert_eq "cross-stack: type=gradle-multi" "gradle-multi" "$(json_get "$JSON_OUT" type)"
  assert_eq "cross-stack: 2 roots"           2              "$(roots_count "$JSON_OUT")"
  # The first root (:api) has build.gradle → java.
  # The second (:web-ui) has package.json → node.
  # Order follows settings.gradle include(...) declaration order.
  assert_eq "cross-stack: root[0] stack=java" "java" "$(nth_root_stack "$JSON_OUT" 0)"
  assert_eq "cross-stack: root[1] stack=node" "node" "$(nth_root_stack "$JSON_OUT" 1)"
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

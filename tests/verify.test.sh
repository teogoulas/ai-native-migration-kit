#!/usr/bin/env bash
# tests/verify.test.sh — regression harness for ai-native-verify.
#
# Runs ai-native-verify against the three synthetic fixtures under
# tests/fixtures/ and asserts on:
#   - exit code
#   - summary counts (pass, partial, fail, n/a)
#   - top-level JSON fields (stack, exit_code, schema_version)
#   - a small handful of per-criterion verdicts that must match exactly
#
# Zero external dependencies beyond bash, jq, and the kit itself.
# Runs in seconds; suitable for pre-push and CI.
#
# Usage:
#   bash tests/verify.test.sh              # run all tests
#   bash tests/verify.test.sh --verbose    # print details on pass too

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
VERIFY="$KIT_ROOT/plugins/ai-native-migration/scripts/ai-native-verify"
FIXTURES="$TEST_DIR/fixtures"

# Sanity: everything we need exists.
[[ -x $VERIFY ]] || { printf 'error: ai-native-verify not executable at %s\n' "$VERIFY" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { printf 'error: jq is required to run verify.test.sh\n' >&2; exit 3; }

VERBOSE=0
[[ ${1:-} == "--verbose" ]] && VERBOSE=1

# ---------- test framework ----------

PASS_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=()

# Colors when stdout is a TTY.
if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_GRAY=""; C_BOLD=""; C_RESET=""
fi

pass() {
  (( ++PASS_COUNT ))
  printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

fail() {
  (( ++FAIL_COUNT ))
  FAIL_NAMES+=("$1")
  printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1"
  printf '    %sexpected:%s %s\n' "$C_GRAY" "$C_RESET" "$2"
  printf '    %sactual:  %s %s\n' "$C_GRAY" "$C_RESET" "$3"
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "$2" "$3"
  fi
}

# assert_exit <label> <expected_code> <actual_code>
assert_exit() {
  assert_eq "$1 (exit code)" "$2" "$3"
}

# Run ai-native-verify against a fixture, capture stdout+exitcode.
# Sets JSON_OUT and EXIT_CODE.
run_verify_json() {
  local fixture=$1
  # Disable set -e locally so a nonzero exit doesn't abort the test.
  set +e
  JSON_OUT=$("$VERIFY" --format=json "$fixture" 2>/dev/null)
  EXIT_CODE=$?
  set -e
}

section() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

# ---------- test cases ----------

section "Preflight (usage errors → exit 3, no partial output)"
{
  set +e
  out=$("$VERIFY" 2>&1); code=$?
  set -e
  assert_exit "missing target" 3 "$code"
  assert_eq "error message on stderr" 1 "$([[ "$out" == error:* ]] && echo 1 || echo 0)"

  set +e
  out=$("$VERIFY" --format=xml /tmp 2>&1); code=$?
  set -e
  assert_exit "invalid --format" 3 "$code"

  set +e
  out=$("$VERIFY" --check=Z99 /tmp 2>&1); code=$?
  set -e
  assert_exit "unknown check id" 3 "$code"

  set +e
  out=$("$VERIFY" /tmp/nonexistent-path-12345 2>&1); code=$?
  set -e
  assert_exit "missing directory" 3 "$code"
}

section "Fixture: empty (rubric v0.2.0: 15 fail + 3 n/a → exit 2)"
{
  run_verify_json "$FIXTURES/empty"
  assert_exit "empty" 2 "$EXIT_CODE"
  assert_eq "empty stack.stack" "unknown"   "$(jq -r '.stack.stack' <<<"$JSON_OUT")"
  assert_eq "empty rubric_version" "0.2.0" "$(jq -r '.rubric_version' <<<"$JSON_OUT")"
  assert_eq "empty summary.pass"    0 "$(jq -r '.summary.pass'    <<<"$JSON_OUT")"
  assert_eq "empty summary.partial" 0 "$(jq -r '.summary.partial' <<<"$JSON_OUT")"
  assert_eq "empty summary.fail"   15 "$(jq -r '.summary.fail'    <<<"$JSON_OUT")"
  assert_eq "empty summary.na"      3 "$(jq -r '.summary.na'      <<<"$JSON_OUT")"
  assert_eq "empty summary.mandatory_fails"    13 "$(jq -r '.summary.mandatory_fails'    <<<"$JSON_OUT")"
  assert_eq "empty summary.nice_to_have_fails"  2 "$(jq -r '.summary.nice_to_have_fails' <<<"$JSON_OUT")"
  assert_eq "empty schema_version" "2" "$(jq -r '.schema_version' <<<"$JSON_OUT")"
  # D04 should be n/a because AGENTS.md doesn't exist / doesn't declare MCP (conditional severity — Q-10).
  assert_eq "empty D04 verdict (no MCP declaration → n/a)" "n/a" \
    "$(jq -r '.results[] | select(.id=="D04") | .verdict' <<<"$JSON_OUT")"
  assert_eq "empty D04 severity" "conditional" \
    "$(jq -r '.results[] | select(.id=="D04") | .severity' <<<"$JSON_OUT")"
  # D16 should be n/a because stack is unknown.
  assert_eq "empty D16 verdict (stack unknown → n/a)" "n/a" \
    "$(jq -r '.results[] | select(.id=="D16") | .verdict' <<<"$JSON_OUT")"
  # D18 should be n/a because D06 fails first (fail-cascade).
  assert_eq "empty D18 verdict (D06 fail cascade → n/a)" "n/a" \
    "$(jq -r '.results[] | select(.id=="D18") | .verdict' <<<"$JSON_OUT")"
}

section "Fixture: perfect (18/18 pass → exit 0)"
{
  run_verify_json "$FIXTURES/perfect"
  assert_exit "perfect" 0 "$EXIT_CODE"
  assert_eq "perfect stack.stack" "node"      "$(jq -r '.stack.stack' <<<"$JSON_OUT")"
  assert_eq "perfect summary.pass"    18 "$(jq -r '.summary.pass'    <<<"$JSON_OUT")"
  assert_eq "perfect summary.partial"  0 "$(jq -r '.summary.partial' <<<"$JSON_OUT")"
  assert_eq "perfect summary.fail"     0 "$(jq -r '.summary.fail'    <<<"$JSON_OUT")"
  assert_eq "perfect summary.na"       0 "$(jq -r '.summary.na'      <<<"$JSON_OUT")"
  assert_eq "perfect summary.mandatory_fails"    0 "$(jq -r '.summary.mandatory_fails'    <<<"$JSON_OUT")"
  assert_eq "perfect summary.nice_to_have_fails" 0 "$(jq -r '.summary.nice_to_have_fails' <<<"$JSON_OUT")"
  # Sanity check a few individual verdicts.
  for id in D01 D02 D03 D10 D13 D18; do
    assert_eq "perfect $id verdict" "pass" \
      "$(jq -r ".results[] | select(.id==\"$id\") | .verdict" <<<"$JSON_OUT")"
  done
}

section "Fixture: partial (rubric v0.2.0: 2 pass + 7 partial + 8 fail + 1 n/a → exit 2)"
{
  run_verify_json "$FIXTURES/partial"
  assert_exit "partial" 2 "$EXIT_CODE"
  assert_eq "partial stack.stack" "node"      "$(jq -r '.stack.stack' <<<"$JSON_OUT")"
  assert_eq "partial summary.pass"     2 "$(jq -r '.summary.pass'    <<<"$JSON_OUT")"
  assert_eq "partial summary.partial"  7 "$(jq -r '.summary.partial' <<<"$JSON_OUT")"
  assert_eq "partial summary.fail"     8 "$(jq -r '.summary.fail'    <<<"$JSON_OUT")"
  assert_eq "partial summary.na"       1 "$(jq -r '.summary.na'      <<<"$JSON_OUT")"
  assert_eq "partial summary.mandatory_fails"    7 "$(jq -r '.summary.mandatory_fails'    <<<"$JSON_OUT")"
  assert_eq "partial summary.nice_to_have_fails" 1 "$(jq -r '.summary.nice_to_have_fails' <<<"$JSON_OUT")"
  # Individual verdicts encoded in the fixture by construction. v0.2.0 changes:
  #   - D01 is now pass-or-fail only (no partial). Fixture's AGENTS.md is a
  #     stub missing canonical sections → fail.
  #   - D09 no longer accepts docs/plans/ as SDD-adjacent → fail.
  #   - D04 becomes n/a when AGENTS.md doesn't declare MCP.
  assert_eq "partial D01 (stub AGENTS.md missing canonical sections)" "fail" \
    "$(jq -r '.results[] | select(.id=="D01") | .verdict' <<<"$JSON_OUT")"
  assert_eq "partial D02 (CLAUDE.md regular file)" "partial" \
    "$(jq -r '.results[] | select(.id=="D02") | .verdict' <<<"$JSON_OUT")"
  assert_eq "partial D04 (no MCP declaration → n/a)" "n/a" \
    "$(jq -r '.results[] | select(.id=="D04") | .verdict' <<<"$JSON_OUT")"
  assert_eq "partial D07 (editorconfig at root)" "pass" \
    "$(jq -r '.results[] | select(.id=="D07") | .verdict' <<<"$JSON_OUT")"
  assert_eq "partial D09 (no docs/specs — docs/plans no longer counts)" "fail" \
    "$(jq -r '.results[] | select(.id=="D09") | .verdict' <<<"$JSON_OUT")"
  assert_eq "partial D13 (CI missing lint)" "partial" \
    "$(jq -r '.results[] | select(.id=="D13") | .verdict' <<<"$JSON_OUT")"
  assert_eq "partial D18 (pre-commit but no activation)" "fail" \
    "$(jq -r '.results[] | select(.id=="D18") | .verdict' <<<"$JSON_OUT")"
}

section "Fixture: realistic (regression baseline for T-30)"
{
  run_verify_json "$FIXTURES/realistic"
  assert_exit "realistic" 2 "$EXIT_CODE"
  assert_eq "realistic stack.stack" "node"      "$(jq -r '.stack.stack' <<<"$JSON_OUT")"
  assert_eq "realistic stack.framework" "next"  "$(jq -r '.stack.framework' <<<"$JSON_OUT")"
  # Encoded expectations from tests/fixtures/realistic/README.md.
  # If any of these change, either the fixture drifted or the rubric changed;
  # either way, review the README and update these together.
  assert_eq "realistic summary.pass"     2 "$(jq -r '.summary.pass'    <<<"$JSON_OUT")"
  assert_eq "realistic summary.partial"  3 "$(jq -r '.summary.partial' <<<"$JSON_OUT")"
  assert_eq "realistic summary.fail"    11 "$(jq -r '.summary.fail'    <<<"$JSON_OUT")"
  assert_eq "realistic summary.na"       2 "$(jq -r '.summary.na'      <<<"$JSON_OUT")"
  assert_eq "realistic summary.mandatory_fails"    9 "$(jq -r '.summary.mandatory_fails'    <<<"$JSON_OUT")"
  assert_eq "realistic summary.nice_to_have_fails" 2 "$(jq -r '.summary.nice_to_have_fails' <<<"$JSON_OUT")"
  # Specific deliberate verdicts encoded in the fixture by construction.
  # v0.2.0: D01 fails on missing canonical sections; D08 accepts up to 4
  # docs and fails when only 2 present; D04 becomes n/a; severity added.
  assert_eq "realistic D01 (AGENTS.md missing canonical sections)" "fail" \
    "$(jq -r '.results[] | select(.id=="D01") | .verdict' <<<"$JSON_OUT")"
  assert_eq "realistic D02 (CLAUDE.md regular file)" "partial" \
    "$(jq -r '.results[] | select(.id=="D02") | .verdict' <<<"$JSON_OUT")"
  assert_eq "realistic D04 (no MCP declaration → n/a)" "n/a" \
    "$(jq -r '.results[] | select(.id=="D04") | .verdict' <<<"$JSON_OUT")"
  assert_eq "realistic D04 severity" "conditional" \
    "$(jq -r '.results[] | select(.id=="D04") | .severity' <<<"$JSON_OUT")"
  assert_eq "realistic D08 (docs quartet: only 2/4 present → partial)" "partial" \
    "$(jq -r '.results[] | select(.id=="D08") | .verdict' <<<"$JSON_OUT")"
  assert_eq "realistic D13 (CI missing lint)" "partial" \
    "$(jq -r '.results[] | select(.id=="D13") | .verdict' <<<"$JSON_OUT")"
  assert_eq "realistic D14 severity (nice-to-have)" "nice-to-have" \
    "$(jq -r '.results[] | select(.id=="D14") | .severity' <<<"$JSON_OUT")"
  assert_eq "realistic D16 (linter missing for node stack)" "fail" \
    "$(jq -r '.results[] | select(.id=="D16") | .verdict' <<<"$JSON_OUT")"
  assert_eq "realistic D17 severity (nice-to-have)" "nice-to-have" \
    "$(jq -r '.results[] | select(.id=="D17") | .severity' <<<"$JSON_OUT")"
  assert_eq "realistic D18 (D06 fail cascade → n/a)" "n/a" \
    "$(jq -r '.results[] | select(.id=="D18") | .verdict' <<<"$JSON_OUT")"
}

section "Subset via --check (exit code and filtering)"
{
  set +e
  out=$("$VERIFY" --format=json --check=D01,D06 "$FIXTURES/perfect" 2>/dev/null); code=$?
  set -e
  assert_exit "subset over perfect" 0 "$code"
  assert_eq "subset result count" 2 "$(jq -r '.results | length' <<<"$out")"
  assert_eq "subset checks_requested type" "array" "$(jq -r '.checks_requested | type' <<<"$out")"
  # Filter should preserve rubric order regardless of input order.
  set +e
  out=$("$VERIFY" --format=json --check=D06,D01 "$FIXTURES/perfect" 2>/dev/null); code=$?
  set -e
  assert_eq "subset preserves rubric order" "D01,D06" \
    "$(jq -r '[.results[].id] | join(",")' <<<"$out")"
}

section "Monorepo: D10 aggregates per-workspace verdicts (spec 02 §5.2)"
{
  # pnpm-basic fixture has tests in packages/api only; packages/web and
  # apps/mobile have none. Expected verdict: partial (1 pass, 2 fail).
  set +e
  out=$("$VERIFY" --format=json --check=D10 "$TEST_DIR/fixtures/monorepos/pnpm-basic" 2>/dev/null); code=$?
  set -e
  # Aggregate is partial (1 pass, 2 fail among workspaces). Partial → exit 1.
  assert_eq "monorepo D10 exit code" 1 "$code"
  assert_eq "monorepo D10 verdict"   "partial"   "$(jq -r '.results[0].verdict' <<<"$out")"
  # per_workspace block present with three keys.
  assert_eq "monorepo D10 per_workspace keys" 3 \
    "$(jq -r '.results[0].per_workspace | length' <<<"$out")"
  assert_eq "packages/api verdict" "pass" \
    "$(jq -r '.results[0].per_workspace["packages/api"].verdict' <<<"$out")"
  assert_eq "packages/web verdict" "fail" \
    "$(jq -r '.results[0].per_workspace["packages/web"].verdict' <<<"$out")"
  assert_eq "apps/mobile verdict"  "fail" \
    "$(jq -r '.results[0].per_workspace["apps/mobile"].verdict' <<<"$out")"
  # Root-only checks in the same run still omit the per_workspace field.
  set +e
  out2=$("$VERIFY" --format=json --check=D01,D10 "$TEST_DIR/fixtures/monorepos/pnpm-basic" 2>/dev/null); code=$?
  set -e
  d01_has_pw=$(jq -r '.results[] | select(.id=="D01") | has("per_workspace")' <<<"$out2")
  d10_has_pw=$(jq -r '.results[] | select(.id=="D10") | has("per_workspace")' <<<"$out2")
  assert_eq "root-only D01 omits per_workspace" "false" "$d01_has_pw"
  assert_eq "per-workspace D10 includes per_workspace" "true" "$d10_has_pw"
}

section "Monorepo: D11 aggregates per-workspace verdicts"
{
  # pnpm-basic: packages/api has tests/integration/, others do not.
  set +e
  out=$("$VERIFY" --format=json --check=D11 "$TEST_DIR/fixtures/monorepos/pnpm-basic" 2>/dev/null); code=$?
  set -e
  assert_eq "monorepo D11 exit code" 1 "$code"
  assert_eq "monorepo D11 verdict"   "partial" "$(jq -r '.results[0].verdict' <<<"$out")"
  assert_eq "packages/api D11 verdict" "pass" \
    "$(jq -r '.results[0].per_workspace["packages/api"].verdict' <<<"$out")"
  assert_eq "packages/web D11 verdict" "fail" \
    "$(jq -r '.results[0].per_workspace["packages/web"].verdict' <<<"$out")"
  assert_eq "apps/mobile D11 verdict"  "fail" \
    "$(jq -r '.results[0].per_workspace["apps/mobile"].verdict' <<<"$out")"
}

section "Flat repo: D10 unchanged from pre-P-5 behavior"
{
  # perfect fixture: flat repo with tests at root. Router should fall through
  # to root-only, no per_workspace field emitted.
  set +e
  out=$("$VERIFY" --format=json --check=D10 "$FIXTURES/perfect" 2>/dev/null); code=$?
  set -e
  assert_eq "flat D10 exit code" 0 "$code"
  assert_eq "flat D10 verdict"   "pass" "$(jq -r '.results[0].verdict' <<<"$out")"
  assert_eq "flat D10 omits per_workspace" "false" \
    "$(jq -r '.results[0] | has("per_workspace")' <<<"$out")"
}

section "Text output smoke test"
{
  set +e
  out=$("$VERIFY" --no-color "$FIXTURES/perfect" 2>/dev/null); code=$?
  set -e
  assert_exit "text against perfect" 0 "$code"
  # The text output must include the word 'summary' and every check ID.
  contains_summary=$([[ "$out" == *"summary"* ]] && echo 1 || echo 0)
  assert_eq "text contains 'summary'" 1 "$contains_summary"
  for id in D01 D06 D12 D18; do
    contains_id=$([[ "$out" == *"$id"* ]] && echo 1 || echo 0)
    assert_eq "text contains $id" 1 "$contains_id"
  done
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

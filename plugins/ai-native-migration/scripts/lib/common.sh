#!/usr/bin/env bash
# common.sh — shared helpers for plugins/ai-native-migration/scripts/*
# Sourced by ai-native-verify (and eventually bootstrap.sh). Never executed directly.
#
# Depends on: bash 3.2+, standard POSIX tools. No jq — this stays runnable in
# minimal environments. Callers must have `set -euo pipefail` before sourcing.

# ---------- constants ----------

# Version of the ai-native-migration-kit rubric these helpers implement.
# Bumped whenever the criteria set changes materially (add/remove/rename D or A).
readonly ANMK_RUBRIC_VERSION="0.2.0"

# ---------- logging ----------

# Emit an informational message to stderr. stdout is reserved for machine output.
log_info() {
  printf '%s\n' "$*" >&2
}

# Emit an error message to stderr and exit.
# Optional first arg: --code=<n> to override the default exit code (1).
# Usage:
#   die "message"                # exits 1
#   die --code=3 "preflight failed: $reason"
die() {
  local code=1
  if [[ ${1-} == --code=* ]]; then
    code=${1#--code=}
    shift
  fi
  printf 'error: %s\n' "$*" >&2
  exit "$code"
}

# ---------- json helpers ----------

# JSON-escape a string for embedding as a value. Handles the seven required
# escapes (backslash, quote, LF, CR, TAB, BS, FF) and is intentionally
# conservative — enough for filenames, evidence quotes, and short prose.
# For anything unusual, prefer to normalize the input before quoting.
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  printf '%s' "$s"
}

# Emit a scalar JSON value from a shell value.
#   json_value <shell-value>
# String values are quoted. The literals null|true|false and pure numbers
# (int/float, positive/negative) are emitted unquoted.
json_value() {
  local v=$1
  case $v in
    null|true|false) printf '%s' "$v" ;;
    -*[!0-9.]*|*[!0-9.-]*) printf '"%s"' "$(json_escape "$v")" ;;
    -*|[0-9]*|-|.) printf '"%s"' "$(json_escape "$v")" ;;
    *[.0-9]) printf '%s' "$v" ;;
    *) printf '"%s"' "$(json_escape "$v")" ;;
  esac
}

# ---------- preflight ----------

# Verify a path is a directory we can read. Dies on failure.
require_readable_dir() {
  local p=$1
  [[ -e $p ]] || die "path does not exist: $p"
  [[ -d $p ]] || die "path is not a directory: $p"
  [[ -r $p ]] || die "path is not readable: $p"
}

# Verify a path looks like a git working tree (has .git as file or dir).
# Returns 0/1; does not die — callers decide policy.
is_git_repo() {
  local p=$1
  [[ -e "$p/.git" ]]
}

# Resolve a path to absolute, portably.
absolute_path() {
  local p=$1
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  else
    (cd "$p" && pwd)
  fi
}

# ---------- file discovery ----------

# Test whether a file exists (regular file, not symlink to nowhere).
file_exists() {
  [[ -f $1 ]]
}

# Test whether a directory exists.
dir_exists() {
  [[ -d $1 ]]
}

# Test whether a path is a symlink resolving to a specific target (basename or
# absolute). Returns 0 on match, 1 otherwise.
symlink_targets() {
  local link=$1
  local expected=$2
  [[ -L $link ]] || return 1
  local actual
  actual=$(readlink "$link")
  [[ $actual == "$expected" ]]
}

# Find the first path in a target matching any of the given globs.
# Prunes standard noise directories to keep runtime bounded.
# Usage: first_match <target> <maxdepth> <glob1> [<glob2> ...]
first_match() {
  local target=$1
  local maxdepth=$2
  shift 2
  local args=()
  local first=1
  for pat in "$@"; do
    if (( first )); then
      args+=( -name "$pat" )
      first=0
    else
      args+=( -o -name "$pat" )
    fi
  done
  find "$target" -maxdepth "$maxdepth" \
    \( -name node_modules -o -name .venv -o -name venv -o -name target -o -name .git -o -name dist -o -name build -o -name .gradle -o -name .idea \) -prune \
    -o -type f \( "${args[@]}" \) -print 2>/dev/null \
    | head -n1
}

# Test whether a file's contents contain a fixed string.
file_contains() {
  local file=$1
  local needle=$2
  [[ -f $file ]] || return 1
  grep -qF -- "$needle" "$file" 2>/dev/null
}

# ---------- rubric verdict constants ----------

readonly VERDICT_PASS=pass
readonly VERDICT_PARTIAL=partial
readonly VERDICT_FAIL=fail
readonly VERDICT_NA=n/a

# ---------- monorepo scope constants (added v0.2.0 per rubric §5) ----------
#
# Applied by ai-native-verify's run_check() dispatcher. See
# `references/ai-native-checklist.md` §5.1 for per-criterion scope
# assignments and §5.2 for the default aggregation rule.

readonly SCOPE_ROOT_ONLY=root-only
readonly SCOPE_PER_WORKSPACE=per-workspace
readonly SCOPE_ROOT_PRIMARY=root-primary

# ---------- workspace detection cache ----------
#
# detect-workspaces.sh is invoked at most once per verify run. Results are
# cached in _WORKSPACES_* vars so per-workspace checks don't re-invoke the
# detector. Callers use list_workspace_roots() (populates the cache lazily)
# and then read _WORKSPACES_ROOT_PATHS / _WORKSPACES_ROOT_STACKS.
#
# Not activated in P-4 — run_check still dispatches every scope to the
# root-only path. P-5 flips the switch and starts iterating.

_WORKSPACES_LOADED=0
_WORKSPACES_TYPE=""
_WORKSPACES_ROOT_PATHS=()    # workspace paths, relative to $TARGET
_WORKSPACES_ROOT_STACKS=()   # matching stacks, same index (e.g. "node")
_WORKSPACES_JSON=""          # raw JSON payload (for advanced consumers)

# Populate the workspace cache by invoking detect-workspaces.sh once. Sets
# _WORKSPACES_LOADED so subsequent calls short-circuit. Silent on any error;
# callers see empty roots and fall back to root-only behavior.
#
# Depends on $TARGET being set in the caller (ai-native-verify sets it).
list_workspace_roots() {
  (( _WORKSPACES_LOADED )) && return 0
  _WORKSPACES_LOADED=1
  [[ -n "${TARGET:-}" ]] || return 0
  # detect-workspaces.sh sits one directory above lib/common.sh.
  local script
  script="$(dirname "${BASH_SOURCE[0]}")/../detect-workspaces.sh"
  [[ -x $script ]] || return 0
  local out
  out=$("$script" "$TARGET" 2>/dev/null) || return 0
  _WORKSPACES_JSON=$out
  if command -v python3 >/dev/null 2>&1; then
    _WORKSPACES_TYPE=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('type', 'none'))
except Exception:
    print('none')
" <<<"$out" 2>/dev/null || printf 'none')
    local line
    while IFS=$'\t' read -r line _stack; do
      [[ -n "$line" ]] || continue
      _WORKSPACES_ROOT_PATHS+=("$line")
      _WORKSPACES_ROOT_STACKS+=("${_stack:-unknown}")
    done < <(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for r in (d.get('roots') or []):
        if isinstance(r, dict):
            p = r.get('path', '')
            s = ((r.get('stack') or {}).get('stack', 'unknown'))
            print(f'{p}\t{s}')
except Exception:
    pass
" <<<"$out" 2>/dev/null || true)
  else
    # Grep-only fallback: extract the top-level type field.
    _WORKSPACES_TYPE=$(grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]+"' <<<"$out" \
      | head -1 \
      | sed -E 's/.*"type"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    [[ -n $_WORKSPACES_TYPE ]] || _WORKSPACES_TYPE=none
    # No root enumeration in fallback mode — a python3-less environment
    # sees the type but not the roots. Acceptable degradation: per-workspace
    # checks fall through to root-only behavior.
  fi
  return 0
}

# Iterate cached workspace roots, calling <callback> with each path. If no
# workspaces are cached, the callback is never invoked.
#
# Usage: in_each_workspace some_fn
in_each_workspace() {
  local callback=$1
  list_workspace_roots
  local ws
  for ws in "${_WORKSPACES_ROOT_PATHS[@]:-}"; do
    [[ -n "$ws" ]] || continue
    "$callback" "$ws"
  done
}

# Format a per-workspace result fragment for embedding in the per_workspace
# block of a check result. Callers collect these lines and format them into
# the final JSON in P-5.
#
#   emit_per_workspace <path> <verdict> <evidence>
emit_per_workspace() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# Aggregate a sequence of verdicts per rubric §5.2 default rule.
# Reads one verdict per line from stdin, emits the aggregate on stdout.
#
#   pass    when every verdict is pass
#   partial when at least one pass and at least one non-pass
#   fail    when at least one fail and no pass
#   n/a     when there are no verdicts, or every verdict is n/a
aggregate_verdicts() {
  local v pass=0 partial=0 fail=0 na=0 total=0
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    (( ++total ))
    case $v in
      "$VERDICT_PASS")    (( ++pass )) ;;
      "$VERDICT_PARTIAL") (( ++partial )) ;;
      "$VERDICT_FAIL")    (( ++fail )) ;;
      "$VERDICT_NA")      (( ++na )) ;;
    esac
  done
  if (( total == 0 )) || (( na == total )); then
    printf '%s' "$VERDICT_NA"
  elif (( pass == total )); then
    printf '%s' "$VERDICT_PASS"
  elif (( pass > 0 || partial > 0 )); then
    printf '%s' "$VERDICT_PARTIAL"
  else
    printf '%s' "$VERDICT_FAIL"
  fi
}

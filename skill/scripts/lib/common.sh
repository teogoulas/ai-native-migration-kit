#!/usr/bin/env bash
# common.sh — shared helpers for skill/scripts/*
# Sourced by ai-native-verify (and eventually bootstrap.sh). Never executed directly.
#
# Depends on: bash 3.2+, standard POSIX tools. No jq — this stays runnable in
# minimal environments. Callers must have `set -euo pipefail` before sourcing.

# ---------- constants ----------

# Version of the ai-native-migration-kit rubric these helpers implement.
# Bumped whenever the criteria set changes materially (add/remove/rename D or A).
readonly ANMK_RUBRIC_VERSION="0.1.0"

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

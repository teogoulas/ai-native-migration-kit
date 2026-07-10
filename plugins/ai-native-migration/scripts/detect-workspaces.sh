#!/usr/bin/env bash
# detect-workspaces.sh — detect the monorepo topology of a target repository.
#
# Emits a single JSON object on stdout matching the contract in
# docs/specs/02-monorepo-support/02-spec-monorepo-support.md §4.1:
#
#   {
#     "type": "pnpm|yarn|npm|lerna|nx|turbo|rush|
#              gradle-multi|maven-multi|cargo|go-work|
#              composer-multi|bazel|none|unknown",
#     "roots": [
#       {
#         "path":     "packages/api",
#         "manifest": "packages/api/package.json",
#         "stack":    { "stack": "node", ... }        # detect-stack.sh output
#       },
#       ...
#     ],
#     "detector_confidence": "high|medium|low",
#     "notes": "one-line human-readable explanation"
#   }
#
# Composes over `detect-stack.sh` — each workspace root is passed through the
# language detector so downstream consumers can see per-workspace stacks
# without doing their own detection.
#
# Best-effort. Never fails on ambiguous input — returns
# {"type":"none","roots":[]} instead. Consumers treat empty roots as
# flat-repo behavior. The "cross-stack" top-level stack decision is NOT
# made here; that logic lives in ai-native-verify (Phase 4).
#
# Contract:
#   - Input: single positional argument, path to target repo root.
#   - Output: one JSON object on stdout, exit 0.
#   - Errors: exit 1 with human-readable message on stderr for preflight
#     failures (path missing, not readable). NEVER exit non-zero for
#     "not a monorepo" — that returns {"type":"none","roots":[]}.
#
# Runtime dependencies:
#   - bash 4+ (for globstar and arrays)
#   - python3 (soft — used for JSON/TOML parsing; falls back to grep/sed
#     heuristics if absent, but the grep path handles only the common
#     cases)

set -euo pipefail

# ---------- helpers ----------

die() {
  printf 'detect-workspaces: %s\n' "$*" >&2
  exit 1
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

file_contains() {
  local file=$1
  local needle=$2
  [[ -f $file ]] || return 1
  grep -qF -- "$needle" "$file" 2>/dev/null
}

have_python3() {
  command -v python3 >/dev/null 2>&1
}

# Read a JSON array of strings from <file> at <dotted.path>.
# If the path resolves to an object with a `packages` array (yarn's object
# form of `workspaces`), returns that array's elements. Prints one entry
# per line. Silent on any error.
read_json_string_array() {
  local file=$1
  local dotted=$2
  [[ -f $file ]] || return 0
  if have_python3; then
    python3 - "$file" "$dotted" <<'PY' 2>/dev/null || true
import json, sys
path, dotted = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
node = data
for key in dotted.split('.'):
    if isinstance(node, dict) and key in node:
        node = node[key]
    else:
        node = None
        break
if isinstance(node, list):
    for item in node:
        if isinstance(item, str):
            print(item)
elif isinstance(node, dict):
    inner = node.get('packages')
    if isinstance(inner, list):
        for item in inner:
            if isinstance(item, str):
                print(item)
PY
  else
    # Fallback: naive grep for the most common shape. Handles flat arrays
    # like `"workspaces": ["packages/*", "apps/*"]` on a single line.
    grep -oE "\"$dotted\"[[:space:]]*:[[:space:]]*\[[^]]*\]" "$file" 2>/dev/null \
      | grep -oE "\"[^\"]+\"" \
      | tr -d '"' \
      | tail -n +2   # skip the key itself
  fi
}

# Read one string field from JSON.
read_json_string_field() {
  local file=$1
  local dotted=$2
  [[ -f $file ]] || return 0
  if have_python3; then
    python3 - "$file" "$dotted" <<'PY' 2>/dev/null || true
import json, sys
path, dotted = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
node = data
for key in dotted.split('.'):
    if isinstance(node, dict) and key in node:
        node = node[key]
    else:
        node = None
        break
if isinstance(node, str):
    print(node)
PY
  fi
}

# ---------- preflight ----------

if [[ $# -lt 1 ]]; then
  die "usage: detect-workspaces.sh <target-repo-path>"
fi

TARGET=$1
[[ -e $TARGET ]] || die "path does not exist: $TARGET"
[[ -d $TARGET ]] || die "path is not a directory: $TARGET"
[[ -r $TARGET ]] || die "path is not readable: $TARGET"

if command -v realpath >/dev/null 2>&1; then
  TARGET=$(realpath "$TARGET")
else
  TARGET=$(cd "$TARGET" && pwd)
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DETECT_STACK="$SCRIPT_DIR/detect-stack.sh"
[[ -x $DETECT_STACK ]] || die "detect-stack.sh not executable at $DETECT_STACK"

# ---------- state ----------

WORKSPACE_TYPE=none
WORKSPACE_ROOTS=()   # array of "path|manifest" entries; path is relative to TARGET
NOTES=""
CONFIDENCE=high

# ---------- glob expansion ----------

# add_roots_from_globs <manifest-basename> <glob> [<glob> ...]
# For each pattern, expands (nullglob+globstar) and adds directories that
# contain the named manifest. `!` prefixes are treated as excludes and
# applied post-hoc.
add_roots_from_globs() {
  local manifest=$1
  shift
  local -a includes=()
  local -a excludes=()
  local pattern
  for pattern in "$@"; do
    if [[ $pattern == !* ]]; then
      excludes+=("${pattern#!}")
    else
      includes+=("$pattern")
    fi
  done

  shopt -s nullglob globstar
  local -A seen=()
  local pat dir rel
  for pat in "${includes[@]}"; do
    # We use the pattern relative to TARGET. `pat` is not quoted so the
    # shell performs globbing; TARGET is quoted so paths with spaces survive.
    for dir in "$TARGET"/$pat/; do
      dir=${dir%/}
      [[ -d $dir ]] || continue
      [[ -f "$dir/$manifest" ]] || continue
      rel=${dir#"$TARGET/"}
      [[ -z ${seen[$rel]:-} ]] || continue
      # Apply excludes.
      local skip=0
      local ex
      for ex in "${excludes[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$TARGET/$rel" == $TARGET/$ex ]]; then
          skip=1; break
        fi
      done
      (( skip )) && continue
      seen[$rel]=1
      WORKSPACE_ROOTS+=("$rel|$rel/$manifest")
    done
  done
  shopt -u nullglob globstar
}

# ---------- detection functions ----------
#
# Each detector, if matching, sets WORKSPACE_TYPE / WORKSPACE_ROOTS / NOTES
# and returns 0. Non-match returns 1. Callers try each in priority order and
# stop at the first match. Bazel is detect-only per Q-06 — matches but does
# not enumerate.

# --- Bazel (detect-only per Q-06) ---
detect_bazel() {
  if [[ -f "$TARGET/WORKSPACE" ]] || [[ -f "$TARGET/WORKSPACE.bazel" ]] || [[ -f "$TARGET/MODULE.bazel" ]]; then
    WORKSPACE_TYPE=bazel
    NOTES="bazel workspace detected; root enumeration deferred (see spec 02 Q-06)"
    CONFIDENCE=high
    return 0
  fi
  return 1
}

# --- Rush ---
detect_rush() {
  [[ -f "$TARGET/rush.json" ]] || return 1
  WORKSPACE_TYPE=rush
  CONFIDENCE=high
  if have_python3; then
    while IFS= read -r folder; do
      [[ -n "$folder" ]] || continue
      folder=${folder#./}
      folder=${folder%/}
      [[ -d "$TARGET/$folder" ]] || continue
      [[ -f "$TARGET/$folder/package.json" ]] || continue
      WORKSPACE_ROOTS+=("$folder|$folder/package.json")
    done < <(python3 - "$TARGET/rush.json" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
    for p in d.get('projects', []) or []:
        f = p.get('projectFolder')
        if isinstance(f, str) and f:
            print(f)
except Exception:
    pass
PY
    )
  fi
  NOTES="rush.json declares ${#WORKSPACE_ROOTS[@]} project(s)"
  return 0
}

# --- Nx ---
# nx.json declares Nx; roots come from an underlying workspace manager
# (pnpm/yarn/npm) or from co-located project.json files.
detect_nx() {
  [[ -f "$TARGET/nx.json" ]] || return 1
  WORKSPACE_TYPE=nx
  CONFIDENCE=high
  # Try to enumerate via the underlying workspace manager first.
  _enumerate_js_workspaces
  if (( ${#WORKSPACE_ROOTS[@]} == 0 )); then
    # Legacy nx / no base workspace manager — look for project.json under
    # the standard nx locations.
    add_roots_from_globs "project.json" "apps/*" "libs/*" "packages/*"
    (( ${#WORKSPACE_ROOTS[@]} == 0 )) && CONFIDENCE=low
  fi
  NOTES="nx.json declares an Nx workspace with ${#WORKSPACE_ROOTS[@]} project(s)"
  return 0
}

# --- Turborepo ---
detect_turbo() {
  [[ -f "$TARGET/turbo.json" ]] || return 1
  WORKSPACE_TYPE=turbo
  CONFIDENCE=high
  _enumerate_js_workspaces
  (( ${#WORKSPACE_ROOTS[@]} == 0 )) && CONFIDENCE=low
  NOTES="turbo.json declares a Turborepo with ${#WORKSPACE_ROOTS[@]} package(s)"
  return 0
}

# --- Lerna ---
detect_lerna() {
  [[ -f "$TARGET/lerna.json" ]] || return 1
  WORKSPACE_TYPE=lerna
  CONFIDENCE=high
  # Lerna's own `packages` field takes precedence.
  local -a patterns=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && patterns+=("$p")
  done < <(read_json_string_array "$TARGET/lerna.json" packages)
  if (( ${#patterns[@]} > 0 )); then
    add_roots_from_globs "package.json" "${patterns[@]}"
  else
    _enumerate_js_workspaces
  fi
  NOTES="lerna.json declares a Lerna monorepo with ${#WORKSPACE_ROOTS[@]} package(s)"
  return 0
}

# --- pnpm workspaces ---
detect_pnpm_workspaces() {
  [[ -f "$TARGET/pnpm-workspace.yaml" ]] || return 1
  WORKSPACE_TYPE=pnpm
  CONFIDENCE=high
  # Parse the packages: list from the YAML. We support the common shape:
  #   packages:
  #     - 'packages/*'
  #     - "apps/*"
  #     - '!**/__tests__/**'
  # Anything more exotic (folded style, block-scalar) needs a proper YAML
  # parser — we accept the limitation and document it.
  local -a patterns=()
  local line
  local in_packages=0
  while IFS= read -r line; do
    if [[ $line =~ ^packages: ]]; then
      in_packages=1
      continue
    fi
    if (( in_packages )); then
      if [[ $line =~ ^[^[:space:]#-] ]]; then
        # Left the packages block.
        break
      fi
      if [[ $line =~ ^[[:space:]]*-[[:space:]]*[\'\"]?([^\'\"[:space:]#]+)[\'\"]?[[:space:]]*(#.*)?$ ]]; then
        patterns+=("${BASH_REMATCH[1]}")
      fi
    fi
  done < "$TARGET/pnpm-workspace.yaml"
  if (( ${#patterns[@]} > 0 )); then
    add_roots_from_globs "package.json" "${patterns[@]}"
  fi
  NOTES="pnpm-workspace.yaml declares ${#WORKSPACE_ROOTS[@]} package(s)"
  return 0
}

# --- Yarn / npm workspaces (package.json .workspaces) ---
detect_pkgjson_workspaces() {
  [[ -f "$TARGET/package.json" ]] || return 1
  # Only match if the workspaces field is actually present. Cheap check first.
  file_contains "$TARGET/package.json" '"workspaces"' || return 1
  local -a patterns=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && patterns+=("$p")
  done < <(read_json_string_array "$TARGET/package.json" workspaces)
  # If workspaces exists but has no entries, this isn't really a monorepo.
  (( ${#patterns[@]} > 0 )) || return 1

  # Yarn if yarn.lock present; else npm (7+ supports workspaces natively).
  if [[ -f "$TARGET/yarn.lock" ]]; then
    WORKSPACE_TYPE=yarn
    NOTES="package.json workspaces + yarn.lock"
  else
    WORKSPACE_TYPE=npm
    NOTES="package.json workspaces (npm 7+)"
  fi
  CONFIDENCE=high
  add_roots_from_globs "package.json" "${patterns[@]}"
  NOTES="$NOTES; ${#WORKSPACE_ROOTS[@]} package(s)"
  return 0
}

# Helper: try each JS workspace manager in turn, populating WORKSPACE_ROOTS
# without setting the top-level type. Used by layered tools (nx, turbo,
# lerna) to reuse enumeration logic.
_enumerate_js_workspaces() {
  # pnpm first (most explicit), then package.json workspaces.
  if [[ -f "$TARGET/pnpm-workspace.yaml" ]]; then
    local -a patterns=()
    local line
    local in_packages=0
    while IFS= read -r line; do
      if [[ $line =~ ^packages: ]]; then
        in_packages=1; continue
      fi
      if (( in_packages )); then
        if [[ $line =~ ^[^[:space:]#-] ]]; then break; fi
        if [[ $line =~ ^[[:space:]]*-[[:space:]]*[\'\"]?([^\'\"[:space:]#]+)[\'\"]?[[:space:]]*(#.*)?$ ]]; then
          patterns+=("${BASH_REMATCH[1]}")
        fi
      fi
    done < "$TARGET/pnpm-workspace.yaml"
    (( ${#patterns[@]} > 0 )) && add_roots_from_globs "package.json" "${patterns[@]}"
  elif [[ -f "$TARGET/package.json" ]]; then
    local -a patterns2=()
    local p
    while IFS= read -r p; do
      [[ -n "$p" ]] && patterns2+=("$p")
    done < <(read_json_string_array "$TARGET/package.json" workspaces)
    (( ${#patterns2[@]} > 0 )) && add_roots_from_globs "package.json" "${patterns2[@]}"
  fi
}

# --- Gradle multi-module ---
detect_gradle_multi() {
  local settings=""
  if [[ -f "$TARGET/settings.gradle" ]]; then
    settings="$TARGET/settings.gradle"
  elif [[ -f "$TARGET/settings.gradle.kts" ]]; then
    settings="$TARGET/settings.gradle.kts"
  else
    return 1
  fi
  # Extract include(...) arguments. Supports both Groovy DSL ("include 'foo'")
  # and Kotlin DSL ("include(\"foo\")").
  local -a modules=()
  local raw
  while IFS= read -r raw; do
    modules+=("$raw")
  done < <(
    grep -E "^[[:space:]]*include[[:space:]]*\(?" "$settings" 2>/dev/null \
      | grep -oE "['\"][:a-zA-Z0-9_./-]+['\"]" \
      | tr -d "'\"" \
      | sed 's|^:||' \
      | tr ':' '/'
  )
  # No include lines? Not multi-module.
  (( ${#modules[@]} > 0 )) || return 1
  WORKSPACE_TYPE=gradle-multi
  CONFIDENCE=high
  local mod
  for mod in "${modules[@]}"; do
    [[ -n "$mod" ]] || continue
    [[ -d "$TARGET/$mod" ]] || continue
    # Prefer a build.gradle (or .kts) as the manifest; fall back to just the path.
    local manifest="$mod/build.gradle"
    [[ -f "$TARGET/$manifest" ]] || manifest="$mod/build.gradle.kts"
    [[ -f "$TARGET/$manifest" ]] || manifest="$mod"
    WORKSPACE_ROOTS+=("$mod|$manifest")
  done
  NOTES="settings.gradle declares ${#WORKSPACE_ROOTS[@]} subproject(s)"
  return 0
}

# --- Maven multi-module ---
detect_maven_multi() {
  [[ -f "$TARGET/pom.xml" ]] || return 1
  file_contains "$TARGET/pom.xml" "<modules>" || return 1
  local -a modules=()
  local raw
  while IFS= read -r raw; do
    modules+=("$raw")
  done < <(
    awk '/<modules>/,/<\/modules>/' "$TARGET/pom.xml" 2>/dev/null \
      | grep -oE "<module>[^<]+</module>" \
      | sed -E 's|<module>([^<]+)</module>|\1|'
  )
  (( ${#modules[@]} > 0 )) || return 1
  WORKSPACE_TYPE=maven-multi
  CONFIDENCE=high
  local mod
  for mod in "${modules[@]}"; do
    [[ -n "$mod" ]] || continue
    [[ -d "$TARGET/$mod" ]] || continue
    [[ -f "$TARGET/$mod/pom.xml" ]] || continue
    WORKSPACE_ROOTS+=("$mod|$mod/pom.xml")
  done
  NOTES="root pom.xml declares ${#WORKSPACE_ROOTS[@]} module(s)"
  return 0
}

# --- Cargo workspaces ---
detect_cargo_workspaces() {
  [[ -f "$TARGET/Cargo.toml" ]] || return 1
  file_contains "$TARGET/Cargo.toml" "[workspace]" || return 1
  # Extract members = ["…", "…"]. Supports multi-line arrays.
  local raw
  raw=$(awk '
    /^\[workspace\]/     { in_ws=1; next }
    /^\[/                { in_ws=0 }
    in_ws && /members[[:space:]]*=[[:space:]]*\[/  { collecting=1; sub(/.*members[[:space:]]*=[[:space:]]*\[/, ""); }
    collecting {
      printf "%s ", $0
      if (match($0, /\]/)) { collecting=0 }
    }
  ' "$TARGET/Cargo.toml" 2>/dev/null)
  local -a patterns=()
  while IFS= read -r p; do
    [[ -n "$p" ]] && patterns+=("$p")
  done < <(echo "$raw" | grep -oE '"[^"]+"' | tr -d '"')
  # Some Cargo workspaces use `default-members`; only members implies enumeration.
  (( ${#patterns[@]} > 0 )) || return 1
  WORKSPACE_TYPE=cargo
  CONFIDENCE=high
  add_roots_from_globs "Cargo.toml" "${patterns[@]}"
  NOTES="Cargo.toml [workspace] declares ${#WORKSPACE_ROOTS[@]} member(s)"
  return 0
}

# --- Go workspaces ---
detect_go_workspaces() {
  [[ -f "$TARGET/go.work" ]] || return 1
  local -a modules=()
  local raw
  # Two shapes: `use ./path` on one line, or a `use ( ... )` block.
  while IFS= read -r raw; do
    modules+=("$raw")
  done < <(
    awk '
      /^use[[:space:]]*\(/         { in_block=1; next }
      in_block && /^\)/            { in_block=0; next }
      in_block                     { sub(/[[:space:]]*\/\/.*$/,""); if ($1 != "") print $1 }
      /^use[[:space:]]+[^(]/       { sub(/[[:space:]]*\/\/.*$/,""); print $2 }
    ' "$TARGET/go.work" 2>/dev/null \
      | sed 's|^\./||'
  )
  (( ${#modules[@]} > 0 )) || return 1
  WORKSPACE_TYPE=go-work
  CONFIDENCE=high
  local mod
  for mod in "${modules[@]}"; do
    [[ -n "$mod" ]] || continue
    [[ -d "$TARGET/$mod" ]] || continue
    [[ -f "$TARGET/$mod/go.mod" ]] || continue
    WORKSPACE_ROOTS+=("$mod|$mod/go.mod")
  done
  NOTES="go.work declares ${#WORKSPACE_ROOTS[@]} module(s)"
  return 0
}

# --- Composer path repos (PHP) ---
# composer.json with repositories: [{ type: "path", url: "packages/*" }]
detect_composer_multi() {
  [[ -f "$TARGET/composer.json" ]] || return 1
  file_contains "$TARGET/composer.json" '"path"' || return 1
  if ! have_python3; then
    return 1
  fi
  local -a patterns=()
  local url
  while IFS= read -r url; do
    [[ -n "$url" ]] && patterns+=("$url")
  done < <(python3 - "$TARGET/composer.json" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
    for r in (d.get('repositories') or []):
        if isinstance(r, dict) and r.get('type') == 'path':
            u = r.get('url')
            if isinstance(u, str): print(u)
except Exception:
    pass
PY
  )
  (( ${#patterns[@]} > 0 )) || return 1
  WORKSPACE_TYPE=composer-multi
  CONFIDENCE=high
  add_roots_from_globs "composer.json" "${patterns[@]}"
  NOTES="composer.json declares ${#WORKSPACE_ROOTS[@]} path repositor(y|ies)"
  return 0
}

# ---------- dispatch ----------
#
# Order: Bazel first (special case), then layered JS tools (rush → nx →
# turbo → lerna), then base JS workspace managers (pnpm → package.json),
# then JVM (gradle → maven), then Rust, Go, PHP.
#
# First match wins.

detect_bazel               || \
detect_rush                || \
detect_nx                  || \
detect_turbo               || \
detect_lerna               || \
detect_pnpm_workspaces     || \
detect_pkgjson_workspaces  || \
detect_gradle_multi        || \
detect_maven_multi         || \
detect_cargo_workspaces    || \
detect_go_workspaces       || \
detect_composer_multi      || \
true   # No detector matched — WORKSPACE_TYPE remains "none".

# For a flat repo (or Bazel), NOTES stays empty. Populate a default.
if [[ -z $NOTES ]]; then
  if [[ $WORKSPACE_TYPE == "none" ]]; then
    NOTES="no monorepo topology detected"
  fi
fi

# ---------- per-workspace stack detection ----------
#
# For each detected workspace root, invoke detect-stack.sh so per-workspace
# stacks appear inline in the JSON. Failures degrade to
# {"stack":"unknown"} rather than aborting the whole detection.

ROOT_ENTRIES=()   # per-root JSON fragments (assembled below)
for entry in "${WORKSPACE_ROOTS[@]:-}"; do
  [[ -n $entry ]] || continue
  IFS='|' read -r RPATH RMANIFEST <<<"$entry"
  ABS="$TARGET/$RPATH"
  STACK_JSON='{"stack":"unknown"}'
  if [[ -d $ABS ]]; then
    if out=$("$DETECT_STACK" "$ABS" 2>/dev/null); then
      STACK_JSON=$out
    fi
  fi
  ROOT_ENTRIES+=("$(printf '    {"path": "%s", "manifest": "%s", "stack": %s}' \
    "$(json_escape "$RPATH")" \
    "$(json_escape "$RMANIFEST")" \
    "$STACK_JSON")")
done

# ---------- emit JSON ----------

printf '{\n'
printf '  "type": "%s",\n' "$(json_escape "$WORKSPACE_TYPE")"
printf '  "roots": ['
if (( ${#ROOT_ENTRIES[@]} > 0 )); then
  printf '\n'
  # shellcheck disable=SC2059
  printf '%s' "${ROOT_ENTRIES[0]}"
  for ((i=1; i<${#ROOT_ENTRIES[@]}; i++)); do
    printf ',\n%s' "${ROOT_ENTRIES[$i]}"
  done
  printf '\n  '
fi
printf '],\n'
printf '  "detector_confidence": "%s",\n' "$(json_escape "$CONFIDENCE")"
printf '  "notes": "%s"\n' "$(json_escape "$NOTES")"
printf '}\n'

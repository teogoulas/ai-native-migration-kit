#!/usr/bin/env bash
# detect-stack.sh — detect the primary stack, framework, and versions of a target repository.
#
# Emits a single JSON object on stdout:
#   {
#     "stack": "java|node|python|go|rust|ruby|php|unknown",
#     "framework": "spring-boot|next|react|django|fastapi|flask|actix|rails|laravel|null",
#     "versions": {"language": "3.11.4", "framework": "3.2.1"} (best-effort; may be null),
#     "package_manager": "maven|gradle|npm|pnpm|yarn|pip|poetry|uv|cargo|go|bundler|composer|null",
#     "test_framework": "junit|jest|vitest|pytest|go-test|cargo-test|rspec|phpunit|null"
#   }
#
# Best-effort. Never fails on ambiguous input — returns {"stack":"unknown"} instead.
# Consumers (ai-native-verify, workflow A08 judge) treat "unknown" as skip.
#
# Contract:
#   - Input: single positional argument, path to target repo root.
#   - Output: one JSON object on stdout, exit 0.
#   - Errors: exit 1 with human-readable message on stderr for preflight failures
#     (path missing, not readable). NEVER exit non-zero for "couldn't detect stack".
set -euo pipefail

# ---------- helpers ----------

die() {
  printf 'detect-stack: %s\n' "$*" >&2
  exit 1
}

# jq is preferred but not required — we assemble JSON manually to keep the script
# runnable in minimal environments. String values get quoted; null and object values
# do not.
json_escape() {
  # Escape backslashes, quotes, and control chars for JSON string embedding.
  # Portable across bash 3.2+ (macOS).
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

emit_field() {
  # emit_field <key> <value> [type]
  # type: "string" (default) → quoted; "raw" → verbatim (null, numbers, nested objects)
  local key=$1
  local value=$2
  local type=${3:-string}
  if [[ $type == "raw" ]]; then
    printf '  "%s": %s' "$key" "$value"
  else
    printf '  "%s": "%s"' "$key" "$(json_escape "$value")"
  fi
}

# Extract a version-like string from a file using a regex. Returns the first match
# on stdout, or nothing (silent) if no match. Portable grep (no -P).
extract_version() {
  # extract_version <file> <regex-with-capture>
  # The regex must produce a version-like string as $1 in a sed s/re/\1/p equivalent.
  local file=$1
  local sed_expr=$2
  [[ -f $file ]] || return 0
  sed -n "$sed_expr" "$file" 2>/dev/null | head -n1
}

file_contains() {
  # file_contains <file> <fixed-string>
  local file=$1
  local needle=$2
  [[ -f $file ]] || return 1
  grep -qF -- "$needle" "$file" 2>/dev/null
}

any_file_matches() {
  # any_file_matches <target> <glob>
  # Returns 0 (found) or 1 (not found). Uses find, not shell globbing, to avoid
  # traversal into node_modules/.venv/etc.
  local target=$1
  local pattern=$2
  find "$target" -maxdepth 4 \
    \( -name node_modules -o -name .venv -o -name venv -o -name target -o -name .git -o -name dist -o -name build \) -prune \
    -o -type f -name "$pattern" -print 2>/dev/null \
    | head -n1 | grep -q .
}

# ---------- preflight ----------

if [[ $# -lt 1 ]]; then
  die "usage: detect-stack.sh <target-repo-path>"
fi

TARGET=$1
[[ -e $TARGET ]] || die "path does not exist: $TARGET"
[[ -d $TARGET ]] || die "path is not a directory: $TARGET"
[[ -r $TARGET ]] || die "path is not readable: $TARGET"

# Resolve to absolute path for downstream consistency.
if command -v realpath >/dev/null 2>&1; then
  TARGET=$(realpath "$TARGET")
else
  TARGET=$(cd "$TARGET" && pwd)
fi

# ---------- detection ----------

STACK=unknown
FRAMEWORK=null
LANG_VERSION=null
FRAMEWORK_VERSION=null
PACKAGE_MANAGER=null
TEST_FRAMEWORK=null

# --- Java (Maven / Gradle) ---
if [[ -f "$TARGET/pom.xml" ]] || [[ -f "$TARGET/build.gradle" ]] || [[ -f "$TARGET/build.gradle.kts" ]]; then
  STACK=java

  if [[ -f "$TARGET/pom.xml" ]]; then
    PACKAGE_MANAGER=maven
    # Spring Boot parent detection
    if file_contains "$TARGET/pom.xml" "spring-boot-starter-parent"; then
      FRAMEWORK=spring-boot
      v=$(extract_version "$TARGET/pom.xml" 's|.*<artifactId>spring-boot-starter-parent</artifactId>.*<version>\([^<]*\)</version>.*|\1|p')
      # Some pom files put version on the next line; try a two-line fallback via awk.
      if [[ -z ${v:-} ]]; then
        v=$(awk '/<artifactId>spring-boot-starter-parent<\/artifactId>/{f=1;next} f && /<version>/{sub(/.*<version>/,""); sub(/<\/version>.*/,""); print; exit}' "$TARGET/pom.xml" 2>/dev/null || true)
      fi
      [[ -n ${v:-} ]] && FRAMEWORK_VERSION=$v
    fi
    # Java version — from <java.version> property or <maven.compiler.source>
    jv=$(extract_version "$TARGET/pom.xml" 's|.*<java\.version>\([^<]*\)</java\.version>.*|\1|p')
    [[ -z ${jv:-} ]] && jv=$(extract_version "$TARGET/pom.xml" 's|.*<maven\.compiler\.source>\([^<]*\)</maven\.compiler\.source>.*|\1|p')
    [[ -n ${jv:-} ]] && LANG_VERSION=$jv
  else
    PACKAGE_MANAGER=gradle
    gradle_file="$TARGET/build.gradle"
    [[ ! -f $gradle_file ]] && gradle_file="$TARGET/build.gradle.kts"
    if file_contains "$gradle_file" "org.springframework.boot"; then
      FRAMEWORK=spring-boot
    fi
  fi

  # Test framework detection
  if any_file_matches "$TARGET" "*.java" && grep -rq -l "org.junit" "$TARGET/src" 2>/dev/null; then
    TEST_FRAMEWORK=junit
  fi

# --- Node.js ---
elif [[ -f "$TARGET/package.json" ]]; then
  STACK=node

  # package_manager detection by lockfile
  if [[ -f "$TARGET/pnpm-lock.yaml" ]]; then
    PACKAGE_MANAGER=pnpm
  elif [[ -f "$TARGET/yarn.lock" ]]; then
    PACKAGE_MANAGER=yarn
  elif [[ -f "$TARGET/bun.lockb" ]] || [[ -f "$TARGET/bun.lock" ]]; then
    PACKAGE_MANAGER=bun
  else
    PACKAGE_MANAGER=npm
  fi

  # Framework detection — check dependencies section for known frameworks
  # We deliberately match on quoted keys to avoid false positives in comments.
  if file_contains "$TARGET/package.json" '"next"'; then
    FRAMEWORK=next
    fv=$(extract_version "$TARGET/package.json" 's|.*"next"[[:space:]]*:[[:space:]]*"\^\{0,1\}~\{0,1\}\([^"]*\)".*|\1|p')
    [[ -n ${fv:-} ]] && FRAMEWORK_VERSION=$fv
  elif file_contains "$TARGET/package.json" '"@remix-run/react"'; then
    FRAMEWORK=remix
  elif file_contains "$TARGET/package.json" '"@nestjs/core"'; then
    FRAMEWORK=nestjs
  elif file_contains "$TARGET/package.json" '"express"'; then
    FRAMEWORK=express
  elif file_contains "$TARGET/package.json" '"react"' && ! file_contains "$TARGET/package.json" '"next"'; then
    FRAMEWORK=react
  elif file_contains "$TARGET/package.json" '"vue"'; then
    FRAMEWORK=vue
  elif file_contains "$TARGET/package.json" '"svelte"'; then
    FRAMEWORK=svelte
  fi

  # Node engine version
  nv=$(extract_version "$TARGET/package.json" 's|.*"node"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')
  [[ -n ${nv:-} ]] && LANG_VERSION=$nv

  # Test framework
  if file_contains "$TARGET/package.json" '"vitest"'; then
    TEST_FRAMEWORK=vitest
  elif file_contains "$TARGET/package.json" '"jest"'; then
    TEST_FRAMEWORK=jest
  elif file_contains "$TARGET/package.json" '"mocha"'; then
    TEST_FRAMEWORK=mocha
  elif file_contains "$TARGET/package.json" '"@playwright/test"'; then
    TEST_FRAMEWORK=playwright
  fi

# --- Python ---
elif [[ -f "$TARGET/pyproject.toml" ]] || [[ -f "$TARGET/setup.py" ]] || [[ -f "$TARGET/setup.cfg" ]] || [[ -f "$TARGET/requirements.txt" ]]; then
  STACK=python

  if [[ -f "$TARGET/pyproject.toml" ]]; then
    if file_contains "$TARGET/pyproject.toml" "[tool.poetry]"; then
      PACKAGE_MANAGER=poetry
    elif file_contains "$TARGET/pyproject.toml" "[tool.uv]"; then
      PACKAGE_MANAGER=uv
    elif file_contains "$TARGET/pyproject.toml" "[tool.hatch"; then
      PACKAGE_MANAGER=hatch
    else
      PACKAGE_MANAGER=pip
    fi
    # Python version constraint
    pv=$(extract_version "$TARGET/pyproject.toml" 's|.*python[[:space:]]*=[[:space:]]*"\([^"]*\)".*|\1|p' | head -n1)
    [[ -n ${pv:-} ]] && LANG_VERSION=$pv
  else
    PACKAGE_MANAGER=pip
  fi

  # Framework detection via requirements files / pyproject
  for f in "$TARGET/pyproject.toml" "$TARGET/requirements.txt" "$TARGET/setup.py" "$TARGET/setup.cfg" "$TARGET/Pipfile"; do
    [[ -f $f ]] || continue
    if file_contains "$f" "django"; then FRAMEWORK=django; break; fi
    if file_contains "$f" "fastapi"; then FRAMEWORK=fastapi; break; fi
    if file_contains "$f" "flask" && ! file_contains "$f" "flaskr"; then FRAMEWORK=flask; break; fi
  done

  # Test framework
  if file_contains "$TARGET/pyproject.toml" "pytest" 2>/dev/null || any_file_matches "$TARGET" "conftest.py"; then
    TEST_FRAMEWORK=pytest
  elif any_file_matches "$TARGET" "test_*.py"; then
    TEST_FRAMEWORK=unittest
  fi

# --- Go ---
elif [[ -f "$TARGET/go.mod" ]]; then
  STACK=go
  PACKAGE_MANAGER=go
  # go.mod first line: "go 1.21"
  gv=$(extract_version "$TARGET/go.mod" 's|^go[[:space:]]*\([0-9][0-9.]*\).*|\1|p')
  [[ -n ${gv:-} ]] && LANG_VERSION=$gv
  if any_file_matches "$TARGET" "*_test.go"; then
    TEST_FRAMEWORK=go-test
  fi

# --- Rust ---
elif [[ -f "$TARGET/Cargo.toml" ]]; then
  STACK=rust
  PACKAGE_MANAGER=cargo
  # rust-toolchain.toml or rust-version in Cargo.toml
  rv=$(extract_version "$TARGET/Cargo.toml" 's|^rust-version[[:space:]]*=[[:space:]]*"\([^"]*\)".*|\1|p')
  [[ -z ${rv:-} && -f "$TARGET/rust-toolchain.toml" ]] && rv=$(extract_version "$TARGET/rust-toolchain.toml" 's|^channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*|\1|p')
  [[ -n ${rv:-} ]] && LANG_VERSION=$rv
  if file_contains "$TARGET/Cargo.toml" "actix-web"; then FRAMEWORK=actix; fi
  if file_contains "$TARGET/Cargo.toml" "axum"; then FRAMEWORK=axum; fi
  if file_contains "$TARGET/Cargo.toml" "rocket"; then FRAMEWORK=rocket; fi
  TEST_FRAMEWORK=cargo-test

# --- Ruby ---
elif [[ -f "$TARGET/Gemfile" ]]; then
  STACK=ruby
  PACKAGE_MANAGER=bundler
  if file_contains "$TARGET/Gemfile" "rails"; then FRAMEWORK=rails; fi
  if file_contains "$TARGET/Gemfile" "sinatra"; then FRAMEWORK=sinatra; fi
  if file_contains "$TARGET/Gemfile" "rspec"; then TEST_FRAMEWORK=rspec; fi
  # Ruby version
  if [[ -f "$TARGET/.ruby-version" ]]; then
    LANG_VERSION=$(head -n1 "$TARGET/.ruby-version" | tr -d '[:space:]')
  fi

# --- PHP ---
elif [[ -f "$TARGET/composer.json" ]]; then
  STACK=php
  PACKAGE_MANAGER=composer
  if file_contains "$TARGET/composer.json" "laravel/framework"; then FRAMEWORK=laravel; fi
  if file_contains "$TARGET/composer.json" "symfony/symfony"; then FRAMEWORK=symfony; fi
  if file_contains "$TARGET/composer.json" "phpunit/phpunit"; then TEST_FRAMEWORK=phpunit; fi
fi

# ---------- emit JSON ----------

# Build versions object.
if [[ $LANG_VERSION == null && $FRAMEWORK_VERSION == null ]]; then
  VERSIONS_JSON=null
else
  lv_json=$([[ $LANG_VERSION == null ]] && echo null || printf '"%s"' "$(json_escape "$LANG_VERSION")")
  fv_json=$([[ $FRAMEWORK_VERSION == null ]] && echo null || printf '"%s"' "$(json_escape "$FRAMEWORK_VERSION")")
  VERSIONS_JSON=$(printf '{"language": %s, "framework": %s}' "$lv_json" "$fv_json")
fi

# framework, package_manager, test_framework: string or null
framework_json=$([[ $FRAMEWORK == null ]] && echo null || printf '"%s"' "$(json_escape "$FRAMEWORK")")
pm_json=$([[ $PACKAGE_MANAGER == null ]] && echo null || printf '"%s"' "$(json_escape "$PACKAGE_MANAGER")")
tf_json=$([[ $TEST_FRAMEWORK == null ]] && echo null || printf '"%s"' "$(json_escape "$TEST_FRAMEWORK")")

# Print JSON. Ordered fields for readability; consumers parse by key so order is cosmetic.
printf '{\n'
emit_field "stack" "$STACK"; printf ',\n'
emit_field "framework" "$framework_json" raw; printf ',\n'
emit_field "versions" "$VERSIONS_JSON" raw; printf ',\n'
emit_field "package_manager" "$pm_json" raw; printf ',\n'
emit_field "test_framework" "$tf_json" raw; printf '\n'
printf '}\n'

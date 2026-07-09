#!/usr/bin/env bash
# bootstrap.sh — apply plugins/ai-native-migration/templates/* into a target repo, one template
# at a time, with per-file confirmation.
#
# Invoked by SKILL.md step 7 when the user passes --apply. Enforces the
# human-in-the-loop invariants from spec §9:
#   - Every application is a human decision.
#   - No batch mode, no --yes-to-all.
#   - Security-sensitive templates are always interactive regardless of
#     any flag (.claude/settings.json, .github/workflows/**, .mcp.json).
#   - Files written are UNSTAGED — the human runs `git add` themselves.
#
# See `bootstrap.sh --help` for full usage.

set -euo pipefail

# ---------- locate helpers + templates ----------

_resolve_dir() {
  local src=$1
  while [[ -L $src ]]; do
    local dir; dir=$(cd -P "$(dirname "$src")" && pwd)
    src=$(readlink "$src"); [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}
SCRIPT_DIR=$(_resolve_dir "${BASH_SOURCE[0]}")
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

readonly SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
readonly TEMPLATES_DIR="$SKILL_DIR/templates"

# ---------- usage ----------

usage() {
  cat <<'EOF'
bootstrap.sh — apply ai-native-migration-kit templates into a target repo

Usage:
  bootstrap.sh --target=<path> [--template=<name>] [--project-name=<name>] [--stack=<stack>]
  bootstrap.sh --help

Options:
  --target=<path>          Target repo to bootstrap templates into. Required.
  --template=<name>        Apply ONE named template only. Repeatable.
                           Names are the paths under plugins/ai-native-migration/templates/, e.g.
                           AGENTS.md.tmpl, .editorconfig.tmpl, .devcontainer,
                           docs/TESTING.md.tmpl.
  --project-name=<name>    Value for {{project_name}} placeholder.
                           Defaults to the target repo's basename.
  --stack=<stack>          Value for {{stack}} placeholder.
                           Defaults to output of detect-stack.sh on target.
  --list                   List all available templates and exit.
  --help                   Print this message and exit.

Behavior:
  For each template selected, bootstrap.sh:
    1. Renders {{project_name}} and {{stack}} placeholders.
    2. Shows a diff between the rendered template and the target's
       current state (which may be "file does not exist").
    3. Prompts: apply / skip / edit-then-apply.
    4. On apply, writes the file UNSTAGED into the target repo.

  Security-sensitive templates ALWAYS require confirmation, regardless
  of any flag:
    .claude/settings.json.tmpl
    .mcp.json.tmpl
    (anything under .github/workflows/, if such templates are added)

  bootstrap.sh never overwrites without confirmation, never batches
  applications, and never modifies files under an existing .git/ dir
  other than the intended targets.

Exit codes:
  0  All selected templates were processed (applied, skipped, or
     deferred by the user)
  1  Runtime error (target missing, template missing, unwritable)
  2  User aborted the session (Ctrl-C or explicit quit)
  3  Preflight/usage failure (bad arguments)
EOF
}

# ---------- argument parsing ----------

TARGET=""
PROJECT_NAME=""
STACK=""
LIST_ONLY=0
SELECTED_TEMPLATES=()

while (( $# > 0 )); do
  case $1 in
    --help|-h)             usage; exit 0 ;;
    --target=*)            TARGET=${1#--target=} ;;
    --target)              shift; TARGET=${1:-} ;;
    --template=*)          SELECTED_TEMPLATES+=("${1#--template=}") ;;
    --template)            shift; SELECTED_TEMPLATES+=("${1:-}") ;;
    --project-name=*)      PROJECT_NAME=${1#--project-name=} ;;
    --project-name)        shift; PROJECT_NAME=${1:-} ;;
    --stack=*)             STACK=${1#--stack=} ;;
    --stack)               shift; STACK=${1:-} ;;
    --list)                LIST_ONLY=1 ;;
    --)                    shift; break ;;
    -*)                    die --code=3 "unknown option: $1 (see --help)" ;;
    *)                     die --code=3 "unexpected argument: $1" ;;
  esac
  shift
done

# ---------- template registry ----------
#
# Every path here is relative to $TEMPLATES_DIR. Order matters for --list
# and for the "all templates" walk. Names ending in .tmpl are rendered
# through placeholder substitution; other files (.devcontainer/*) are
# copied verbatim.
#
# always_interactive lists paths that must prompt for confirmation
# regardless of any flag — the human-in-the-loop invariant.

TEMPLATES=(
  # (template_path)                              (target_path relative to repo)
  "AGENTS.md.tmpl                                AGENTS.md"
  ".editorconfig.tmpl                            .editorconfig"
  ".gitmessage.tmpl                              .gitmessage"
  ".coderabbit.yaml.tmpl                         .coderabbit.yaml"
  ".claude/settings.json.tmpl                    .claude/settings.json"
  ".mcp.json.tmpl                                .mcp.json"
  ".devcontainer/devcontainer.json               .devcontainer/devcontainer.json"
  ".devcontainer/Dockerfile                      .devcontainer/Dockerfile"
  ".pre-commit-config.yaml.tmpl                  .pre-commit-config.yaml"
  "docs/ARCHITECTURE.md.tmpl                     docs/ARCHITECTURE.md"
  "docs/DEVELOPMENT.md.tmpl                      docs/DEVELOPMENT.md"
  "docs/TESTING.md.tmpl                          docs/TESTING.md"
  "docs/PRECOMMIT.md.tmpl                        docs/PRECOMMIT.md"
  "scripts/setup-precommit.sh.tmpl               scripts/setup-precommit.sh"
  "scripts/onboarding-check.sh.tmpl              scripts/onboarding-check.sh"
)

# Paths that ALWAYS prompt for confirmation. Match the *template* name.
ALWAYS_INTERACTIVE=(
  ".claude/settings.json.tmpl"
  ".mcp.json.tmpl"
)

# Paths that need executable bit after write.
EXECUTABLE_TARGETS=(
  "scripts/setup-precommit.sh"
  "scripts/onboarding-check.sh"
)

# ---------- helpers ----------

# Get the target-relative path for a template. Trims whitespace-separated
# entries from the TEMPLATES registry.
target_for() {
  local tmpl=$1
  for entry in "${TEMPLATES[@]}"; do
    # shellcheck disable=SC2206
    local parts=($entry)
    if [[ ${parts[0]} == "$tmpl" ]]; then
      printf '%s' "${parts[1]}"
      return 0
    fi
  done
  return 1
}

# List every registered template.
list_templates() {
  printf '%sAvailable templates%s (in %s):\n\n' "$(_bold)" "$(_reset)" "$TEMPLATES_DIR"
  for entry in "${TEMPLATES[@]}"; do
    # shellcheck disable=SC2206
    local parts=($entry)
    local tmpl=${parts[0]}
    local dest=${parts[1]}
    local marker=""
    if [[ " ${ALWAYS_INTERACTIVE[*]} " == *" $tmpl "* ]]; then
      marker="  $(_yellow)[always interactive]$(_reset)"
    fi
    printf '  %-52s → %s%s\n' "$tmpl" "$dest" "$marker"
  done
  printf '\n'
}

_is_executable_target() {
  local dest=$1
  for e in "${EXECUTABLE_TARGETS[@]}"; do
    [[ $e == "$dest" ]] && return 0
  done
  return 1
}

# Color helpers (stdout-TTY-aware).
_bold()   { [[ -t 1 ]] && printf '\033[1m'  || true; }
_dim()    { [[ -t 1 ]] && printf '\033[90m' || true; }
_green()  { [[ -t 1 ]] && printf '\033[32m' || true; }
_yellow() { [[ -t 1 ]] && printf '\033[33m' || true; }
_red()    { [[ -t 1 ]] && printf '\033[31m' || true; }
_cyan()   { [[ -t 1 ]] && printf '\033[36m' || true; }
_reset()  { [[ -t 1 ]] && printf '\033[0m'  || true; }

# Render a template file (substitute placeholders) to stdout.
# Verbatim copy for non-.tmpl files.
render_template() {
  local src=$1
  case $src in
    *.tmpl)
      sed \
        -e "s|{{project_name}}|${PROJECT_NAME}|g" \
        -e "s|{{stack}}|${STACK}|g" \
        "$src"
      ;;
    *)
      cat "$src"
      ;;
  esac
}

# ---------- --list short-circuit ----------

if (( LIST_ONLY )); then
  list_templates
  exit 0
fi

# ---------- preflight ----------

[[ -n $TARGET ]] || die --code=3 "missing --target (see --help)"
[[ -e $TARGET ]] || die --code=3 "target does not exist: $TARGET"
[[ -d $TARGET ]] || die --code=3 "target is not a directory: $TARGET"
[[ -w $TARGET ]] || die --code=3 "target is not writable: $TARGET"

TARGET=$(absolute_path "$TARGET")

if ! is_git_repo "$TARGET"; then
  log_info "warning: $TARGET is not a git repository"
  log_info "         bootstrap will still write files, but there will be no git tracking of changes"
  printf 'proceed anyway? [y/N] '
  read -r ans
  [[ $ans == [yY] ]] || die --code=2 "aborted by user"
fi

# Default project name = basename of target
if [[ -z $PROJECT_NAME ]]; then
  PROJECT_NAME=$(basename "$TARGET")
fi

# Default stack = detect-stack.sh output
if [[ -z $STACK ]]; then
  if [[ -x "$SCRIPT_DIR/detect-stack.sh" ]]; then
    local_stack_json=$("$SCRIPT_DIR/detect-stack.sh" "$TARGET" 2>/dev/null || echo '{"stack":"unknown"}')
    STACK=$(printf '%s' "$local_stack_json" \
      | grep -oE '"stack"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -n1 \
      | sed 's/.*"\([^"]*\)"$/\1/' \
      || true)
    [[ -z $STACK ]] && STACK=unknown
  else
    STACK=unknown
  fi
fi

log_info "$(_bold)bootstrap$(_reset) $(_dim)into$(_reset) $TARGET"
log_info "$(_dim)project_name:$(_reset) $PROJECT_NAME"
log_info "$(_dim)stack:$(_reset)        $STACK"
log_info ""

# Decide which templates to walk. Empty selection = ALL.
WALK_TEMPLATES=()
if (( ${#SELECTED_TEMPLATES[@]} == 0 )); then
  for entry in "${TEMPLATES[@]}"; do
    # shellcheck disable=SC2206
    parts=($entry)
    WALK_TEMPLATES+=("${parts[0]}")
  done
else
  for t in "${SELECTED_TEMPLATES[@]}"; do
    if ! target_for "$t" >/dev/null; then
      die --code=3 "unknown template: $t (see --list)"
    fi
    WALK_TEMPLATES+=("$t")
  done
fi

# ---------- per-template application ----------
#
# For each template:
#   1. Render placeholders (or copy verbatim for non-.tmpl files).
#   2. If target file already exists, compute a diff. Otherwise diff
#      against /dev/null (all-added view).
#   3. Show the diff (paged if long).
#   4. Prompt for apply / skip / edit-then-apply / quit.
#   5. On apply, write the file unstaged.
#   6. Fix executable bit for scripts.
#
# The prompt is the ONLY place a template can transition from
# "candidate" to "written". Every application is a human decision.

count_applied=0
count_skipped=0
count_edited=0

# Temp dir for rendered/edited files; cleaned on any exit.
TMP_DIR=$(mktemp -d -t bootstrap.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

for tmpl in "${WALK_TEMPLATES[@]}"; do
  src="$TEMPLATES_DIR/$tmpl"
  dest_rel=$(target_for "$tmpl")
  dest="$TARGET/$dest_rel"

  # Sanity: the template must exist.
  if [[ ! -f $src ]]; then
    log_info "$(_red)ERROR:$(_reset) template $tmpl does not exist at $src (skipping)"
    continue
  fi

  # Render to a temp file so we can diff and edit.
  # Preserve directory structure inside TMP_DIR to keep names readable.
  rendered="$TMP_DIR/$(printf '%s' "$tmpl" | tr '/' '_')"
  render_template "$src" >"$rendered"

  # Detect always-interactive.
  is_sensitive=0
  for a in "${ALWAYS_INTERACTIVE[@]}"; do
    [[ $a == "$tmpl" ]] && is_sensitive=1
  done

  printf '\n%s─── %s → %s%s%s ───%s\n' \
    "$(_bold)" "$tmpl" "$(_cyan)" "$dest_rel" "$(_reset)$(_bold)" "$(_reset)"

  if (( is_sensitive )); then
    printf '%s[SENSITIVE — always interactive, cannot be batched]%s\n' "$(_yellow)" "$(_reset)"
  fi

  # Show diff. Use --new-file so a nonexistent target diffs as "all added".
  if [[ -f $dest ]]; then
    printf '%starget file exists — showing diff (target → rendered template)%s\n\n' "$(_dim)" "$(_reset)"
    diff -u "$dest" "$rendered" | head -n 200 || true
  else
    printf '%starget does not exist — showing full rendered content%s\n\n' "$(_dim)" "$(_reset)"
    head -n 200 "$rendered" | sed 's/^/  /'
  fi

  # Prompt.
  while true; do
    printf '\n%s[a]pply / [s]kip / [e]dit-then-apply / [q]uit%s ' "$(_bold)" "$(_reset)"
    read -r ans
    case ${ans,,} in
      a|apply)
        # Ensure destination directory exists.
        mkdir -p "$(dirname "$dest")"
        cp "$rendered" "$dest"
        # Fix exec bit for scripts.
        if _is_executable_target "$dest_rel"; then
          chmod +x "$dest"
        fi
        printf '%s✓ applied%s → %s\n' "$(_green)" "$(_reset)" "$dest_rel"
        (( ++count_applied ))
        break
        ;;
      s|skip|"")
        printf '%s· skipped%s\n' "$(_dim)" "$(_reset)"
        (( ++count_skipped ))
        break
        ;;
      e|edit)
        # Open $EDITOR (default: nano) on the rendered file.
        editor=${EDITOR:-nano}
        printf '%sopening %s in %s ...%s\n' "$(_dim)" "$(basename "$rendered")" "$editor" "$(_reset)"
        # If EDITOR is not on PATH, fall back to nano; if that fails, warn and re-prompt.
        if ! command -v "$editor" >/dev/null 2>&1; then
          log_info "$(_yellow)warning:$(_reset) \$EDITOR ($editor) not found; trying nano"
          editor=nano
        fi
        if command -v "$editor" >/dev/null 2>&1; then
          "$editor" "$rendered" </dev/tty >/dev/tty 2>/dev/tty || true
          (( ++count_edited ))
        else
          log_info "$(_red)error:$(_reset) no editor available (\$EDITOR unset and nano missing); skipping"
          (( ++count_skipped ))
          break
        fi
        # After edit, apply the file.
        mkdir -p "$(dirname "$dest")"
        cp "$rendered" "$dest"
        if _is_executable_target "$dest_rel"; then
          chmod +x "$dest"
        fi
        printf '%s✓ edited and applied%s → %s\n' "$(_green)" "$(_reset)" "$dest_rel"
        (( ++count_applied ))
        break
        ;;
      q|quit)
        printf '%squit — remaining templates left unprocessed%s\n' "$(_yellow)" "$(_reset)"
        exit 2
        ;;
      *)
        printf '%sinvalid choice — enter a, s, e, or q%s\n' "$(_red)" "$(_reset)"
        ;;
    esac
  done
done

# ─────────────────────────────────────────────────────────────────────────
# Post-step: offer to create the CLAUDE.md → AGENTS.md symlink (D02).
#
# There is no CLAUDE.md.tmpl because the artifact is a symlink, not a file.
# If AGENTS.md was applied in this session and CLAUDE.md is missing or is
# a regular file (drift), offer to fix it. Same per-file confirmation as
# every other template.
# ─────────────────────────────────────────────────────────────────────────

if [[ -f "$TARGET/AGENTS.md" ]] && ( [[ ! -e "$TARGET/CLAUDE.md" ]] || ( [[ ! -L "$TARGET/CLAUDE.md" ]] && [[ -f "$TARGET/CLAUDE.md" ]] ) ); then
  printf '\n%s─── CLAUDE.md → AGENTS.md symlink (D02) ───%s\n' "$(_bold)" "$(_reset)"
  if [[ -f "$TARGET/CLAUDE.md" ]]; then
    printf '%sCLAUDE.md exists as a regular file — will be REPLACED with a symlink to AGENTS.md%s\n' \
      "$(_yellow)" "$(_reset)"
  else
    printf '%sCLAUDE.md is missing — will be created as a symlink to AGENTS.md%s\n' \
      "$(_dim)" "$(_reset)"
  fi
  while true; do
    printf '\n%s[a]pply / [s]kip%s ' "$(_bold)" "$(_reset)"
    read -r ans
    case ${ans,,} in
      a|apply)
        # Symlink relative to repo root so it works after clone.
        ( cd "$TARGET" && ln -sf AGENTS.md CLAUDE.md )
        printf '%s✓ CLAUDE.md → AGENTS.md%s\n' "$(_green)" "$(_reset)"
        (( ++count_applied ))
        break
        ;;
      s|skip|"")
        printf '%s· skipped%s\n' "$(_dim)" "$(_reset)"
        (( ++count_skipped ))
        break
        ;;
      *)
        printf '%sinvalid choice — enter a or s%s\n' "$(_red)" "$(_reset)"
        ;;
    esac
  done
fi

printf '\n%ssummary:%s applied=%d edited=%d skipped=%d\n' \
  "$(_bold)" "$(_reset)" "$count_applied" "$count_edited" "$count_skipped"
printf '%sfiles are unstaged — run `git status` in %s and stage what you want to commit.%s\n' \
  "$(_dim)" "$TARGET" "$(_reset)"

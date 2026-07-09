# Pre-commit

<!--
  Reference doc for the pre-commit hooks configured in
  .pre-commit-config.yaml. Judge A06 cross-references this file against
  the actual config — a workflow named here must exist in the config,
  and vice versa.
-->

## What runs

Every hook configured in `.pre-commit-config.yaml` runs on `git commit` (or `git push`, for `stages: [push]` hooks). Baseline hooks that ship with the AI-native migration kit template:

| Hook | Stage | Purpose |
|------|-------|---------|
| trailing-whitespace | commit | Strip whitespace at end of lines |
| end-of-file-fixer | commit | Ensure files end with a newline |
| check-merge-conflict | commit | Fail on merge-conflict markers left in files |
| check-added-large-files | commit | Fail on files > 500 KB (adjust in config) |
| check-yaml / check-json / check-toml | commit | Syntactic validity of config files |
| detect-private-key | commit | Fail if a private key looks committed |
| mixed-line-ending | commit | Normalize line endings to LF |
| conventional-pre-commit | commit-msg | Enforce Conventional Commits format |
| gitleaks | commit | Scan staged content for leaked secrets |
| shellcheck | commit | Lint shell scripts |
| markdownlint | commit | Lint Markdown docs |

Stack-specific hooks (eslint, ruff, mypy, spotless, ...) are configured in the same file — see the marked block in `.pre-commit-config.yaml` for the block your stack uses.

## Setup on a fresh clone

The hooks are inert until activated. Run:

```bash
./scripts/setup-precommit.sh
```

The onboarding script installs `pre-commit` itself if missing, installs the git hook, installs the commit-msg hook, and runs the hooks against every file to confirm the current tree is clean. **Do not skip this step** — a committed `.pre-commit-config.yaml` without local activation is what rubric §Part 1 D18 was written to catch.

## Running manually

```bash
# Run all hooks against all files (slower, thorough)
pre-commit run --all-files

# Run one specific hook against all files
pre-commit run trailing-whitespace --all-files

# Run all hooks against only staged files (fast, what commit does)
pre-commit run
```

## Bypassing (don't)

`git commit --no-verify` skips every hook. This is almost always the wrong choice — the hook is either right (fix the file) or wrong (fix the hook). If you find yourself bypassing repeatedly, that's the signal to update the config.

Rare legitimate cases: a WIP branch where you know the hook will fail on incomplete code but want to save progress. Even then, prefer `git stash` to `--no-verify`.

## Updating the hooks

```bash
# Bump every hook to its latest release, in place
pre-commit autoupdate

# Re-run everything to catch anything the new version flags
pre-commit run --all-files
```

Commit the resulting `.pre-commit-config.yaml` change as a `chore(deps): bump pre-commit hooks` PR. Review the diff for any new hook that changed defaults — occasionally an update introduces a stricter rule that flags previously-passing files.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `pre-commit: command not found` after clone | onboarding script never ran | run `./scripts/setup-precommit.sh` |
| Commit message rejected by conventional-pre-commit | subject doesn't start with a valid type | see the template in `.gitmessage`; run `git config commit.template .gitmessage` |
| A specific hook is much slower than the others | usually a linter running against too many files | pass `files:` glob in the config to narrow scope |
| Every commit runs hooks against files you haven't touched | the hook config has `always_run: true` on the wrong hook | remove `always_run` — the default (run only on changed files) is right for most hooks |
| Hooks fail on CI but not locally | different versions of the hook or a mismatched language runtime | pin `default_language_version` in the config; make CI run the same `pre-commit run --all-files` |

## Turning off a single hook temporarily

For one commit only:

```bash
SKIP=markdownlint git commit -m "docs: WIP"
```

Comma-separated for multiple. Never `SKIP=*` — if you need to bypass everything, this hook config isn't the right one and needs fixing.

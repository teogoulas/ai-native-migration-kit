# AGENTS.md

Context file for AI agents working inside `ai-native-migration-kit`. Symlinked as `CLAUDE.md` for Claude Code compatibility.

## Project Overview

This repository is a Claude Code skill + workflow that audits any target repository against a canonical AI-native rubric (18 deterministic structural checks + 8 semantic judges) and produces a human-reviewable migration plan. The kit's own design is in `docs/specs/01-initial-design/` — read the spec before making architectural decisions.

The kit is **stack-agnostic**: no per-stack overlay files ship. Stack-specific rigor comes from live queries to the `context7` MCP at audit time, with a thin cross-stack floor in `plugins/ai-native-migration/references/stack-generic.md` as fallback.

## Coding Standards

- **Bash**: `set -euo pipefail` at the top of every script. Prefer POSIX-portable constructs where possible; `bash` explicitly when features (arrays, `[[`) are needed. Every script must have a `--help` flag.
- **JavaScript (Workflow)**: `plugins/ai-native-migration/workflows/*.js` uses the Claude Code Workflow tool's runtime (no Node modules, no filesystem access). Structured output goes through JSON schemas at every `agent()` boundary — no free-text agent returns.
- **Markdown**: authored to pass `markdownlint`. Line length is not enforced (prose is prose); code fences are always fenced and languaged.

## Key Commands

```bash
# Deterministic audit — no LLM, no Claude Code required
./plugins/ai-native-migration/scripts/ai-native-verify [--format=text|json] <target-repo>

# Full agentic audit — invoked as a Claude Code slash command from any session
/ai-native-migration:migrate <target-repo> [--depth=light|standard|thorough]

# Interactive bootstrap of one or more templates into a target repo
./plugins/ai-native-migration/scripts/bootstrap.sh --target=<target-repo> [--template=<name>]

# End-to-end regression tests (bash + node harnesses combined)
./tests/all.sh
```

The kit installs as a Claude Code plugin — see the README for `/plugin marketplace add` and `/plugin install` syntax. No standalone installer.

## Architecture Notes

- `plugins/ai-native-migration/scripts/ai-native-verify` is the standalone deterministic layer per spec §10. Pure bash, no runtime dependency on Node/Python/Claude Code. Target repos, after migration, can wire it into their own CI/pre-push guardrails.
- `plugins/ai-native-migration/workflows/ai-native-audit.js` is the agentic layer. Spawns judges in parallel (`parallel()`), verifies findings adversarially (N-vote refuters), optionally runs a completeness critic. Depth is controlled by CLI flag.
- `plugins/ai-native-migration/references/` holds the canonical rubric (`ai-native-checklist.md`), per-judge scoring anchors (`judging-rubrics.md`), and pattern documentation (`patterns-explained.md`). Every judge sources its prompt scaffolding from a named section in these files — no inline prompts in workflow code.
- `plugins/ai-native-migration/templates/` holds the baseline artifacts that `bootstrap.sh` renders into target repos when `--apply` is used.

## Things to Avoid

- **Do not add hand-authored per-stack overlay files.** Stack-specific guidance is intentionally dynamic (live `context7` query at audit time). If you find yourself wanting to add `stack-java-spring.md`, the answer is either "improve `stack-generic.md`" or "improve the A08 judge prompt."
- **Do not add batch or `--yes` modes to `bootstrap.sh`.** Every template application is a human decision by design (spec §9). Any code path that writes multiple templates without per-file confirmation is a governance violation.
- **Do not remove citations from the plan-file output.** Every recommendation must cite a section of the kit's own rubric (spec §4.1 D01–D18 or §4.2 A01–A08). Uncited claims do not ship (spec §9.4). Citations to external curricula, training programs, or reference repositories are not permitted (see questions file Q-07).
- **Do not let judges return free-text.** Every `agent()` call in the workflow uses a JSON schema. Schema validation happens at the tool boundary; malformed output triggers automatic retry.
- **Do not commit generated audit output** (plan files) into this repo. Plan files are written into the *target* repo's `docs/plans/` directory, not here. This repo only contains the kit.

## Agent Governance

This repo protects its own source-of-truth directories via a committed `.claude/settings.json` deny-list. The rationale for landing this at the END of the build (T-32) rather than the beginning is in [Q-06 of the questions file](docs/specs/01-initial-design/01-questions-1-initial-design.md#q-06--when-does-the-self-governance-deny-list-land) — deny-lists on empty directories protect nothing, and enforcement during authoring creates friction that defeats the guardrail. Now that the sources are stable, the enforcement is on.

Two-layer pattern (advisory in AGENTS.md, enforced in settings.json — see rubric §4.1 D03 and §4.2 A03) — both layers are now aligned.

### Do not modify — enforced by `.claude/settings.json` deny-list
- `plugins/ai-native-migration/templates/**` — the templates bootstrap.sh applies into target repos
- `plugins/ai-native-migration/references/**` — the canonical rubric and judging scaffolding

Any change to a file under those trees is blocked at the tool boundary. To land a legitimate change, the engineer must:
1. Lift the corresponding entry in `.claude/settings.json` (in the same PR).
2. Make the change.
3. Restore the deny-list entry before merging.

This makes the intent explicit and reviewable — the same "policy as code" pattern the kit teaches, applied recursively to the kit itself.

### Always run before committing
- `./plugins/ai-native-migration/scripts/ai-native-verify .` — the kit must audit clean against itself (spec §14)
- `./tests/all.sh` — 89 assertions across both harnesses (verify + workflow)
- `pre-commit run --all-files` — pre-commit hooks (also runs automatically on `git commit`)

### Escalate to a human when
- Any change to `plugins/ai-native-migration/templates/**` or `plugins/ai-native-migration/references/**` (governance, per above)
- Any change to `.claude/settings.json` (policy change — see rubric §4.1 D03)
- Any change to `.github/workflows/**` (CI is enforcement infrastructure)
- Adding a new judge, changing a judge's schema, or changing the rubric in `references/ai-native-checklist.md` — these change what the kit measures

## Design Trail

Every non-obvious design decision is captured in `docs/specs/01-initial-design/01-questions-1-initial-design.md`. Before proposing a design change, read that file — the answer to "why isn't it done this way?" often lives there.

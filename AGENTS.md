# AGENTS.md

Context file for AI agents working inside `ai-native-migration-kit`. Symlinked as `CLAUDE.md` for Claude Code compatibility.

## Project Overview

This repository is a Claude Code skill + workflow that audits any target repository against a canonical AI-native rubric (18 deterministic structural checks + 8 semantic judges) and produces a human-reviewable migration plan. The kit's own design is in `docs/specs/01-initial-design/` — read the spec before making architectural decisions.

The kit is **stack-agnostic**: no per-stack overlay files ship. Stack-specific rigor comes from live queries to the `context7` MCP at audit time, with a thin cross-stack floor in `skill/references/stack-generic.md` as fallback.

## Coding Standards

- **Bash**: `set -euo pipefail` at the top of every script. Prefer POSIX-portable constructs where possible; `bash` explicitly when features (arrays, `[[`) are needed. Every script must have a `--help` flag.
- **JavaScript (Workflow)**: `skill/workflows/*.js` uses the Claude Code Workflow tool's runtime (no Node modules, no filesystem access). Structured output goes through JSON schemas at every `agent()` boundary — no free-text agent returns.
- **Markdown**: authored to pass `markdownlint`. Line length is not enforced (prose is prose); code fences are always fenced and languaged.

## Key Commands

Not yet wired — placeholders below will be filled during Phase 2+ implementation:

```bash
# Deterministic audit — no LLM, safe in CI (see spec §10)
./skill/scripts/ai-native-verify [--format=text|json] <target-repo>

# Full agentic audit — invoked as a Claude Code slash command
/ai-native-migration <target-repo> [--depth=light|standard|thorough]

# Interactive bootstrap of one or more templates into a target repo
./skill/scripts/bootstrap.sh --target=<target-repo> [--template=<name>]

# Install the skill into ~/.claude/skills/ai-native-migration/
./install.sh
```

## Architecture Notes

- `skill/scripts/ai-native-verify` is the standalone deterministic layer per spec §10. Pure bash, no runtime dependency on Node/Python/Claude Code. Target repos, after migration, can wire it into their own CI/pre-push guardrails.
- `skill/workflows/ai-native-audit.js` is the agentic layer. Spawns judges in parallel (`parallel()`), verifies findings adversarially (N-vote refuters), optionally runs a completeness critic. Depth is controlled by CLI flag.
- `skill/references/` holds the canonical rubric (`ai-native-checklist.md`), per-judge scoring anchors (`judging-rubrics.md`), and pattern documentation (`patterns-explained.md`). Every judge sources its prompt scaffolding from a named section in these files — no inline prompts in workflow code.
- `skill/templates/` holds the baseline artifacts that `bootstrap.sh` renders into target repos when `--apply` is used.

## Things to Avoid

- **Do not add hand-authored per-stack overlay files.** Stack-specific guidance is intentionally dynamic (live `context7` query at audit time). If you find yourself wanting to add `stack-java-spring.md`, the answer is either "improve `stack-generic.md`" or "improve the A08 judge prompt."
- **Do not add batch or `--yes` modes to `bootstrap.sh`.** Every template application is a human decision by design (spec §9). Any code path that writes multiple templates without per-file confirmation is a governance violation.
- **Do not remove citations from the plan-file output.** Every recommendation must cite a section of the kit's own rubric (spec §4.1 D01–D18 or §4.2 A01–A08). Uncited claims do not ship (spec §9.4). Citations to external curricula, training programs, or reference repositories are not permitted (see questions file Q-07).
- **Do not let judges return free-text.** Every `agent()` call in the workflow uses a JSON schema. Schema validation happens at the tool boundary; malformed output triggers automatic retry.
- **Do not commit generated audit output** (plan files) into this repo. Plan files are written into the *target* repo's `docs/plans/` directory, not here. This repo only contains the kit.

## Agent Governance

Per spec §12, this repo will protect its own source-of-truth directories with a `.claude/settings.json` deny-list. The enforcement layer lands as **T-32, the final task of the build** (see [task file Q-06 rationale](docs/specs/01-initial-design/01-questions-1-initial-design.md#q-06--when-does-the-self-governance-deny-list-land) — deny-lists on empty directories protect nothing, and enforcement during authoring creates friction that defeats the guardrail).

Until T-32 lands, this section is **advisory only** — the two-layer pattern (advisory in AGENTS.md, enforced in settings.json — see rubric §4.1 D03 and §4.2 A03) is applied in sequence here, not in lockstep.

### Do not modify (once T-32 lands: enforced by `.claude/settings.json` deny-list)
- `skill/templates/**`
- `skill/references/**`

To change any file under those trees after T-32, the engineer must lift the deny-list in `.claude/settings.json` in the same PR. This makes the intent explicit and reviewable.

### Always run before committing
Once the tooling lands (Phase 5):
- `./skill/scripts/ai-native-verify .` — the kit must audit clean against itself (spec §14)
- `pre-commit run --all-files` — once the pre-commit config is set up

### Escalate to a human when
- Any change to `skill/templates/**` or `skill/references/**` (governance, per above)
- Any change to `.claude/settings.json` (policy change — see rubric §4.1 D03)
- Any change to `.github/workflows/**` (CI is enforcement infrastructure)
- Adding a new judge, changing a judge's schema, or changing the rubric in `references/ai-native-checklist.md` — these change what the kit measures

## Design Trail

Every non-obvious design decision is captured in `docs/specs/01-initial-design/01-questions-1-initial-design.md`. Before proposing a design change, read that file — the answer to "why isn't it done this way?" often lives there.

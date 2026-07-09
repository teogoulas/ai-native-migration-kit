# Realistic fixture

A kit-owned, hand-crafted target repo with **deliberate mixed strengths and gaps** across the AI-native rubric. Used by T-30 (end-to-end verification) as the regression baseline for how the kit scores a plausible mid-migration repo.

**Do not edit this fixture to fix findings.** The gaps are intentional. If a future rubric or judge change alters what this fixture surfaces, adjust the encoded expectations below rather than the fixture itself.

## What the fixture represents

A small Next.js 15 App Router project that has *started* migrating toward AI-native but hasn't finished. A team-lead might reasonably ask *"how far along are we?"* and expect the kit to answer with a plan they can execute.

Stack: `node` + `next`, pnpm-flavored (though no lockfile is shipped to keep the fixture small).

## Encoded expectations — deterministic layer (D01–D18), rubric v0.2.0

If any of these change unexpectedly, the fixture drifted (or the rubric changed).

| Check | Severity | Expected verdict | Why |
|---|---|---|---|
| D01 | mandatory | `fail` | AGENTS.md missing canonical sections (Architecture Notes, Things to Avoid). v0.2.0 grep-checks for the five canonical section names. |
| D02 | mandatory | `partial` | CLAUDE.md is a copy of AGENTS.md, not a symlink |
| D03 | mandatory | `fail` | no .claude/settings.json |
| D04 | conditional | `n/a` | no .mcp.json, no MCP declaration in AGENTS.md → team hasn't opted into MCP |
| D05 | mandatory | `fail` | no reproducible-env mechanism (no .devcontainer, Tiltfile, docker-compose, .sdkmanrc, .nvmrc, .python-version, .tool-versions) |
| D06 | mandatory | `fail` | no .pre-commit-config.yaml |
| D07 | mandatory | `pass` | .editorconfig at root |
| D08 | mandatory | `partial` | docs quartet: 2 of 4 present (ARCHITECTURE, DEVELOPMENT); TESTING.md and PRECOMMIT.md missing |
| D09 | mandatory | `fail` | no docs/specs/ |
| D10 | mandatory | `pass` | tests/unit/ exists with .test.ts files |
| D11 | mandatory | `fail` | no integration test structure |
| D12 | mandatory | `fail` | no E2E harness |
| D13 | mandatory | `partial` | CI has build+test but no lint keyword (2/3 gates) |
| D14 | nice-to-have | `fail` | no AI review layer |
| D15 | mandatory | `fail` | no Conventional Commits mechanism |
| D16 | mandatory | `fail` | Node stack detected but no linter config |
| D17 | nice-to-have | `fail` | no .claude/commands/ or .claude/skills/ |
| D18 | mandatory | `n/a` (D06 cascade) | pre-commit config absent → activation check n/a |

Summary: **2 pass · 3 partial · 11 fail · 2 n/a** = **9 mandatory fails · 2 nice-to-have fails**.

Exit code: **2** (blocking) because 9 mandatory checks fail. Under v0.1.0 the exit was also 2 but for a different reason (any single fail → 2); under v0.2.0 the exit code carries the mandatory-vs-nice-to-have distinction explicitly.

The D01/A01 split is a good illustration of the two-layer design: D01 verifies structural presence of the five canonical sections, A01 verifies content quality. A fixture whose AGENTS.md is missing sections fails D01 outright (v0.2.0 tightening) rather than passing D01 and only being flagged by A01.

## Encoded expectations — agentic layer (A01–A08)

If run through the full workflow at standard depth:

| Judge | Expected finding shape |
|---|---|
| A01 (AGENTS.md quality) | score 1/3 — Things-to-Avoid section missing (highest-value gap); Architecture Notes also missing |
| A02 (governance section) | score 0/3 — no governance section at all |
| A04 (test AI-legibility) | score 1/3 — sampled tests violate isolated assertions, descriptive names, readable-diff matchers, and deterministic execution properties |
| A05 (ARCHITECTURE accuracy) | score 0/3 — 2 of ~4 referenced paths do not exist (`src/components/`, `src/components/AppLayout.tsx`) |
| A06 (docs match reality) | score 1/3 — DEVELOPMENT.md references `pnpm dev` which package.json does not expose |

At thorough depth, A03/A07/A08 would also run:

| Judge | Expected finding shape |
|---|---|
| A03 (settings enforcement) | score 0/3 — settings.json missing, no advisory rules to cross-reference |
| A07 (coverage signal) | score 0/3 — no coverage tool detected in CI |
| A08 (stack conventions) | context7 result-dependent; likely 1/3 or 2/3 finding missing pinned versions or a Next.js-specific pattern |

## How this fixture is used

1. **During T-30 development** — the kit was run against this fixture; the plan file was reviewed to confirm it matched the encoded expectations above.
2. **As a regression baseline** — any future judge tuning or rubric change should re-run against this fixture. The observed shape should not change unless the rubric/judge change was intentional.
3. **For screenshots/demos in the README** — one clean, reproducible fixture makes it possible to include an example plan-file snippet in the top-level README without shipping an actual customer repo.

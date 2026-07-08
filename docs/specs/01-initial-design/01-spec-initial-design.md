# Spec 01 — Initial Design of `ai-native-migration-kit`

**Status:** draft
**Author:** T. Goulas (with AI assistance)
**Date:** 2026-07-08
**External standards referenced:** the [AGENTS.md open standard](https://agents.md/) (Agentic AI Foundation), [Anthropic Claude Code docs](https://docs.anthropic.com/en/docs/claude-code).

---

## 1. Problem

Any given repository can be made "AI-native" — restructured so an agent loads the right context on session start, follows repo conventions without being told, and can verify its own work through deterministic guardrails. Four through-lines characterize this pattern: **explicit over implicit, verification at every level, structured artifacts, stable context anchors**.

Today, applying this pattern to a new repository is a manual, error-prone process. An engineer has to:

- Remember the full checklist (AGENTS.md, symlinked CLAUDE.md, `.claude/settings.json` with denyList, `.mcp.json`, `.devcontainer/`, `.pre-commit-config.yaml`, `docs/ARCHITECTURE.md` / `DEVELOPMENT.md` / `TESTING.md`, `docs/specs/`, three test layers, CI gates, conventional commits, an AI review layer, onboarding scripts, and more).
- Judge quality of the artifacts they find (does `AGENTS.md` actually have a "Things to Avoid" section? Are tests AI-legible? Is `ARCHITECTURE.md` in sync with the current code?).
- Sequence the fixes so PRs stay reviewable.

This is exactly the shape of work that benefits from a **deterministic-checks-plus-agentic-audit** pipeline, kept **human-in-the-loop** at every decision boundary. A full autonomous migration is neither achievable nor desirable: rewriting `AGENTS.md`, seeding a governance section, or restructuring `docs/` requires human judgment about the project's actual conventions and risk profile.

## 2. Goals

1. **Produce a repeatable process** to assess and migrate any repository toward AI-native status, applicable to arbitrary languages and stacks.
2. **Combine deterministic and agentic checks** — bash scripts for structural facts, LLM subagents for semantic judgments — so token spend is spent only where it adds value.
3. **Keep a human in the loop** at every write. The kit never converts findings into commits autonomously.
4. **Ship as a Claude Code skill wrapping a Workflow**, installed by symlink from a dedicated repo, so the deliverable is versioned, reviewable, and improvable independently of any target repo.
5. **Traceability** — every recommendation in the output plan cites the rubric section that motivates it (e.g., "§4.1 D01" or "§4.2 A02"), so the reader can verify the reasoning by reading a single self-contained document.

## 3. Non-goals

1. **Not** a code-generator. It never writes production source files. Templates it drops are structural files (context, config, docs skeletons, onboarding scripts) that the target repo owner then edits.
2. **Not** a one-shot autonomous migration. There is no `--yes-to-all` mode.
3. **Not** stack-specific. Stack-specific overlays are additive references, not the core; the general checklist runs on every repo.
4. **Not** a replacement for `/init`, `/review`, `/security-review`, or existing Claude Code slash commands. Where those apply, the kit's plan file cites them and asks the human to run them.
5. **Not** a runtime enforcement mechanism. Once the kit finishes, ongoing enforcement is the target repo's committed `.claude/settings.json`, pre-commit hooks, and CI — none of which the kit continues to manage after handoff.

## 4. Definition: what "AI-native" means for this kit

The kit uses the rubric below as its scoring rubric. The rubric is self-contained; it does not depend on any external repository or curriculum. Where it names files or patterns, those are conventions from public standards (e.g., the [AGENTS.md](https://agents.md/) open standard) or widely-adopted engineering practices (pre-commit, Conventional Commits, SDD).

### 4.1 Deterministic criteria (checkable without an LLM)

| # | Criterion | Example indicator | Through-line |
|---|---|---|---|
| D01 | `AGENTS.md` exists at repo root, non-empty | file present, size > 0, ≥ 3 top-level headings | Explicit over implicit |
| D02 | `CLAUDE.md` is a symlink to `AGENTS.md` | `readlink CLAUDE.md` returns `AGENTS.md` | Explicit over implicit |
| D03 | `.claude/settings.json` present with `denyList` and audit hooks | valid JSON containing `denyList` array and `hooks` object | Explicit over implicit |
| D04 | `.mcp.json` present (if MCP servers used by team) | file present OR AGENTS.md declares no MCP usage | Stable context anchors |
| D05 | `.devcontainer/devcontainer.json` + `Dockerfile` | both files present under `.devcontainer/` | Stable context anchors |
| D06 | `.pre-commit-config.yaml` present | file present, parseable YAML with `repos:` key | Verification at every level |
| D07 | `.editorconfig` present | file present at repo root | Explicit over implicit |
| D08 | `docs/ARCHITECTURE.md`, `docs/DEVELOPMENT.md`, `docs/TESTING.md` all present | all three files present under `docs/` | Structured artifacts |
| D09 | `docs/specs/` directory exists (SDD artifacts home) | `docs/specs/` is a directory | Structured artifacts |
| D10 | Unit test folder(s) exist | any of: `src/test/`, `test/`, `tests/`, `__tests__/`, matching stack conventions | Verification at every level |
| D11 | Integration test folder(s) exist | folder matching `**/integration/**` OR test tags indicating integration | Verification at every level |
| D12 | E2E test folder(s) exist (Playwright / Cypress / equivalent) | `e2e-tests/`, `playwright.config.*`, `cypress.config.*`, or equivalent | Verification at every level |
| D13 | `.github/workflows/` (or equivalent CI) with build + test + lint gates | `.github/workflows/*.yml` OR `.gitlab-ci.yml` OR `.circleci/config.yml` present, with jobs matching build/test/lint keywords | Verification at every level |
| D14 | `.coderabbit.yaml` or equivalent AI review layer | any of: `.coderabbit.yaml`, other AI-review bot config file, OR CI job invoking an AI reviewer | Verification at every level |
| D15 | Conventional Commits enabled (commitlint hook, `.gitmessage`, or scoped commit skill) | any of: `.gitmessage` template, `commitlint.config.*`, pre-commit hook enforcing conventional-commits, `/commit` slash command | Explicit over implicit |
| D16 | Stack-specific linter/style config present | file matching detected stack: e.g., `checkstyle.xml` for Java, `eslint.config.*` for JS/TS, `.ruff.toml` for Python, `.rubocop.yml` for Ruby | Verification at every level |
| D17 | `.claude/commands/` and/or `.claude/skills/` present with at least one entry | either directory exists and contains ≥ 1 file | Explicit over implicit |
| D18 | Onboarding automation script exists (e.g., `scripts/setup-precommit.sh`) that makes committed pre-commit config actually active on new-dev clone | executable script under `scripts/` OR Makefile target that runs `pre-commit install` (or stack-equivalent) | Verification at every level |

Each criterion resolves to one of `{pass, fail, partial, n/a}`. `partial` covers cases like "AGENTS.md exists but CLAUDE.md is a separate file, not a symlink" or "pre-commit config present but no onboarding script activates it."

### 4.2 Agentic criteria (require semantic reading)

| # | Judge | What it evaluates |
|---|---|---|
| A01 | AGENTS.md quality judge | Content covers the five canonical sections: Project Overview, Coding Standards, Key Commands, Architecture Notes, and **Things to Avoid** (the most-skipped, highest-value section). Size discipline: ~120–200 lines. |
| A02 | AGENTS.md governance judge | Presence of a governance sub-section covering *do-not-modify*, *always-run-before-commit*, *escalate-to-a-human-when*. |
| A03 | `.claude/settings.json` enforcement judge | Verifies that rules stated in AGENTS.md's governance section are actually enforced by settings.json — cross-references the "advisory in AGENTS.md, enforced in settings.json" pattern. |
| A04 | Test AI-legibility judge | Samples up to N tests per test layer and scores against: isolated assertions, descriptive names (`method_expected_when` pattern), matchers that emit readable diffs (Hamcrest `is`, AssertJ `isEqualTo`, `expect().toEqual()`), deterministic execution (injected clock, seeded randoms, no live network). |
| A05 | ARCHITECTURE.md accuracy judge | Reads ARCHITECTURE.md, sketches the actual directory layout, flags drift (e.g., "doc says `src/main/java/com/example/domain/` but no such folder exists"). |
| A06 | Docs coverage judge | For DEVELOPMENT/TESTING/PRECOMMIT, verifies the doc actually describes commands and workflows that the deterministic checks confirmed exist (no phantom docs, no undocumented workflows). |
| A07 | Coverage / mutation-testing signal judge | Detects whether coverage is used as a spec-completeness signal: is there a coverage tool wired to CI, and is there a mutation-testing tool (PIT, Stryker, mutmut, etc.) as a stronger gate? |
| A08 | Stack conventions judge | Detects stack + framework versions from lockfiles at audit time, then calls `mcp__context7__query-docs` live for the framework's current AI-native / testing / structural guidance and evaluates the target against it. **No hand-authored per-stack overlay files ship with the kit** — the live query is the source of truth for stack-specific rules, so guidance never rots. If `context7` is unavailable in the calling session, A08 falls back to `references/stack-generic.md` (a thin cross-stack floor) and notes the degradation in the plan. |

Each judge returns a JSON object matching a schema (`{criterion, verdict, score: 0-3, evidence, gap, recommendation, throughline}`). Schema validation happens at the tool boundary — malformed output triggers automatic retry.

## 5. Solution shape

A dedicated repository `ai-native-migration-kit/` at `~/dev/ai-native-migration-kit/`, structured as follows:

```
ai-native-migration-kit/
├── README.md
├── AGENTS.md                                    # eats own dogfood
├── CLAUDE.md -> AGENTS.md
├── LICENSE
├── install.sh                                   # symlinks skill into ~/.claude/skills/
├── skill/
│   ├── SKILL.md                                 # entry point invoked by /ai-native-migration
│   ├── scripts/
│   │   ├── ai-native-verify                     # standalone deterministic audit (see §10) — invocable directly, no LLM
│   │   ├── detect-stack.sh                      # infers {stack, framework, versions} from lockfiles
│   │   ├── bootstrap.sh                         # applies ONE named template, interactive per file
│   │   └── lib/                                 # shared bash helpers
│   ├── workflows/
│   │   └── ai-native-audit.js                   # multi-agent audit workflow; consumes ai-native-verify output
│   ├── references/
│   │   ├── ai-native-checklist.md               # canonical rubric (§4 of this spec, expanded)
│   │   ├── judging-rubrics.md                   # per-judge prompt guidance + score anchors
│   │   ├── patterns-explained.md                # judge / adversarial verify / critic explained
│   │   └── stack-generic.md                     # thin cross-stack floor used by A08 when context7 unavailable
│   └── templates/                               # bootstrap sources; kit never edits the target directly
│       ├── AGENTS.md.tmpl
│       ├── .claude/settings.json.tmpl
│       ├── .mcp.json.tmpl
│       ├── .devcontainer/
│       ├── .pre-commit-config.yaml.tmpl
│       ├── .editorconfig.tmpl
│       ├── .gitmessage.tmpl
│       ├── .coderabbit.yaml.tmpl
│       ├── docs/
│       │   ├── ARCHITECTURE.md.tmpl
│       │   ├── DEVELOPMENT.md.tmpl
│       │   ├── TESTING.md.tmpl
│       │   └── PRECOMMIT.md.tmpl
│       └── scripts/
│           ├── setup-precommit.sh.tmpl
│           └── onboarding-check.sh.tmpl
└── docs/
    ├── ARCHITECTURE.md
    ├── DEVELOPMENT.md
    └── specs/
        └── 01-initial-design/
            ├── 01-spec-initial-design.md        # (this file)
            ├── 01-tasks-initial-design.md       # (produced next)
            └── 01-questions-1-initial-design.md # (if any open questions)
```

## 6. Invocation flow

The user (or an agent working on the user's behalf) invokes:

```
/ai-native-migration <target-repo-path> [--depth=light|standard|thorough|custom] [--apply]
```

Sequence:

1. **Preflight** — `SKILL.md` verifies the target path is a git repo, is clean (or user confirms working with uncommitted changes), and that Claude Code has read access.

2. **Stack detection** — `detect-stack.sh` inspects the target for stack indicators (`pom.xml`, `build.gradle`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json`). Emits `{stack, framework, versions, package_manager, test_framework}`. Versions matter because A08 uses them when querying `context7`.

3. **Deterministic audit** — `ai-native-verify` (see §10) runs the 18 checks in §4.1 and emits a JSON scorecard on stdout: `{criterion, verdict, evidence, remediation_hint}`. Exit code is a summary signal for CI use.

4. **Agentic audit workflow** — `workflows/ai-native-audit.js` runs, spawning judges per §4.2. Depth flag controls:
   - **light**: 3 judges (A01, A04, A05), no verify, no critic.
   - **standard** (default): 5 judges (A01, A02, A04, A05, A06), single-vote verify per finding, no critic.
   - **thorough**: all 8 judges, 3-vote adversarial verify per finding (majority survives), completeness critic loop (up to 2 rounds).
   - **custom**: `--judges=A01,A04 --verify=3 --critic=on` — surgical control.

5. **Synthesis** — a final synthesis agent merges the deterministic scorecard and the verified agent findings into a **migration plan** written to `<target-repo>/docs/plans/ai-native-migration-<yyyy-mm-dd>.md`. The plan is organized by through-line, cites the rubric section that motivates each recommendation (e.g., "rubric §4.1 D01"), and breaks work into PR-sized tasks.

6. **Human review boundary** — the skill stops here in the default (no `--apply`) case. It surfaces a summary of the plan and its location. Nothing has been written to the target repo except the plan file (in `docs/plans/`, unstaged).

7. **Optional bootstrap** — if `--apply` is supplied, `bootstrap.sh` walks the templates whose corresponding deterministic check failed (or that a judge recommended). **Per template**, it:
   1. Shows a diff between template and target-repo current state (which may be "file does not exist").
   2. Asks the user `apply / skip / edit-then-apply`.
   3. If `edit-then-apply`, opens the template in a temp buffer for the user to modify before it lands.
   4. Writes the file, unstaged, into the target repo.
   Security-sensitive templates (`.claude/settings.json`, anything under `.github/workflows/`) are **always** interactive regardless of any flag. Templates are never applied in a batch or without per-file confirmation.

## 7. Agent-pattern definitions used by the workflow

For humans in the loop reading the plan, `references/patterns-explained.md` explains the three multi-agent patterns the workflow uses. Summary here for spec completeness:

- **Judge** — one `agent()` call whose prompt targets one dimension (e.g., "AGENTS.md quality") and returns a schema-validated JSON verdict. Judges are readers, not writers.

- **Adversarial verify (N-vote)** — for each judge finding, spawn N independent skeptics whose prompt is to *refute* the claim. Plain code counts votes: majority-not-refuted → survives. Inverts the plausibility bias judges naturally carry. `standard` depth uses 1 verifier per finding; `thorough` uses 3.

- **Completeness critic** — a final agent that reads the aggregated findings and asks "what's missing?" (unjudged criterion, unverified claim, unread source). Its gap list drives the next audit round. Enabled only in `thorough` depth, capped at 2 rounds.

All three are prompting patterns implemented via `agent()` calls with JSON schemas — no special framework beyond what the Workflow tool exposes.

## 8. Output artifact — migration plan structure

The plan file at `<target-repo>/docs/plans/ai-native-migration-<date>.md` follows this shape:

```markdown
# AI-Native Migration Plan — <target-repo-name>

**Generated:** <ISO date>
**Depth:** standard
**Stack detected:** <stack>
**Overall score:** <n>/<total> deterministic, <n>/<total> agentic

## Executive summary
<3-5 sentence summary: what's strong, what's missing, biggest risks>

## Findings by through-line

### Explicit over implicit
- **Gap** (score 1/3): <criterion — e.g. "AGENTS.md missing 'Things to Avoid' section">
  - Evidence: <quote or file:line>
  - Recommendation: <specific action>
  - Source: rubric §4.2 A01 (AGENTS.md quality)
  - Task: T-01 (see below)

### Verification at every level
… (same shape) …

### Structured artifacts
…

### Stable context anchors
…

## Task list (PR-sized)

- [ ] **T-01** — Add "Things to Avoid" section to AGENTS.md (est: 30m)
- [ ] **T-02** — Wire pre-commit onboarding script (est: 15m)
- [ ] **T-03** — Move `docs/specs/` into place and seed with SDD template (est: 20m)
- …

## Suggested sequencing
<explains which tasks unlock which, so a team can pick up the plan and execute in order>

## Human-decision points
<lists tasks that need a human call before an agent can proceed: e.g. "T-05 requires product to decide which endpoints are safe for autonomous modification">
```

## 9. Human-in-the-loop guarantees

Enshrined in the SKILL.md and in the workflow's synthesis prompt:

1. **No writes to the target repo except the plan file** in the default flow. The plan is a proposal, not a change.
2. **`--apply` is per-template interactive.** No batch modes, no `--yes`.
3. **Security-sensitive templates are always interactive**, regardless of flags: `.claude/settings.json`, `.github/workflows/**`, anything under `.mcp.json`.
4. **Every recommendation traces to the rubric** — cites a section of §4 (e.g., "§4.1 D06" or "§4.2 A04"). Absent traceability, it doesn't ship.
5. **The plan file names its own limits** — a "confidence" section lists what the audit could NOT judge (e.g., "no read access to CI logs; test flakiness assessed statically only").
6. **The completeness critic (in `thorough` depth) may extend runtime and cost** — the SKILL.md explicitly asks the user to confirm `thorough` runs before spawning.

## 10. `ai-native-verify` — standalone deterministic script

The 18 deterministic checks (§4.1) are shipped as a standalone executable at `skill/scripts/ai-native-verify`. The skill's agentic workflow invokes it, but so can anything else — target repos, after migration, can wire it into their own guardrails.

**Contract:**

```
ai-native-verify [--format=text|json] [--check=D01,D02,...] <target-repo-path>
```

- `--format=text` (default): human-readable pass/fail per criterion, aligned columns.
- `--format=json`: machine-readable scorecard on stdout, one JSON object.
- `--check=<list>`: run only the named subset of checks; omitted = run all 18.

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | All checks pass or n/a |
| 1 | At least one criterion is `partial` — structural presence, quality gap |
| 2 | At least one criterion is `fail` |
| 3 | Preflight failure — not a git repo, no read access, or malformed target path |

**Post-migration use cases the script enables (the kit does NOT wire these up; the target repo decides):**

- **GitHub Actions step** — `- run: ai-native-verify .` in a workflow. Fails the PR when structural regressions occur (e.g., someone deletes `AGENTS.md`).
- **Pre-push git hook** — installed via `.pre-commit-config.yaml`. Blocks pushing branches that regress structural compliance.
- **Manual sanity check** — an engineer running `ai-native-verify .` locally after refactoring the docs directory.

The script is pure bash — no Node, no Python dependency, no Claude Code required at runtime. This is deliberate: the deterministic guardrails a target repo relies on must be independent of the tools that authored them.

## 11. Portability and stack agnosticism

- The general rubric (§4.1 + A01–A07) runs on every repo regardless of stack.
- Stack detection is best-effort. If ambiguous, A08 skips stack-specific evaluation and notes the ambiguity in the plan.
- **No hand-authored stack overlays ship with the kit.** A08 detects stack + framework versions at audit time and calls `mcp__context7__query-docs` live so guidance reflects current framework practice, not a snapshot that ages. This means the kit does not need to be rebuilt when Spring Boot 4 or Next.js 16 lands.
- If `context7` is unavailable in the calling session, A08 falls back to `references/stack-generic.md` — a thin cross-stack floor (test names describe behavior, config in files not code, etc.) — and the plan file marks A08 as degraded so the reader knows the stack layer was not fully evaluated.

## 12. Self-governance — the kit protects its own source of truth

The kit's own `templates/` and `references/` directories are the source of truth for what the kit does. An agent working inside the kit's repo (helping refine a template, tune a judge prompt, etc.) must not be able to silently rewrite them.

The kit ships with a committed `.claude/settings.json` that includes a **deny-list** on Edit/Write tools for:

- `skill/templates/**`
- `skill/references/**`

To change any file in those trees, an engineer must first modify `settings.json` in the same PR to lift the block. This makes the intent explicit and reviewable — the "policy as code" pattern (rubric §4.1 D03 and §4.2 A03), applied recursively to the kit itself.

The kit's own AGENTS.md includes matching guidance in its governance section, so both the advisory and enforced layers agree.

## 13. Open questions

All questions raised during the first spec review have been resolved and folded into the spec above. Full trail in `01-questions-1-initial-design.md`.

No open questions block task breakdown. New questions raised during implementation will land in `01-questions-N-initial-design.md` files.

## 14. Acceptance criteria for the kit itself (dogfood check)

Before the kit is considered done, running it against its own repo (`ai-native-migration-kit/`) must produce a plan file with:

- All 18 deterministic criteria passing (or `n/a` with justification).
- Judges A01–A07 scoring ≥ 2/3 for the kit's own AGENTS.md, docs, and (if any) tests.
- Zero critical gaps in the through-line "explicit over implicit."
- The completeness critic returning an empty gap list on the first pass in `thorough` mode.

The kit ships when it can honestly audit itself and come back clean.

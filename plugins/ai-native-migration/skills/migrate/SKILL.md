---
name: migrate
description: Audit any repository against the ai-native-migration-kit rubric (18 deterministic checks + up to 8 semantic judges) and produce a human-reviewable migration plan. Use when the user asks to audit or migrate a repository toward AI-native status, invokes /ai-native-migration:migrate, or asks how an existing repo scores against AI-native structural criteria. Does NOT convert findings into commits — human-in-the-loop by design.
---

# /ai-native-migration:migrate

You are running the ai-native-migration plugin's `migrate` skill against a target repository. This file tells you the seven steps to execute, in order, and the invariants you must not violate.

Inside this plugin, the environment variable `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's root directory (the directory containing `.claude-plugin/plugin.json`). Every script and reference this file mentions lives under that root — use `${CLAUDE_PLUGIN_ROOT}/scripts/…`, `${CLAUDE_PLUGIN_ROOT}/workflows/…`, and `${CLAUDE_PLUGIN_ROOT}/references/…` when calling out from Bash.

## Invariants (non-negotiable)

Read these before doing anything. They are the guarantees the human invoking this skill is relying on.

1. **The default flow writes exactly one file into the target repo**: the plan file, at `<target>/docs/plans/ai-native-migration-<yyyy-mm-dd>.md`. **No other writes** are permitted in the default (no `--apply`) flow.

2. **Never modify source files in the target.** Not to fix findings, not to demonstrate a template, not for any reason. If the human wants changes applied, they will re-invoke with `--apply` and go through `bootstrap.sh`'s interactive per-template flow (see step 7).

3. **Every recommendation in the plan file must cite a rubric section** — either `§Part 1 D01`–`D18` (deterministic) or `§Part 2 A01`–`A08` (agentic). Uncited claims do not ship. If a judge produced a finding without evidence, the synthesizer drops it silently, not you.

4. **No citations to external curricula, training programs, or reference repositories.** Rubric sections are the only allowed citation source. See the design record's Q-07 for why.

5. **Security-sensitive templates are always interactive**, regardless of any flag: `.claude/settings.json`, anything under `.github/workflows/`, and `.mcp.json`. This constraint lives in `bootstrap.sh`; do not try to shortcut it.

6. **The plan file's `## Confidence` section names what could not be judged** — an unavailable `context7` MCP, no read access to CI logs, tests that couldn't be sampled. Silence is not confidence; be explicit about the audit's blind spots.

## The seven steps

### 1. Preflight

Confirm the invocation is well-formed.

- The user must have provided a **target repo path**. If they invoked `/ai-native-migration` bare, ask which repo they want audited — do not proceed against the current directory unless the user explicitly confirms it.
- Verify the target is a git repository (has `.git`). If not, report and stop.
- If the target has uncommitted changes, note it in the plan file's Confidence section but do not stop. Auditing dirty trees is legitimate; the human made the choice.

### 2. Detect stack

Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh <target>`. Capture the JSON output. Fields:

```
{stack, framework, versions, package_manager, test_framework}
```

`stack` can be `unknown` — that is a valid answer, not an error. Judge A08 handles the unknown case explicitly (§Part 2 A08 in the rubric).

### 3. Deterministic audit

Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/ai-native-verify --format=json <target>`. Capture:

- The full JSON scorecard (18 check results).
- The exit code (0 = all pass/n/a, 1 = ≥1 partial, 2 = ≥1 fail, 3 = preflight).

**Do not** re-implement any of the D checks yourself. The bash script is the sole authority for deterministic verdicts.

If exit code is 3, something is wrong with the invocation (probably a bad path) — stop and report.

### 4. Agentic audit (workflow)

Invoke the workflow at `${CLAUDE_PLUGIN_ROOT}/workflows/ai-native-audit.js` with the target path, the depth flag (default `standard`), and the deterministic scorecard as input. The workflow will:

- Spawn judges A01–A08 (or a subset, per depth).
- Run adversarial verify per finding.
- Optionally run a completeness critic (thorough mode only).
- Emit an aggregated findings JSON.

**Depth levels** (from spec §6 step 4):

| Depth | Judges | Verifiers per finding | Completeness critic |
|---|---|---|---|
| `light` | 3 (A01, A04, A05) | 0 | off |
| `standard` (default) | 5 (A01, A02, A04, A05, A06) | 1 | off |
| `thorough` | all 8 | 3 (majority vote) | on, up to 2 rounds |
| `custom` | per `--judges=` | per `--verify=` | per `--critic=` |

If the user requested `thorough`, **confirm before spawning** — it consumes significantly more tokens and time than the default.

If the workflow invocation fails for any reason (transient MCP unavailability, tool error), report the failure and skip to step 6 with only the deterministic results — a plan file with just the scorecard is still useful to the human.

### 5. Synthesize the plan

Merge the deterministic scorecard from step 3 with the verified agentic findings from step 4 into the plan file. Structure (from spec §8):

```markdown
# AI-Native Migration Plan — <target-repo-name>

**Generated:** <ISO date>
**Depth:** <light|standard|thorough|custom>
**Stack detected:** <stack> (<framework> <version>)
**Overall score:** <n>/<total> deterministic, <n>/<total> agentic

## Executive summary
<3–5 sentences: what's strong, what's missing, biggest risks>

## Findings by through-line

### Explicit over implicit
- **Gap** (score X/3): <criterion — e.g., "AGENTS.md missing 'Things to Avoid' section">
  - Evidence: <quoted file:line or exact quote>
  - Recommendation: <specific action>
  - Source: `rubric §Part 2 A01`
  - Task: T-01

### Verification at every level
… (same shape)

### Structured artifacts
…

### Stable context anchors
…

## Task list (PR-sized)

- [ ] **T-01** — <one-line title> (est: <15m|30m|1h|2h+>)
- [ ] **T-02** — …
- …

## Suggested sequencing
<Which tasks unlock which. Dependencies from the rubric — e.g., D18 depends
on D06, so if both fail, land D06 first.>

## Human-decision points
<Tasks that require a human call before an agent can proceed — e.g., "T-05
requires product to decide which endpoints are safe for autonomous
modification".>

## Confidence
<What could NOT be evaluated:
- context7 unavailable → A08 scored against stack-generic floor only
- Uncommitted changes in target → some judges may have inconsistent input
- Any layer skipped due to --depth=light>
```

**Write the plan file to `<target>/docs/plans/ai-native-migration-<yyyy-mm-dd>.md`.** If `docs/plans/` does not exist in the target, create it. If a plan file with today's date already exists, append a `-N` suffix.

### 6. Human review boundary — STOP

Report to the user:

- Where the plan file was written.
- The overall score (deterministic and agentic).
- A one-line summary of the top three findings.
- Whether any part of the audit was degraded (see step 5's Confidence section).

**Do not proceed to step 7 unless the user explicitly re-invokes with `--apply`.** The default flow ends here. The human reads the plan and decides.

### 7. Optional bootstrap (only when `--apply` was passed)

If and only if the user's invocation included `--apply`, enter the collaborative remediation flow. **You (the reading agent) drive the conversation with the human; `bootstrap.sh` handles the mechanical file-writing.** The goal is not just to apply templates — it is to leave the target with each mandatory check flipped from `fail` to `pass`.

Order of operations:

1. **Walk mandatory fails first, in criterion-severity order.** From the deterministic scorecard in step 3, take all findings where `severity=mandatory` and `verdict != pass`. These are the blockers. Address them before touching nice-to-have or conditional findings.

2. **Per-artifact strategy.** Every mandatory finding maps to one of two remediation styles:

   - **Simple template application** — the artifact is largely boilerplate; the template renders into a passing state without needing project-specific input. This covers `.editorconfig`, `.gitmessage`, `.coderabbit.yaml`, `.pre-commit-config.yaml`, `.devcontainer/*`, `docs/PRECOMMIT.md` (mostly-generic), and the two onboarding scripts. Use `bootstrap.sh --template=<name> --check-after=<criterion>` for each.

   - **Conversational walkthrough** — the artifact needs real project-specific content. This applies to **AGENTS.md** (D01, plus A01/A02 quality) and **`.claude/settings.json`** (D03 baseline is generic but the governance section needs project-specific do-not-modify paths and always-run commands). Follow the per-artifact scripts in `${CLAUDE_PLUGIN_ROOT}/references/walkthroughs.md` — ask the human the listed questions, draft content from their answers, show the draft, iterate on their feedback, and only then write via the Write tool. Do not shortcut to the raw template.

   `docs/ARCHITECTURE.md`, `docs/DEVELOPMENT.md`, `docs/TESTING.md` sit in the middle — the templates are structured but need project-specific detail. Treat them as conversational walkthroughs only when D08 fails outright (0-1 of 4 docs present); when D08 is partial (2-3 of 4), the human already has some docs and you should ask which they want to draft next rather than assume.

3. **Verify after each artifact.** As soon as you (or bootstrap.sh) write a file, run `${CLAUDE_PLUGIN_ROOT}/scripts/ai-native-verify --check=<criterion> --format=json <target>` and inspect the result. If the criterion still doesn't pass, tell the human what's still missing and iterate before moving to the next criterion. Do not batch multiple writes and check at the end — one artifact, one write, one check.

4. **After all mandatory fails are addressed, offer nice-to-have and conditional findings.** For nice-to-have (`D14`, `D17`), ask the human explicitly whether to apply each — the migration is complete without them. For conditional (`D04`, `A08`), only offer if the audit surfaced a real fail (not `n/a`).

5. **Never write without human confirmation.** Bootstrap's `apply / skip / edit-then-apply / quit` prompt still gates the mechanical templates. For your conversationally-generated content, show the draft (Read it back or paste into the message) and ask "apply?" before invoking Write. The plan file is still the source of truth for what needs fixing; this step is how the human authorizes each fix, one at a time.

6. **Security-sensitive templates always require confirmation, regardless of severity or apply-flag.** `.claude/settings.json`, `.mcp.json`, and anything under `.github/workflows/**` — the human sees each rendered file and explicitly says "apply" before it lands. This constraint lives in `bootstrap.sh` too; don't try to shortcut it in the conversational flow either.

7. **Report at the end.** For each mandatory criterion addressed: verdict-before → verdict-after, and (if you asked the human to defer any) which findings remain open. Nice-to-have applied/skipped counts. Then hand back to the human — the audit re-scorecard is what proves the work landed.

If `bootstrap.sh` fails to launch (interactive terminal not available, missing dependency), fall back to reporting: *"The bootstrap step could not run. The plan file at <path> documents the recommended changes; apply them manually."*

## Argument reference

```
/ai-native-migration:migrate <target-repo-path> [options]

Options:
  --depth=<light|standard|thorough|custom>   Default: standard
  --judges=<A01,A04,...>                     Custom depth only
  --verify=<N>                               Custom depth only
  --critic=<on|off>                          Custom depth only
  --apply                                    Enter step 7 (interactive bootstrap)
```

## When you finish

Report concisely. No decorative summaries. The plan file speaks for itself; your job is to point at it and name the biggest gaps.

## Related references

Under `${CLAUDE_PLUGIN_ROOT}/references/`:

- Rubric (what is measured): `ai-native-checklist.md`
- Judging rubrics (how each judge scores): `judging-rubrics.md`
- Pattern explanations (judge / adversarial verify / critic): `patterns-explained.md`
- Stack-generic floor (A08 fallback): `stack-generic.md`
- Per-artifact walkthrough scripts (step 7 conversational flow): `walkthroughs.md`

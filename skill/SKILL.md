---
name: ai-native-migration
description: Audit any repository against the ai-native-migration-kit rubric (18 deterministic checks + up to 8 semantic judges) and produce a human-reviewable migration plan. Use when the user asks to audit or migrate a repository toward AI-native status, invokes /ai-native-migration, or asks how an existing repo scores against AI-native structural criteria. Does NOT convert findings into commits — human-in-the-loop by design.
---

# /ai-native-migration

You are running the ai-native-migration-kit skill against a target repository. This file tells you the seven steps to execute, in order, and the invariants you must not violate.

## Invariants (non-negotiable)

Read these before doing anything. They are the guarantees the human invoking this skill is relying on.

1. **The default flow writes exactly one file into the target repo**: the plan file, at `<target>/docs/plans/ai-native-migration-<yyyy-mm-dd>.md`. **No other writes** are permitted in the default (no `--apply`) flow.

2. **Never modify source files in the target.** Not to fix findings, not to demonstrate a template, not for any reason. If the human wants changes applied, they will re-invoke with `--apply` and go through `bootstrap.sh`'s interactive per-template flow (T-27; may not be present yet — see step 7).

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

Invoke `<skill-dir>/scripts/detect-stack.sh <target>`. Capture the JSON output. Fields:

```
{stack, framework, versions, package_manager, test_framework}
```

`stack` can be `unknown` — that is a valid answer, not an error. Judge A08 handles the unknown case explicitly (§Part 2 A08 in the rubric).

### 3. Deterministic audit

Invoke `<skill-dir>/scripts/ai-native-verify --format=json <target>`. Capture:

- The full JSON scorecard (18 check results).
- The exit code (0 = all pass/n/a, 1 = ≥1 partial, 2 = ≥1 fail, 3 = preflight).

**Do not** re-implement any of the D checks yourself. The bash script is the sole authority for deterministic verdicts.

If exit code is 3, something is wrong with the invocation (probably a bad path) — stop and report.

### 4. Agentic audit (workflow)

Invoke the workflow at `<skill-dir>/workflows/ai-native-audit.js` with the target path, the depth flag (default `standard`), and the deterministic scorecard as input. The workflow will:

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

If the workflow file (`ai-native-audit.js`) does not exist yet (kit is mid-build), report gracefully: *"The agentic audit workflow is not yet available. Deterministic scorecard follows."* Then skip to step 6 with only the deterministic results.

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

If and only if the user's invocation included `--apply`, hand off to `<skill-dir>/scripts/bootstrap.sh` (T-27; may not be present yet). Its contract:

- Walks templates in `<skill-dir>/templates/**` whose corresponding rubric check failed in step 3 (or that a judge recommended in step 5).
- For each template:
  1. Renders placeholders (`{{project_name}}`, `{{stack}}`).
  2. Shows a diff against the target's current state (which may be "file does not exist").
  3. Prompts `apply / skip / edit-then-apply`.
  4. On `edit-then-apply`, opens `$EDITOR` on a temp copy, then writes.
  5. Writes files unstaged into the target repo.
- **Always-interactive templates** (`.claude/settings.json`, `.github/workflows/**`, `.mcp.json`) — no flag can override the per-file prompt.

If `bootstrap.sh` is not yet present in the skill, report: *"The bootstrap step is not yet available. The plan file at <path> documents the recommended changes; apply them manually."*

## Argument reference

```
/ai-native-migration <target-repo-path> [options]

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

- Rubric (what is measured): `references/ai-native-checklist.md`
- Judging rubrics (how each judge scores): `references/judging-rubrics.md`
- Pattern explanations (judge / adversarial verify / critic): `references/patterns-explained.md`
- Stack-generic floor (A08 fallback): `references/stack-generic.md`

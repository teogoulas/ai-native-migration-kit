# Spec 02 — Monorepo Support

**Status:** draft
**Author:** T. Goulas (with AI assistance)
**Date:** 2026-07-09
**Target version:** 0.2.0
**Depends on:** [Spec 01 — Initial Design](../01-initial-design/01-spec-initial-design.md)

---

## 1. Problem

A real-world audit run against a monorepo produced a **silent false-negative cascade**:

- The deterministic layer (`ai-native-verify`) checks D10/D11/D12 by looking at root-level test directories (`$TARGET/{tests,test,__tests__,src/__tests__}`) and a `find -maxdepth 4` sweep for co-located `*.test.*` files.
- Neither check knows about workspace-scoped test locations (`packages/*/tests/`, `apps/*/src/__tests__/`, `services/*/src/test/java/`).
- Deep test files (`packages/web/src/components/Button.test.ts` — 5 path segments) fall outside the depth cap and are silently dropped.
- D10/D11/D12 emit `verdict=fail`.
- Judge A04 (test legibility) is instructed to defer to D10-D12 and abstain when they all fail.
- Judges A06 and A07 have the same defer-to-deterministic pattern for tooling and CI signals.
- The plan file recommends creating scaffolding that **already exists** in the target.

The kit's multi-agent verify + critic layers cannot catch this class of error because both are optimistic-finding *filters* — verifiers refute judge claims; the critic surfaces missing coverage. Neither challenges an *abstention* or an *input verdict*. The design assumed deterministic outputs were ground truth. In monorepos, that assumption is false.

Part 1 of the fix (already landed in this branch, commits `c924875`, `a5832a0`) taught A04/A06/A07 to cross-check their inputs and surface disagreements. That's a mitigation — the deterministic layer still lies, judges now catch some of its lies. Part 2 (this spec) makes the deterministic layer itself monorepo-aware, so the ground truth is actually true.

## 2. Goals

1. **Ground truth aligned with reality.** `ai-native-verify` correctly reports the state of monorepos: tests, tooling, CI, and stack signals are found where they actually live.
2. **Extensible workspace detection.** New monorepo tools (workspace managers, build systems) can be added without touching check logic — same pattern as `detect-stack.sh`.
3. **Per-criterion scope, made explicit.** Every D and A criterion has a documented scope (`root-only`, `per-workspace`, `root-primary`) in the canonical rubric. No implicit assumptions.
4. **Backward-compatible for flat repos.** A non-monorepo target sees no behavior change. The workspace detector emits `type: "none"`, and all checks fall back to their pre-0.2.0 root-only behavior.
5. **Machine-readable per-workspace verdicts.** The JSON scorecard exposes per-workspace results so downstream consumers (CI, dashboards) can act on workspace-level gaps.

## 3. Non-goals

1. **Not** a per-workspace plan file. The audit still produces ONE plan file at the target root. Per-workspace findings appear as a dedicated section within that file, not as N plans.
2. **Not** per-workspace stack detection *in 0.2.0*. `detect-stack.sh` continues to report the root stack. Cross-stack monorepos (one package Python, another TypeScript) are recognized as monorepos but scored against a single detected stack. Multi-stack scoring lands in a later spec.
3. **Not** a change to the `A01/A02/A03/A05` judges. Governance and root-doc quality are inherently root-only concerns.
4. **Not** a schema break. The 1 → 2 bump of `DETERMINISTIC_SCHEMA` is additive: new fields (`workspaces`, `per_workspace`) are optional; consumers reading schema-1 output work unchanged.

## 4. Workspace detection model

### 4.1 Contract

New script `plugins/ai-native-migration/scripts/detect-workspaces.sh`. Same shape as `detect-stack.sh`:

- **Input:** single positional argument, path to target repo root.
- **Output:** one JSON object on stdout, exit 0.
- **Errors:** exit 1 with human-readable message on stderr for preflight failures (path missing, not readable). NEVER exit non-zero for "not a monorepo" — that returns `{"type": "none", "roots": []}`.

Emitted JSON:

```json
{
  "type": "pnpm|yarn|npm|lerna|nx|turbo|gradle-multi|maven-multi|cargo|go-work|bazel|nx-native|rush|composer-multi|none|unknown",
  "roots": [
    { "path": "packages/api",   "manifest": "packages/api/package.json" },
    { "path": "packages/web",   "manifest": "packages/web/package.json" },
    { "path": "apps/mobile",    "manifest": "apps/mobile/package.json" }
  ],
  "detector_confidence": "high|medium|low",
  "notes": "one-line human-readable explanation of what was detected"
}
```

`roots[].path` is relative to the target root. `roots[].manifest` identifies the file that declared each root (the workspace glob's target, the `<module>` entry, etc.) so downstream tools can find per-workspace tooling.

### 4.2 Detector architecture

Following `detect-stack.sh`'s pattern, one function per workspace type. Each function returns 0 if it matched (setting `_WORKSPACE_TYPE` and populating `_WORKSPACE_ROOTS[]`) or 1 to skip. First match wins; detectors are ordered by confidence and specificity.

```bash
detect_pnpm_workspaces()      # pnpm-workspace.yaml with `packages:` field
detect_yarn_workspaces()      # package.json .workspaces (array or object with .packages)
detect_npm_workspaces()       # package.json .workspaces (npm 7+)
detect_lerna()                # lerna.json (may layer on top of the above)
detect_nx()                   # nx.json (typically layers on top of the above)
detect_turbo()                # turbo.json
detect_rush()                 # rush.json
detect_gradle_multi()         # settings.gradle{,.kts} with include(...)
detect_maven_multi()          # root pom.xml with <modules>
detect_cargo_workspaces()     # Cargo.toml with [workspace]
detect_go_workspaces()        # go.work
detect_bazel()                # WORKSPACE, WORKSPACE.bazel, or MODULE.bazel with visible packages
detect_composer_multi()       # composer.json with `repositories: [ { type: path } ]`
```

**Ordering rule:** more specific detectors run first. `nx` layers on top of `pnpm`, so `detect_nx` runs after `detect_pnpm_workspaces` — but if both match, the emitted `type` reflects the highest layer (nx), while the roots come from whichever detector enumerated them (pnpm's glob expansion).

### 4.3 Extensibility

Adding a new workspace type is one function + one line in the ordered dispatch list. No changes to `ai-native-verify` are required for the workspace type to be *detected*; behavior changes only happen when a specific D/A check consumes the `roots[]` list.

New workspace types are added by:
1. Writing `detect_<name>()` following the existing helpers (`file_contains`, `any_file_matches`, `extract_version`).
2. Inserting a call at the correct ordering position in the dispatch list.
3. Adding a fixture under `tests/fixtures/monorepos/<name>/` — a minimal skeleton that the new detector must classify correctly.
4. Adding an assertion to `tests/detect-workspaces.bats` (or the harness we settle on — see [Q-01 in the questions file](02-questions-1-monorepo-support.md#q-01--test-harness-for-detect-workspacessh)).

### 4.4 Confidence levels

- **`high`** — canonical manifest present (`pnpm-workspace.yaml`, `go.work`, root `pom.xml` with `<modules>`).
- **`medium`** — indirect signals (a `packages/` directory with N ≥ 2 sub-projects, each with their own `package.json`, but no root workspace declaration).
- **`low`** — heuristic-only (repo top-level has `packages/` OR `apps/` OR `services/` conventions but no manifest confirming intent).

`medium` and `low` results still list roots but are annotated in `notes`. The synthesizer uses these levels to phrase recommendations more conservatively when confidence is lower.

## 5. Scope model

### 5.1 Per-criterion scope

New §5 in `references/ai-native-checklist.md` — the full scope table is authoritative. Reproduced here for the design record:

| ID | Scope | Aggregation |
|---|---|---|
| D01 README | root-only | — |
| D02 CLAUDE.md symlink | root-only | — |
| D03 .claude/settings.json | root-only | — |
| D04 .mcp.json | root-only | — |
| D05 .devcontainer/ | root-only | — |
| D06 .pre-commit-config.yaml | root-only | — |
| D07 .editorconfig | root-only (cascades) | — |
| D08 docs/ARCHITECTURE, DEV, TESTING | root-primary | pass if root docs present; workspace docs are bonus, not required |
| D09 docs/specs/ | root-only | — |
| **D10 unit tests** | **per-workspace** | pass if ≥1 workspace has unit tests; report per-workspace verdicts |
| **D11 integration tests** | **per-workspace** | pass if ≥1 workspace has integration tests |
| **D12 E2E tests** | **per-workspace** | pass if ≥1 workspace has E2E; also permitted at root (Playwright often lives at root) |
| D13 CI | root-only | with monorepo-awareness note when CI lacks path filters or matrix builds |
| D14 AI review | root-only | — |
| D15 Conventional Commits | root-only | — |
| **D16 linter config** | **root-primary** | pass if root config present; per-workspace overrides tolerated |
| D17 .claude/commands/skills | root-only | — |
| D18 onboarding script | root-only | — |
| A01 AGENTS.md quality | root-only | — |
| A02 governance | root-only | — |
| A03 settings ↔ AGENTS | root-only | — |
| **A04 test legibility** | **per-workspace** | overall score = weighted avg of per-workspace scores, weight = test-file count per workspace |
| A05 ARCHITECTURE accuracy | root-primary | must mention workspaces when they exist; drift includes stale workspace references |
| A06 docs match reality | root-primary | cross-check against per-workspace tooling |
| A07 coverage signal | root-primary | per-workspace config allowed (JaCoCo per-module) |
| **A08 framework conventions** | **per-workspace when stacks differ, else root** | see §3 non-goal — 0.2.0 keeps single-stack scoring |

Bold rows are the ones changing behavior in 0.2.0. Non-bold rows document their existing scope for completeness.

### 5.2 Aggregation semantics for per-workspace checks

The per-workspace check runs against each workspace root, emits a per-workspace verdict, and aggregates to a single top-level verdict per the check's aggregation rule. The JSON scorecard exposes both:

```json
{
  "id": "D10",
  "verdict": "pass",
  "evidence": "unit tests present in 2 of 3 workspaces",
  "per_workspace": {
    "packages/api":    { "verdict": "pass", "evidence": "src/test/ present" },
    "packages/web":    { "verdict": "pass", "evidence": "__tests__/ present" },
    "apps/mobile":     { "verdict": "fail", "evidence": "no unit test structure detected" }
  }
}
```

The aggregation rule (`pass if ≥1`, `pass if ≥50%`, `pass if all`) is per-criterion and documented in the rubric. Default is `pass if ≥1` for tests — pragmatic, matches how humans read monorepo test coverage.

### 5.3 Root-primary semantics

For `root-primary` checks, the check runs against the root artifact first. If it passes, done. If it fails, the check also inspects workspaces (some checks have workspace fallbacks — e.g., D16 tolerates workspace-local ESLint configs). The check's evidence names both signals so the reader sees the full picture.

## 6. Deterministic-layer refactor

### 6.1 Workspace-aware runner

`ai-native-verify` gains a lightweight scope router:

```bash
run_check() {
  local id=$1
  local scope=$2  # ROOT_ONLY | PER_WORKSPACE | ROOT_PRIMARY
  case $scope in
    ROOT_ONLY)      check_$id ;;
    PER_WORKSPACE)  run_per_workspace "$id" ;;
    ROOT_PRIMARY)   check_$id || run_per_workspace "$id" ;;
  esac
}
```

Each check function is refactored to accept an optional workspace-root argument. The default (empty) argument means "root scope" — preserving pre-0.2.0 behavior for callers that invoke check functions directly.

### 6.2 New helpers in `lib/common.sh`

```bash
list_workspace_roots()   # cached wrapper over detect-workspaces.sh; returns paths
in_each_workspace()      # helper that runs a callback in each workspace root
emit_per_workspace()     # emits {per_workspace: {...}} JSON block into the result
aggregate_verdicts()     # applies an aggregation rule to a list of per-workspace verdicts
```

### 6.3 JSON schema version bump

`DETERMINISTIC_SCHEMA` in `ai-native-audit.js` moves 1 → 2. New fields:

- **Top-level:** `workspaces` (object matching detect-workspaces.sh output). Optional in schema-2 but always emitted by ai-native-verify going forward.
- **Per-result:** `per_workspace` (object mapping workspace path → `{verdict, evidence}`). Optional; only present for per-workspace or root-primary-with-workspace-fallback checks.

Schema version bumps to `"schema_version": "2"`. Documented in `docs/DEVELOPMENT.md`. Existing schema-1 consumers see an unknown field but can continue reading required fields; workflow-side handling gracefully degrades if `workspaces` is absent (flat-repo behavior).

## 7. Judge inputs update

- **A04** now receives the workspace roots (`args.workspaces.roots`) and iterates them, sampling tests from each. Overall score is a weighted average. Per-workspace evidence appears in `dimension_specific`.
- **A08** receives the workspace roots but continues to score against the root-detected stack in 0.2.0 (per §3 non-goal). It sets `dimension_specific.workspaces` for the plan-file reader's context.
- The **synthesizer** receives the workspace list unchanged, uses it to emit a `## Per-workspace findings` section in the plan file when `workspaces.type != "none"`.

## 8. Plan file structure change

Plan file gains one new top-level section (only when `workspaces.type != "none"`):

```markdown
## Workspace layout

**Detected type:** pnpm workspaces (high confidence)
**Roots:** 3 workspaces

  - packages/api      (Node/TypeScript, no framework detected)
  - packages/web      (Node/TypeScript, Next.js)
  - apps/mobile       (React Native — outside root stack)

Per-criterion scope: see `rubric §5 Scope in monorepos`.
```

Per-workspace verdicts appear inside their respective through-line finding entries, not as a separate list:

```markdown
### Verification at every level

- **[D10]** Unit tests present in 2/3 workspaces (pass)
  - **Evidence:** packages/api/src/test/ (pass), packages/web/__tests__/ (pass), apps/mobile — no unit tests (fail)
  - **Recommendation:** Add unit tests to apps/mobile OR declare test-optional in its AGENTS.md
  - **Source:** rubric §Part 1 D10
  - **Task:** T-<NN>
```

This keeps the plan file navigable — readers see gaps by through-line as before, with workspace-scoped detail inline.

## 9. Backward compatibility

- **Flat repos:** `detect-workspaces.sh` emits `{"type": "none", "roots": []}`. The scope router runs every check as `ROOT_ONLY`. No behavior change. Existing plan files re-audited under 0.2.0 produce byte-identical findings for their D-check set.
- **Schema consumers:** The JSON scorecard gains fields; no fields are removed or renamed. Version bumps to 2 so consumers can conditionally handle the new fields.
- **Templates:** No template changes in Part 2. Bootstrap behavior unchanged.
- **Workflow (`ai-native-audit.js`):** Guard against absent `workspaces` field in the deterministic scorecard so older callers still work.

## 10. Test strategy

New fixtures under `tests/fixtures/monorepos/`:

```
tests/fixtures/monorepos/
├── pnpm-basic/           # 2 packages, each with tests
├── yarn-workspaces/      # 3 workspaces, one with no tests (fail case)
├── lerna-on-pnpm/        # lerna.json layered on pnpm-workspace.yaml
├── nx-basic/             # nx.json with 2 apps
├── turbo-basic/          # turbo.json with 2 packages
├── gradle-multi/         # settings.gradle with 3 subprojects
├── maven-multi/          # pom.xml with 3 modules
├── cargo-workspaces/     # Cargo.toml with 2 members
├── go-work/              # go.work with 2 modules
└── flat-repo/            # control: verify no false positive
```

Each fixture is small (a few files each; no real code, just structural anchors) and drives at least three assertions:

1. `detect-workspaces.sh` returns the expected `type` and `roots[]`.
2. `ai-native-verify` reports per-workspace verdicts correctly for D10/D11/D12/D16.
3. The workflow (via a mocked judge, or a real thorough run under a token-budget flag) produces a plan file with the expected per-workspace section.

## 11. Rollout — phased

Landing all of §4-§10 in a single PR is high-risk. Phases:

| Phase | Deliverable | Governance touch |
|---|---|---|
| **P-1** ✅ | Judge cross-check patch (this branch, done) | workflows/ only |
| **P-2** | `detect-workspaces.sh` + bats fixtures | new script, tests/ only |
| **P-3** | Rubric §5 lands in `references/ai-native-checklist.md` | **governance lift+restore** on references/ |
| **P-4** | Scope router in `ai-native-verify` + `lib/common.sh` helpers | scripts/ only |
| **P-5** | Refactor D10, D11, D12, D16 to accept workspace argument | scripts/ only |
| **P-6** | JSON schema bump (1 → 2) in `ai-native-audit.js` + workflow guards | workflows/ only |
| **P-7** | A04 iterates workspaces; A08 receives roots | workflows/ only |
| **P-8** | Synthesizer emits `## Workspace layout` + per-workspace evidence | workflows/ only |
| **P-9** | Fixture-driven regression tests | tests/ only |
| **P-10** | Docs updates: README + docs/DEVELOPMENT.md schema notes | docs/ only |

Each phase is one PR (or one commit inside the 0.2.0 branch, depending on how you want to review). P-3 is the only phase that lifts the references/ deny rule; all other phases stay outside governance-locked territory.

## 12. Version and release

- **Target version:** `0.2.0` — MINOR bump because behavior changes are additive from a consumer POV but visible to the user (new plan-file section, new JSON fields).
- **Breaking changes:** None. Schema is additive; existing behavior on flat repos is unchanged; existing plan files remain readable.
- **Release note focus:** "Monorepo support: workspace detection + per-workspace D10-D12/D16 verdicts + per-workspace A04 scoring." Link this spec.

## 13. Open decisions

Tracked in [02-questions-1-monorepo-support.md](02-questions-1-monorepo-support.md). Key questions blocking implementation:

- Q-01: test harness choice for `detect-workspaces.sh` (bats-core vs. existing tests/all.sh conventions)
- Q-02: aggregation defaults (pass if ≥1 vs. pass if ≥50%)
- Q-03: how to represent partial passes at the per-workspace layer
- Q-04: cross-stack monorepo policy for 0.2.0 (defer to 0.3.0?)
- Q-05: whether `docs/plans/` in a monorepo should live at root or per-workspace

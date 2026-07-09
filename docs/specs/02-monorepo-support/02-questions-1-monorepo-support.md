# Spec 02 — Questions Round 1

**Round:** 1
**Dates:** 2026-07-09 (open)
**Reviewer:** T. Goulas
**Status:** open — resolutions needed before implementation of P-2 onward

This file captures open decisions surfaced while drafting `02-spec-monorepo-support.md`. Each question should be resolved before the implementation phase it blocks begins.

---

## Q-01 — Test harness for `detect-workspaces.sh`

**Context:** `detect-stack.sh` today is tested via bash-driven assertions in `tests/all.sh`. `detect-workspaces.sh` has richer output (a structured `roots[]` array) and more fixtures (~10 monorepo shapes), so the assertion volume is materially higher.

**Options:**

1. **Extend the existing `tests/all.sh` bash harness.** Consistent with prior art. Cheap. Assertions on JSON output stay `jq`-style, which the harness already knows how to run.
2. **Adopt `bats-core` for the new fixtures.** More idiomatic bash testing. Cleaner setup/teardown per fixture. Adds a dev dependency and a new harness the repo hasn't used before.
3. **Node-side harness under `tests/detect-workspaces.test.js`.** Uses the same test runner the workflow tests use (whatever `tests/all.sh` invokes for the workflow layer). Keeps all structured-output tests in one language.

**Blocks:** P-2 (workspace detector implementation).

**Reviewer decision:** _pending_.

---

## Q-02 — Default aggregation rule for per-workspace tests

**Context:** For D10/D11/D12, the top-level verdict aggregates over per-workspace verdicts. The spec proposes `pass if ≥1 workspace passes`. Alternatives exist.

**Options:**

1. **`pass if ≥1`.** Pragmatic. Matches "does this monorepo test anything at all". Downside: a 10-package monorepo with tests in only 1 package still scores `pass` at D10, hiding meaningful gaps.
2. **`pass if ≥50%`.** Rewards broad coverage. Downside: policy call about what fraction is enough — feels arbitrary.
3. **`partial if some pass, fail if none`.** Uses the existing `partial` verdict to convey "some but not all". Fits the rubric's existing 4-verdict vocabulary. Reader sees the exact per-workspace breakdown in evidence anyway.

**Recommendation:** Option 3 — `partial` when 0 < passing < total, `pass` when all pass, `fail` when none pass. It preserves the information content without inventing new verdicts.

**Blocks:** P-4 (scope router implementation).

**Reviewer decision:** _pending_.

---

## Q-03 — Per-workspace partial verdicts

**Context:** A single workspace might have unit tests but no integration tests. Does the per-workspace D10 verdict for that workspace emit `pass` (has unit tests) or `partial` (only some test layers)?

**Options:**

1. **Per-workspace verdicts are single-layer.** D10 per-workspace = "unit tests present" (pass/fail only). D11 per-workspace = "integration tests present". Reader combines them mentally.
2. **Per-workspace verdicts summarize across layers.** For the same workspace, D10/D11/D12 report a combined per-workspace signal. Fewer per-workspace entries but each is more informative.

**Recommendation:** Option 1 — one per-workspace verdict per D-check, matching the pattern the D-checks already follow at the root level. Consistent, and the per-workspace JSON stays small.

**Blocks:** P-5 (D-check refactor).

**Reviewer decision:** _pending_.

---

## Q-04 — Cross-stack monorepos in 0.2.0

**Context:** A monorepo can contain packages in different stacks — e.g., a TypeScript API and a Python ML service. `detect-stack.sh` today emits ONE stack per repo (from root-level indicators). §3 non-goal (2) defers per-workspace stack detection to a later spec.

**Options:**

1. **0.2.0: root stack only.** A08 scores against the root's detected stack. The plan file's Confidence section flags "monorepo appears to be multi-stack — A08 evaluated only against root stack". Users who need multi-stack can invoke `/ai-native-migration:migrate` per-workspace manually as a workaround.
2. **0.2.0: per-workspace stack detection + per-workspace A08.** Ships as part of Part 2. Bigger surface area; more places to break.
3. **0.2.0: detect-only.** `detect-stack.sh` gains per-workspace stack detection and emits it in JSON, but A08 continues to score against root stack (consumers can opt in later).

**Recommendation:** Option 3 — split the detection work from the scoring work. Per-workspace stacks appear in the JSON immediately, which lets us test the detector without changing judge behavior. A08 stays single-stack in 0.2.0; multi-stack scoring becomes Spec 03.

**Blocks:** §3 non-goal (2), P-7 (A08 changes).

**Reviewer decision:** _pending_.

---

## Q-05 — Where does the plan file live in a monorepo?

**Context:** The current design writes `<target>/docs/plans/ai-native-migration-<date>.md`. In a monorepo where `docs/` exists at the root, this is unambiguous. But some monorepos have `docs/` per-workspace or no root `docs/` at all.

**Options:**

1. **Root only, always.** Plan lives at `<target>/docs/plans/`. If root `docs/` doesn't exist, create it. Simple, one artifact per audit.
2. **Root, but note per-workspace docs/ if they exist.** Plan still at root, but the synthesizer notes that per-workspace docs exist and could benefit from their own plans (future work).
3. **Configurable via a flag.** `--plan-location=<path>` on the SKILL invocation. Overkill for the common case.

**Recommendation:** Option 1 — the plan is a whole-repo artifact regardless of where docs live inside the repo. If root `docs/` is absent, the plan-file synthesizer creates `docs/plans/` at root (already existing behavior — it creates the directory when missing).

**Blocks:** P-8 (synthesizer changes).

**Reviewer decision:** _pending_.

---

## Q-06 — Bazel and other rare workspace types

**Context:** The spec lists Bazel among the detectors but Bazel workspaces are structurally different (BUILD files everywhere, not just at package roots). Full Bazel support is significantly more work than the other detectors.

**Options:**

1. **Best-effort Bazel in 0.2.0.** Detect `WORKSPACE` / `MODULE.bazel` presence, treat every directory containing a `BUILD` or `BUILD.bazel` file as a workspace root. Coarse but functional.
2. **Detect only, no root enumeration in 0.2.0.** Emit `type: "bazel"`, empty `roots[]`, and a note explaining Bazel enumeration is deferred. Marks the intent without shipping half-working code.
3. **Skip Bazel in 0.2.0.** Return `type: "none"` for Bazel repos. Add it in a later spec.

**Recommendation:** Option 2 — the detector recognizes Bazel but doesn't pretend to fully enumerate it. Downstream checks fall back to root-only scope for Bazel repos, which is at least not wrong.

**Blocks:** P-2 (workspace detector).

**Reviewer decision:** _pending_.

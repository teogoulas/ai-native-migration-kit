# Spec 02 — Task List

**Target:** 0.2.0 release
**Depends on:** [02-spec-monorepo-support.md](02-spec-monorepo-support.md), open questions in [02-questions-1-monorepo-support.md](02-questions-1-monorepo-support.md).

---

## Phase 0 — Judge cross-check (DONE)

- [x] **T-01** — Patch A04 to search for tests before abstaining. Commit `a5832a0`.
- [x] **T-02** — Patch A06 to cross-check tooling before flagging as missing. Commit `a5832a0`.
- [x] **T-03** — Patch A07 to cross-check CI locations before flagging as missing. Commit `a5832a0`.
- [x] **T-04** — Synthesizer aggregates `deterministic_disagreement` and surfaces in Confidence. Commit `a5832a0`.

## Phase 2 — Workspace detector

Blocked on: Q-01 (test harness), Q-06 (Bazel scope).

- [ ] **T-05** — Create `plugins/ai-native-migration/scripts/detect-workspaces.sh` with the contract from spec §4.1. Preflight, JSON emission, `type: "none"` default.
- [ ] **T-06** — Implement pnpm/yarn/npm/lerna/nx/turbo/rush detectors (JS/Node family).
- [ ] **T-07** — Implement gradle-multi and maven-multi detectors (JVM family).
- [ ] **T-08** — Implement cargo-workspaces and go-work detectors.
- [ ] **T-09** — Implement composer-multi detector (PHP family).
- [ ] **T-10** — Implement Bazel detector per Q-06 resolution.
- [ ] **T-11** — Add fixtures under `tests/fixtures/monorepos/` (one per detector).
- [ ] **T-12** — Add detector tests per Q-01 resolution. At minimum: `type` correct, `roots[]` correct, `notes` non-empty, exit 0.

## Phase 3 — Rubric §5 in canonical checklist

Blocked on: nothing (design-side change).

- [ ] **T-13** — Governance lift: remove references/ deny rule for this PR from `.claude/settings.json`, or lift in-PR per repo policy.
- [ ] **T-14** — Add §5 "Scope in monorepos" to `references/ai-native-checklist.md` with the full per-criterion scope table from spec §5.1.
- [ ] **T-15** — Cross-link §5 from each affected D-check row and A-check row in §Part 1 / §Part 2.
- [ ] **T-16** — Restore references/ deny rule before merge.
- [ ] **T-17** — Update `references/judging-rubrics.md` to reference §5 from the A04/A08 sections that consume workspace scope.

## Phase 4 — Scope router in `ai-native-verify`

Blocked on: Q-02 (aggregation default), Q-03 (per-workspace partial rules).

- [ ] **T-18** — Add scope declarations near the check registry: `SCOPE_ROOT_ONLY | SCOPE_PER_WORKSPACE | SCOPE_ROOT_PRIMARY`.
- [ ] **T-19** — Add `run_check()` dispatcher that reads the scope and routes to a workspace-iterating runner or the direct check.
- [ ] **T-20** — Add helpers to `lib/common.sh`: `list_workspace_roots`, `in_each_workspace`, `emit_per_workspace`, `aggregate_verdicts`.
- [ ] **T-21** — Cache `detect-workspaces.sh` output for the duration of one `ai-native-verify` run (same pattern as detect-stack caching, `ai-native-verify:600-650`).
- [ ] **T-22** — Bats/unit tests for the router: root-only checks unchanged, per-workspace checks fan out, root-primary checks fall back correctly.

## Phase 5 — Per-workspace D-checks

Blocked on: Phase 2, Phase 4.

- [ ] **T-23** — Refactor `check_D10` to accept optional workspace-root argument. Update its per-stack directory-list to be workspace-relative.
- [ ] **T-24** — Same refactor for `check_D11`, `check_D12`.
- [ ] **T-25** — Refactor `check_D16` for root-primary semantics (root config passes; else check per-workspace).
- [ ] **T-26** — Update `check_D08` for root-primary semantics (per-workspace docs are bonus).
- [ ] **T-27** — Emit `per_workspace` block for each affected check per spec §5.2.
- [ ] **T-28** — Regression test: on the pre-existing flat-repo fixtures, D10-D12 verdicts are byte-identical to pre-0.2.0.

## Phase 6 — JSON schema bump

Blocked on: Phase 5.

- [ ] **T-29** — Update `DETERMINISTIC_SCHEMA` in `plugins/ai-native-migration/workflows/ai-native-audit.js` to include `workspaces` and per-result `per_workspace` fields (both optional).
- [ ] **T-30** — Bump `schema_version` from `"1"` to `"2"` in `ai-native-verify`'s JSON emit path.
- [ ] **T-31** — Document schema-2 additions in `docs/DEVELOPMENT.md`.
- [ ] **T-32** — Add workflow-side guard: if `deterministic.workspaces` is absent (schema-1 caller), treat as flat repo.

## Phase 7 — Judges consume workspace roots

Blocked on: Phase 6, Q-04 (cross-stack policy).

- [ ] **T-33** — A04: read `deterministic.workspaces.roots`, iterate, sample up to 5 tests per workspace per layer. Aggregate score as weighted avg.
- [ ] **T-34** — A08: receive `workspaces.roots` and emit `dimension_specific.workspaces = [...]`. Continue scoring against root stack in 0.2.0 per Q-04 resolution.
- [ ] **T-35** — A04/A08 prompt cleanups to reference new workspace input.
- [ ] **T-36** — Regression test: mocked A04 receives workspaces, iterates correctly, weighted-avg matches expected value on a 3-workspace fixture.

## Phase 8 — Synthesizer per-workspace section

Blocked on: Phase 7.

- [ ] **T-37** — Add `## Workspace layout` section to synthesizer prompt, emitted only when `workspaces.type != "none"`.
- [ ] **T-38** — Update per-finding format to include per-workspace evidence for per-workspace D-checks.
- [ ] **T-39** — Update Confidence section to name workspace-scoped limitations (Q-04 cross-stack single-scoring, Bazel detect-only per Q-06, etc.).
- [ ] **T-40** — Task-list ordering: workspace-scoped tasks group per-workspace (all tasks for `apps/mobile` together), root-scoped tasks stay in severity order.

## Phase 9 — Integration & regression tests

Blocked on: all prior phases.

- [ ] **T-41** — End-to-end: run `ai-native-verify` against each monorepo fixture, snapshot the JSON output, commit as expected-output fixtures.
- [ ] **T-42** — End-to-end: run the full workflow (light depth to keep tokens bounded) against one monorepo fixture, verify plan file structure.
- [ ] **T-43** — Add monorepo fixtures to the self-audit CI so `./tests/all.sh` covers them on every PR.
- [ ] **T-44** — Verify the kit still audits itself clean (`ai-native-verify .` returns 0 mandatory fails introduced by this PR).

## Phase 10 — Docs and release

Blocked on: all prior phases.

- [ ] **T-45** — Update `README.md` with a "Monorepo support" section linking spec 02.
- [ ] **T-46** — Update `AGENTS.md` if the audit invocation contract changes for monorepos (should not, but check).
- [ ] **T-47** — Bump plugin version to `0.2.0` in the plugin manifest.
- [ ] **T-48** — Draft PR description linking spec 02, listing behavioral changes per §5.1 scope table.
- [ ] **T-49** — Post-merge: tag `v0.2.0` release.

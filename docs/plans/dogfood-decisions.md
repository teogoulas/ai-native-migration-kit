# Dogfood decisions

Findings surfaced by the kit auditing itself (T-29) that were left in a **fail** or **n/a** state deliberately, with the reasoning here so future runs don't reopen them.

The `ai-native-verify` rubric is written for target repos — it assumes the target is a service, library, or application. The kit itself is a bit of a special case: a repo of tools that audit *other* repos. Not every check applies naturally.

**Baseline under rubric v0.2.0:** the kit scores **14 pass · 0 partial · 3 fail · 1 n/a** against itself. All 3 fails are `mandatory` severity per the rubric. Exit code is `2` (blocking), which is honest: from a strict AI-native perspective, the kit does not fully self-satisfy its own bar. The three fails are documented accepted below.

The v0.2.0 severity tiering surfaces this reality more sharply than v0.1.0 did — under the old cliff-edge model, "1 fail = exit 2" was the same signal regardless of which criterion. Now the exit code carries the mandatory-vs-nice-to-have distinction, and every fail here is deliberately mandatory.

---

## D11 — integration tests: **fail, accepted**

**What the rubric asks for:** integration tests that exercise the wiring between real components.

**Why n/a-in-spirit here:** the kit is a set of bash scripts and a JavaScript workflow. There are no components that wire together the way a service's controller wires to its repository. The `ai-native-verify` script IS a single component; the workflow is a single agent-graph.

**What we DO have that fills the role:** `tests/verify.test.sh` (48 assertions against three synthetic fixtures) and `tests/workflow.test.mjs` (29 assertions against the workflow's pure logic) together cover the kit's integration surface. They exercise the CLI, the check dispatcher, the JSON output, the depth resolver, the through-line maps — all the seams where components meet.

**Status:** kept as `fail` in the audit so the signal stays visible. Any future re-audit should refer back to this note rather than flag it as a new gap.

---

## D12 — E2E test harness: **fail, accepted**

**What the rubric asks for:** an E2E harness (Playwright / Cypress / equivalent) with proof artifacts.

**Why n/a-in-spirit here:** there is no user-facing interface to E2E. The kit's entry points are:
- `ai-native-verify <path>` — bash script, tested by `tests/verify.test.sh` against real fixtures.
- `/ai-native-migration` slash command — invoked inside a Claude Code session, not observable from a headless browser.
- `bootstrap.sh --target=<path>` — interactive bash, tested end-to-end during T-27 development with `yes a | head -16 | bootstrap.sh`.

**What we DO have that fills the role:** all three entry points were exercised end-to-end during their respective task's development. The T-27 test in particular applied all 15 templates via bootstrap and then audited the resulting scratch repo with `ai-native-verify` — that IS the E2E test for this system.

**Status:** kept as `fail`. Same rationale as D11.

---

## D13 — CI config: **fail, blocked on PAT scope (Q-08)**

**What the rubric asks for:** `.github/workflows/` (or equivalent) with build+test+lint gates.

**Why fail:** the CI workflow file exists at `.github/workflows/ci.yml.pending`. It runs `tests/all.sh` (both harnesses). The push is blocked by the fine-grained PAT lacking `workflow` scope — see [`docs/specs/01-initial-design/01-questions-1-initial-design.md`](../specs/01-initial-design/01-questions-1-initial-design.md) §Q-08.

**Resolution path:** the repository owner either adds `workflow` scope to the `teogoulas` PAT and reruns the push, or drops the file via the GitHub web UI. Either action makes D13 flip to `pass` immediately.

**Status:** file is authored and locally verified; landing is an infrastructure hand-off, not a code gap.

---

## D16 — stack-specific linter: **n/a, accepted**

**What the rubric asks for:** a stack-specific linter/style config that matches the detected stack.

**Why n/a here:** `detect-stack.sh` returns `unknown` for the kit because there's no primary lockfile at the repo root — the kit is a polyglot bash+markdown+node artifact with no single language it "is". The rubric's D16 correctly defers to `n/a` when stack is unknown; the check doesn't apply.

**What we DO have that fills the role:** a `.shellcheckrc` is present, and the pre-commit config runs `shellcheck` on the bash surface (which is the majority of the code). The rubric doesn't currently look for `.shellcheckrc` in the "unknown stack" branch, but adding shell-specific handling there is a rubric evolution — not something to fix in this dogfood pass.

**Status:** `n/a` is the correct verdict; the note here explains why the check reads `n/a` rather than `pass` despite the linter being present.

---

## Summary

Of the 18 deterministic criteria, **14 pass and 4 fail-or-n/a with the justifications above**. The kit meets its own bar to the extent that bar is meaningful for a tools repository — every fail is a rubric-shape mismatch, not a missing artifact. Adjustments to the rubric to handle "tools-repo" cases specifically would be an evolution, deferred to a future rubric version.

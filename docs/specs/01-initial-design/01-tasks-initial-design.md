# Spec 01 — Task Breakdown

**Status:** proposed
**Date:** 2026-07-08
**Source spec:** `01-spec-initial-design.md`

PR-sized units of work to deliver the first working version of `ai-native-migration-kit`, in dependency order. Every task is small enough to review in one sitting (≈15 min – 2 hours) and produces something demonstrable. Tasks are grouped into phases; phases are strict — no task in phase N+1 starts until phase N is done.

## Legend

- **Deps** — task IDs this task depends on
- **Est** — rough authoring effort, not calendar time
- **Artifact** — what lands in the repo
- **Verify** — how we know it's done
- **Human-decision** — the task contains a decision only a human should make; the task cannot be autonomously completed

---

## Phase 0 — Foundation

The kit needs a home before anything else can land. Self-governance (the `.claude/settings.json` deny-list on templates/references) is intentionally **not** in this phase — it belongs at the very end of the build, after the sources are stable. See T-32 and the [rationale in the questions file](01-questions-1-initial-design.md#q-06--when-does-the-self-governance-deny-list-land) for why.

### T-01 — Repo skeleton
- **Deps:** none
- **Est:** 30m
- **Artifact:**
  - `README.md` (short — one paragraph, points at `docs/`)
  - `LICENSE` (MIT or Apache-2.0 — **human-decision**)
  - `.gitignore` (bash / Node / OS noise)
  - `AGENTS.md` — includes the governance section documenting the intended deny-list as advisory. The two-layer pattern (advisory in AGENTS.md, enforced in settings.json) is a design invariant of the kit; see rubric §4.1 D03 and §4.2 A03. The enforced settings.json lands in T-32.
  - `CLAUDE.md → AGENTS.md` symlink
  - `docs/ARCHITECTURE.md` — one-page: "SKILL.md front door → deterministic script → workflow → plan file"
  - `docs/DEVELOPMENT.md` — one-page: how to work on the kit locally
  - `docs/specs/01-initial-design/*` — spec files already present
- **Verify:** `ls -la` shows all files; `readlink CLAUDE.md` returns `AGENTS.md`; `git init` + first commit succeeds.
- **Human-decision:** license choice.

---

## Phase 1 — References (canonical rubric)

References describe the *rules* the kit applies. They are read by every judge and by every human reviewer. During the build they are edited freely; once the kit is complete, T-32 freezes them with the deny-list.

### T-03 — `references/patterns-explained.md`
- **Deps:** T-01
- **Est:** 45m
- **Artifact:** Plain-language explanation of judge / adversarial verify (N-vote) / completeness critic patterns, so any human reading a generated plan file understands how the findings were produced.
- **Verify:** Read by a fresh reader who has not seen the spec — they can articulate the three patterns unaided.

### T-04 — `references/ai-native-checklist.md`
- **Deps:** T-01
- **Est:** 1.5h
- **Artifact:** Canonical rubric — all 18 deterministic criteria (D01–D18) and all 8 agentic judges (A01–A08) from spec §4, with per-criterion:
  - one-line intent
  - example indicator (what a satisfying file/directory looks like — filenames only, not references to any specific external repository)
  - through-line mapping (one of the four)
  - what `pass` / `partial` / `fail` looks like
  - remediation hint
- **Verify:** File is the sole source consumed by both `ai-native-verify` and the workflow's synthesis step — no criterion drift between deterministic script and agentic judges.

### T-05 — `references/judging-rubrics.md`
- **Deps:** T-04
- **Est:** 1h
- **Artifact:** Per-judge (A01–A08) prompt scaffolding + score anchors (what 0/1/2/3 look like for each dimension the judge scores). Consumed by the workflow when it constructs judge prompts.
- **Verify:** Every judge in `workflows/ai-native-audit.js` sources its prompt scaffolding from a named section in this file — no inline prompt content in the workflow.

### T-06 — `references/stack-generic.md`
- **Deps:** T-04
- **Est:** 30m
- **Artifact:** Thin cross-stack floor used by A08 when `context7` is unavailable — 5–10 conventions applicable to any stack (test names describe behavior, config in files not code, deterministic execution, etc.).
- **Verify:** Deliberately short (< 100 lines). If it grows, it is drifting toward being a per-stack overlay — the wrong direction.

---

## Phase 2 — Deterministic layer (`ai-native-verify`)

The kit's most reusable artifact per spec §10: a standalone bash script that target repos can wire into their own CI/pre-push guardrails after migration.

### T-07 — `scripts/detect-stack.sh`
- **Deps:** T-04
- **Est:** 1h
- **Artifact:** Pure bash. Inspects target repo for stack indicators (`pom.xml`, `build.gradle`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json`). Emits JSON on stdout: `{stack, framework, versions, package_manager, test_framework}`. Returns `{stack: "unknown"}` cleanly when nothing matches.
- **Verify:** Unit-tested against synthetic fixtures under `tests/fixtures/stacks/` — a minimal Java+Gradle fixture returns `{stack: "java", framework: "spring-boot", ...}`; a minimal Node+Next fixture returns `{stack: "node", framework: "next", ...}`; an empty directory returns `{stack: "unknown"}`. Fixtures contain only the lockfiles/manifests needed to trigger detection; no real source code.

### T-08 — `ai-native-verify` scaffolding
- **Deps:** T-04
- **Est:** 45m
- **Artifact:** `skill/scripts/ai-native-verify` executable bash script implementing the contract from spec §10:
  - argparse for `--format=text|json`, `--check=<list>`, `<target-repo-path>`
  - preflight (path exists, is git repo, readable)
  - stub check runner that iterates D01–D18 and returns `n/a` for all
  - exit code logic (§10 table)
- **Verify:** `ai-native-verify /tmp/nonexistent` → exit 3. `ai-native-verify --format=json <valid-repo>` → JSON on stdout with 18 `n/a` entries, exit 0. `--help` prints the contract.

### T-09 — `ai-native-verify` — implement checks D01–D09
- **Deps:** T-08
- **Est:** 1.5h
- **Artifact:** Real implementations for:
  - D01 `AGENTS.md` present + non-empty
  - D02 `CLAUDE.md` symlink → `AGENTS.md`
  - D03 `.claude/settings.json` present with `denyList` + hooks (structural: JSON parseable + required keys present)
  - D04 `.mcp.json` present (n/a if repo has no MCP indicator)
  - D05 `.devcontainer/devcontainer.json` + `Dockerfile`
  - D06 `.pre-commit-config.yaml` present
  - D07 `.editorconfig` present
  - D08 `docs/{ARCHITECTURE,DEVELOPMENT,TESTING}.md` all present
  - D09 `docs/specs/` directory exists
- **Verify:** Run against a synthetic `tests/fixtures/perfect/` fixture that satisfies all 9 criteria → all pass. Delete each of the 9 required artifacts one at a time in a scratch copy → the corresponding check flips to `fail`. Run against `tests/fixtures/empty/` → all 9 fail.

### T-10 — `ai-native-verify` — implement checks D10–D18
- **Deps:** T-09
- **Est:** 1.5h
- **Artifact:** Real implementations for:
  - D10 unit test folder(s) exist (heuristic per stack: `src/test/java`, `test/`, `tests/`, `__tests__/`)
  - D11 integration test folder(s) exist (heuristic: `**/integration/**`, tagged tests)
  - D12 E2E folder exists (`e2e-tests/`, `playwright.config.*`, `cypress.config.*`)
  - D13 `.github/workflows/` (or `.gitlab-ci.yml`, `.circleci/config.yml`) — CI configuration present
  - D14 `.coderabbit.yaml` or equivalent AI-review config
  - D15 Conventional Commits enabled (commitlint config, `.gitmessage`, or scoped commit skill)
  - D16 Stack-specific linter present (via detect-stack output)
  - D17 `.claude/commands/` or `.claude/skills/` non-empty
  - D18 Onboarding script exists (`scripts/setup-*.sh` or `Makefile` target that installs pre-commit)
- **Verify:** Same shape as T-09 — `tests/fixtures/perfect/` passes; scratch damage flips checks; `tests/fixtures/empty/` fails all.

### T-11 — `ai-native-verify` JSON output
- **Deps:** T-10
- **Est:** 30m
- **Artifact:** `--format=json` produces one JSON object per invocation: `{target, timestamp, stack, results: [{id, verdict, evidence, remediation_hint}, ...], summary: {pass, partial, fail, na}}`. Schema documented in `docs/DEVELOPMENT.md`.
- **Verify:** `ai-native-verify --format=json <repo> | jq '.summary'` returns expected counts.

### T-12 — Deterministic self-test
- **Deps:** T-11
- **Est:** 45m
- **Artifact:** `tests/verify.test.sh` — bats-core or plain bash test harness that runs `ai-native-verify` against three synthetic, kit-owned fixtures:
  - `tests/fixtures/empty/` — nearly-empty directory (expected: fail on almost every check)
  - `tests/fixtures/perfect/` — a full scaffold satisfying every check (expected: full pass; this fixture is authored specifically as the passing reference)
  - `tests/fixtures/partial/` — a mid-state fixture triggering a mix of `pass` / `partial` / `fail` verdicts (expected: exercises the `partial` code paths — e.g. AGENTS.md present but no CLAUDE.md symlink, pre-commit config present but no onboarding script)
- **Verify:** `tests/verify.test.sh` exits 0. CI job wired for it under `.github/workflows/`. No external repository is referenced by any fixture.

---

## Phase 3 — Templates (baseline artifacts for `--apply`)

Templates are authored freely during Phase 3 and will be frozen by T-32 at the end of the build. Any edit after T-32 requires lifting the deny-list in `.claude/settings.json` in the same PR.

### T-13 — Templates batch 1 — context + standards
- **Deps:** T-04
- **Est:** 1h
- **Artifact:**
  - `skill/templates/AGENTS.md.tmpl` — skeleton with the five canonical sections and a governance sub-section (do-not-modify / always-run / escalate-when)
  - `skill/templates/.editorconfig.tmpl`
  - `skill/templates/.gitmessage.tmpl` (Conventional Commits template)
  - `skill/templates/.coderabbit.yaml.tmpl`
- **Verify:** Templates use `{{stack}}`, `{{project_name}}` placeholders replaced by `bootstrap.sh` (T-27). Rendered templates parse as valid Markdown/JSON/YAML per their type. Rendering into `tests/fixtures/empty/` produces files that make the corresponding deterministic checks (D01, D07, D14, D15) flip from `fail` to `pass`.

### T-14 — Templates batch 2 — governance
- **Deps:** T-04
- **Est:** 45m
- **Artifact:**
  - `skill/templates/.claude/settings.json.tmpl` — denyList baseline covering commonly destructive operations (`git push --force`, `git push --force-with-lease`, `DROP TABLE`, `kubectl delete`) + `PostToolUse` audit hook writing to `.claude/audit.log`
  - `skill/templates/.mcp.json.tmpl` — commented sample entries only; not wired to any real server
- **Verify:** JSON validates. Deny-list entries match the baseline documented in rubric §4.1 D03 and spec §12.

### T-15 — Templates batch 3 — environment
- **Deps:** T-04
- **Est:** 45m
- **Artifact:**
  - `skill/templates/.devcontainer/devcontainer.json`
  - `skill/templates/.devcontainer/Dockerfile` — stack-neutral base with `pre-commit` and `git` preinstalled; comment placeholder for stack-specific additions
  - `skill/templates/.pre-commit-config.yaml.tmpl` — baseline hooks (trailing whitespace, yaml/json lint, markdownlint, commitizen-style commit-msg)
- **Verify:** `docker build .devcontainer/` succeeds against the rendered template.

### T-16 — Templates batch 4 — docs skeletons
- **Deps:** T-04
- **Est:** 1h
- **Artifact:**
  - `skill/templates/docs/ARCHITECTURE.md.tmpl` — sections with prompts to fill in
  - `skill/templates/docs/DEVELOPMENT.md.tmpl` — dev workflow, TDD stance
  - `skill/templates/docs/TESTING.md.tmpl` — three-layer test strategy + AI-legibility guidance (isolated assertions, descriptive names, readable-diff matchers, deterministic execution — as codified in rubric §4.2 A04)
  - `skill/templates/docs/PRECOMMIT.md.tmpl` — hook configuration and troubleshooting
- **Verify:** Rendered templates parse as valid Markdown; internal `[link](@path)` references point to files the template also creates.

### T-17 — Templates batch 5 — onboarding scripts
- **Deps:** T-04
- **Est:** 45m
- **Artifact:**
  - `skill/templates/scripts/setup-precommit.sh.tmpl` — one-command installer for pre-commit hooks (`pip install pre-commit`, `pre-commit install`, `pre-commit install --hook-type commit-msg`, then `pre-commit run --all-files` as a clean-baseline check), stack-adjusted (uses detected package manager). This is the artifact D18 checks for.
  - `skill/templates/scripts/onboarding-check.sh.tmpl` — verifies each governance requirement is active (`.claude/settings.json` committed, pre-commit hooks installed locally, MCP servers reachable if declared)
- **Verify:** Rendered against `tests/fixtures/empty/` + run → both scripts execute successfully; `setup-precommit.sh` installs hooks; `onboarding-check.sh` reports each check with pass/fail.

---

## Phase 4 — Skill entry point + workflow (agentic layer)

### T-18 — `skill/SKILL.md` — front door
- **Deps:** T-04, T-08, T-13
- **Est:** 1h
- **Artifact:** SKILL.md invoked by `/ai-native-migration`. Frontmatter (`name`, `description`, triggers). Body describes the seven-step flow from spec §6, in the imperative — telling the reading agent exactly which script to call, which workflow to invoke, and where to write the plan file. Includes explicit human-in-the-loop language matching spec §9 (no writes except the plan file; `--apply` is per-template interactive; security-sensitive templates always interactive).
- **Verify:** Invoking `/ai-native-migration <path>` reads this file and follows the flow. If the first agentic step (workflow) is not yet implemented (T-19+), SKILL.md gracefully reports "workflow not yet available" without proceeding.

### T-19 — Workflow scaffolding
- **Deps:** T-05, T-11
- **Est:** 1h
- **Artifact:** `skill/workflows/ai-native-audit.js` — `meta` block with all phases pre-named, arg parsing (target path, `--depth`, `--judges`, `--verify`, `--critic`), invocation of `ai-native-verify --format=json` at the top, and JSON schema constants for judge output, verifier output, and synthesizer output.
- **Verify:** Workflow runs end-to-end with 0 judges enabled; produces a plan file containing only the deterministic scorecard (no agentic findings). Confirms plumbing.

### T-20 — Judges A01–A04
- **Deps:** T-05, T-19
- **Est:** 2h
- **Artifact:** Four `agent()` calls in the workflow implementing:
  - A01 AGENTS.md quality judge
  - A02 AGENTS.md governance judge
  - A03 settings.json enforcement judge (cross-references AGENTS.md governance § against settings.json rules)
  - A04 Test AI-legibility judge (samples up to 5 tests per layer)
  - Each judge sources its scoring rubric from `references/judging-rubrics.md` (T-05) — no inline prompts in the workflow.
- **Verify:** Running standard-depth workflow against `tests/fixtures/perfect/` produces four judge outputs matching the schema. Judges cite the file/line evidence they scored on. Running against `tests/fixtures/partial/` produces findings with score < 3 that name specific gaps.

### T-21 — Judges A05–A07
- **Deps:** T-20
- **Est:** 1.5h
- **Artifact:**
  - A05 ARCHITECTURE.md accuracy judge (drift check against actual directory tree)
  - A06 Docs coverage judge (cross-references docs claims against deterministic scorecard from T-11)
  - A07 Coverage / mutation-testing signal judge
- **Verify:** Same as T-20.

### T-22 — Judge A08 (stack conventions with context7)
- **Deps:** T-07, T-21
- **Est:** 1.5h
- **Artifact:** A08 with the two-branch behavior from spec §11:
  - If `context7` MCP available in session → query `mcp__context7__query-docs` with `{stack, framework, versions}` from T-07 and evaluate target against live guidance
  - Else → fall back to `references/stack-generic.md` (T-06), mark A08 as `degraded` in output
- **Verify:** In a session with context7 available, running against a Java-Spring synthetic fixture (`tests/fixtures/stacks/java-spring/`) produces Spring-Boot-flavored findings; running against a Node-Next fixture (`tests/fixtures/stacks/node-next/`) produces Next.js-flavored findings. Simulate context7 unavailable → falls back cleanly, output marked degraded.

### T-23 — Adversarial verify pattern
- **Deps:** T-22
- **Est:** 1h
- **Artifact:** After each judge produces findings, spawn N skeptic agents per finding (N controlled by `--verify` flag). Prompt refutes-by-default. Plain-code majority vote counter drops findings whose majority is `refuted: true`. Standard depth = 1 verifier; thorough = 3.
- **Verify:** Injected fake plausible-but-wrong finding → adversarial verify drops it (all 3 verifiers refute). Injected real finding → survives.

### T-24 — Completeness critic (thorough mode)
- **Deps:** T-23
- **Est:** 1h
- **Artifact:** Final agent in thorough mode that reads aggregated findings and produces a gap list (unjudged criteria, unverified claims, unread sources). Gaps drive an additional audit round; capped at 2 rounds total. Empty gap list → exit loop.
- **Verify:** Deliberately disable judge A02 → thorough run's first critic pass flags "governance judge not run"; second pass converges.

### T-25 — Synthesizer + plan file writer
- **Deps:** T-11, T-23
- **Est:** 1.5h
- **Artifact:** Final synthesis agent merges deterministic scorecard + verified agentic findings into the plan file structure from spec §8. Writes to `<target>/docs/plans/ai-native-migration-<yyyy-mm-dd>.md`. Every recommendation cites its rubric section (e.g., "§4.1 D06" or "§4.2 A04"). Explicit `## Confidence` section names what could not be judged.
- **Verify:** Plan file conforms to §8 structure; every recommendation has a rubric citation; regex spot-check confirms no un-cited claims.

### T-26 — Depth flag routing
- **Deps:** T-24, T-25
- **Est:** 45m
- **Artifact:** Wire `--depth={light|standard|thorough|custom}` and `--judges=A01,A04` / `--verify=N` / `--critic=on|off` overrides into workflow-level control flow per spec §6 step 4.
- **Verify:** `--depth=light` runs 3 judges, no verify, no critic. `--depth=thorough` runs all 8 judges, 3-vote verify, critic loop. `--depth=custom --judges=A01 --verify=2` runs only A01 with 2-vote verify.

---

## Phase 5 — Bootstrap + install

### T-27 — `bootstrap.sh` — interactive per-template application
- **Deps:** T-13, T-14, T-15, T-16, T-17
- **Est:** 1.5h
- **Artifact:** `skill/scripts/bootstrap.sh` per spec §6 step 7 and §9 guarantees:
  - Accepts `--template=<name>` OR walks all templates whose corresponding check failed in the last audit
  - For each template: renders placeholders, shows diff vs current target state, prompts `apply / skip / edit-then-apply`
  - `edit-then-apply` opens `$EDITOR` on a temp copy, then writes
  - Writes files unstaged into target repo
  - **Always-interactive templates** (`.claude/settings.json`, `.github/workflows/**`, `.mcp.json`) — no flag can override this
  - Never writes in a batch; per-file confirmation required
- **Verify:** Dry-run against `tests/fixtures/empty/` (which lacks all baseline files) → prompts to apply each template; user says `skip` → nothing written. User says `apply` → file appears unstaged.
- **Human-decision:** every template application is a human decision by design.

### T-28 — `install.sh`
- **Deps:** T-18, T-27
- **Est:** 45m
- **Artifact:** Root-level `install.sh`. Verifies bash + jq + git present. Symlinks `skill/` contents into `~/.claude/skills/ai-native-migration/`. Idempotent — re-running updates the symlink. Prints post-install verification (`/ai-native-migration --help` should now be discoverable).
- **Verify:** Fresh clone + `./install.sh` → `/ai-native-migration` is invokable in a new Claude Code session.

---

## Phase 6 — Dogfood + acceptance

### T-29 — Dogfood pass — kit audits itself
- **Deps:** T-28
- **Est:** 1h + remediation
- **Artifact:** Run `/ai-native-migration ~/dev/ai-native-migration-kit --depth=thorough` against the kit's own repo. Address every finding until:
  - All 18 deterministic checks pass or are `n/a` with justification
  - Judges A01–A07 score ≥ 2/3 on the kit's AGENTS.md, docs, and code
  - Zero critical gaps in "explicit over implicit"
  - Completeness critic returns empty gap list on first pass
- **Verify:** Plan file for the kit is short and mostly n/a. Spec §14 acceptance criteria satisfied.
- **Human-decision:** any finding the kit surfaces that is not worth acting on is documented in `docs/plans/dogfood-decisions.md` with reasoning.

### T-30 — End-to-end verification against a realistic fixture
- **Deps:** T-29
- **Est:** 1h (fixture authoring included)
- **Artifact:** A realistic, kit-owned fixture under `tests/fixtures/realistic/` — a small but plausible project (any stack; author's choice) with a deliberate mix of AI-native strengths and gaps (e.g., has AGENTS.md but no governance section; has tests but they use `assertTrue` instead of readable-diff matchers; has CI but no pre-commit onboarding script). Run the kit against this fixture in `standard` depth. Review the produced plan file:
  - Does it correctly identify the deliberate gaps?
  - Are any findings surprising or wrong?
  - Do all citations resolve to sections of the kit's own rubric (§4.1 or §4.2)?
- Findings-of-findings feed back into judge tuning (direct edits — the deny-list has not yet landed). Fixture becomes a regression baseline for future judge changes: subsequent judge tunings must not silently change how they score this fixture without the reviewer's intent.
- **Verify:** Plan file matches the deliberate gap list encoded in `tests/fixtures/realistic/README.md`. No reference to any external repository appears in the output.

### T-31 — README polish + usage doc
- **Deps:** T-30
- **Est:** 30m
- **Artifact:** README covers: what the kit does, one-command install, one-command usage, the human-in-the-loop stance, links to spec + acceptance criteria. Small usage transcript (real output from the T-30 realistic-fixture run, sanitized).
- **Verify:** A reader arriving at the repo cold — no prior context about the kit — can install and run it from README alone.

### T-32 — Self-governance — freeze templates and references
- **Deps:** T-31
- **Est:** 20m
- **Artifact:** `.claude/settings.json` committed to the repo, deny-list covering `skill/templates/**` and `skill/references/**` for Edit/Write tools (per spec §12). This is the FINAL task in the build — the sources are stable, further edits should be deliberate and reviewable.
- **Verify:** Attempt to Edit a file under `skill/templates/` — Claude Code refuses. `AGENTS.md`'s governance section (already documenting the deny-list from T-01) is now backed by enforcement.
- **Notes:** Rationale for landing this last, not first, is in `01-questions-1-initial-design.md` Q-06. During the build (T-01 through T-31), templates and references are edited freely; the deny-list serves post-build stability, not authoring-time protection.

---

## Cumulative estimates

| Phase | Tasks | Est authoring time |
|---|---|---|
| 0 — Foundation | T-01 | ~30m |
| 1 — References | T-03 – T-06 | ~4h |
| 2 — Deterministic | T-07 – T-12 | ~6h |
| 3 — Templates | T-13 – T-17 | ~4h |
| 4 — Agentic | T-18 – T-26 | ~11h |
| 5 — Install | T-27 – T-28 | ~2h |
| 6 — Dogfood + freeze | T-29 – T-32 | ~2h + remediation |
| **Total** | 31 tasks (T-02 removed, T-32 added) | ~30h authoring |

## Dependency graph (compact)

```
T-01 → { T-03, T-04 } → T-05 → { T-06, T-07, T-08 → T-09 → T-10 → T-11 → T-12,
                                  T-13, T-14, T-15, T-16, T-17 }
                                → T-18 (needs T-04, T-08, T-13)
                                → T-19 (needs T-05, T-11)
                                     → T-20 → T-21 → T-22 → T-23 → T-24
                                                                ↓
                                                              T-25 → T-26
                                → T-27 (needs T-13..T-17)
                                → T-28 (needs T-18, T-27)
                                     → T-29 → T-30 → T-31 → T-32
```

## Critical path

**T-01 → T-04 → T-08 → T-09 → T-10 → T-11 → T-19 → T-20 → T-21 → T-22 → T-23 → T-25 → T-26 → T-28 → T-29 → T-30 → T-31 → T-32**

Phase 1 references (T-03, T-05, T-06), Phase 3 templates (T-13–T-17), and detect-stack (T-07) can run in parallel with the deterministic implementation once T-04 lands.

## Human-decision points (explicit)

Tasks that contain a decision only a human should make:

- **T-01** — license choice
- **T-27** — every template application, by design
- **T-29** — which dogfood findings are worth acting on vs. documented as accepted
- **T-30** — judge tuning based on realistic-fixture findings
- **T-32** — final review before freezing sources with the deny-list

Every other task is executable by an agent working under review.

## Deferred to v2

Explicitly not in scope for v1, captured here so future readers see the scoping:

- Machine-readable audit sidecar (Q-02 resolution: deferred until a concrete consumer exists)
- Additional stack conventions layers beyond `context7` + `stack-generic.md`
- Web UI / dashboard for compliance tracking across repos
- Any coupling to a specific curriculum, training program, or reference repository (permanently out of scope: the kit is repo-agnostic and general-purpose by design; the rubric in spec §4 is self-contained)
- Autonomous plan-to-PR conversion (violates human-in-the-loop; permanently deferred)

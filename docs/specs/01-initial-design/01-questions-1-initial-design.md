# Spec 01 — Questions Round 1

**Round:** 1
**Dates:** 2026-07-08 (Q-01 to Q-08 across spec review, T-01, T-04 sweep, and T-12)
**Reviewer:** T. Goulas
**Status:** all resolved; folded into spec + tasks

This file captures the questions raised during the first review of `01-spec-initial-design.md` (and its follow-up `01-tasks-initial-design.md`), the reasoning surfaced during each exchange, and the resolutions that were folded back into the design record. Preserved so future readers can see *why* the design landed where it did without re-deriving it.

Q-06 and Q-07 were raised after Q-01–Q-05 were closed, during T-01 landing (Q-06) and the tasks-file re-review (Q-07) — task-file review questions rather than spec review questions, but landing here keeps the whole trail in one place.

---

## Q-01 — Which language/stacks get first-class overlays in the initial release?

**Original phrasing (spec draft §11):** provisional set of Java/Spring, Node/Next, Python (Django/FastAPI). Anything else?

**Reviewer response:**
> "I feel that I should always detect the languages/frameworks and then dynamically pull the context7 to get the most recent versions."

**Reasoning surfaced during review:**

Hand-authored per-stack overlay files carry two liabilities:

1. **They rot.** Every framework major release invalidates parts of the overlay; the kit would need a maintenance cadence per stack.
2. **They pretend to a completeness they don't have.** Shipping overlays for four stacks silently signals to users of other stacks that the kit's stack coverage is limited.

Dynamic detection + live `context7` query at audit time avoids both liabilities. The kit stays stack-agnostic in its own source, and stack-specific rigor comes from the most current source available.

**Consequence named during review:** `context7` may be unavailable in some calling sessions (e.g., headless or no-MCP environments). Judge A08 needs a floor.

**Resolution:**

1. `skill/references/stack-overlays/` directory removed from the design.
2. §4.2 A08 renamed from "Stack overlay judge" to "Stack conventions judge" and its behavior rewritten:
   - Detect stack + framework versions at audit time (from `detect-stack.sh`).
   - Query `mcp__context7__query-docs` live for framework-specific AI-native guidance.
   - Fall back to `references/stack-generic.md` — a thin cross-stack floor — if `context7` is unavailable, and mark A08 as degraded in the plan file.
3. §5 directory layout: `stack-overlays/` replaced by single-file `stack-generic.md`.
4. §11 (Portability) rewritten to reflect the new model.

**Folded into spec:** §4.2 (A08), §5 (directory), §6 (step 2), §11 (Portability and stack agnosticism).

---

## Q-02 — Machine-readable audit sidecar (`<date>.audit.json`)

**Original phrasing (spec draft §11):** Should the deterministic scorecard also be persisted as a machine-readable artifact alongside the human-readable plan, so CI can pick it up?

**Reviewer response:**
> "what do I need this audit for?"

**Reasoning surfaced during review:**

The sidecar has no consumer in v1. It would be useful only if:
- The target repo's CI wanted to fail builds on compliance regression, or
- A dashboard/tool wanted to plot compliance over time across many repos.

Both are downstream ideas without a concrete need today. Meanwhile, `ai-native-verify` (see Q-03 resolution) already emits JSON on stdout for any caller that wants it, on demand — no need to persist a stale copy on disk.

**Resolution:**

Sidecar dropped from v1. The plan file (markdown) is the sole persisted artifact. If a concrete downstream consumer appears, adding a `--json-sidecar` flag to the workflow is a trivial follow-up.

**Folded into spec:** removed from §11 open questions; not added elsewhere (no artifact to describe).

---

## Q-03 — `/ai-native-verify` companion command

**Original phrasing (spec draft §11):** Should the kit ship with an `/ai-native-verify` command that re-runs only the deterministic audit for use in CI?

**Reviewer response:**
> "what does this command is used for? is it a hook for PR creation?"
>
> (after clarification) "Yes — ship as reusable script"

**Reasoning surfaced during review:**

The question conflated two things: an on-demand full audit (LLM-heavy, expensive) and a fast deterministic re-check (bash, zero cost). Only the second is useful as a CI/pre-push guardrail.

The kit already needs to run the deterministic checks internally. Exposing them as a **standalone script with a documented exit-code contract** makes the deterministic layer reusable by the target repo itself, post-migration — turning a one-shot report into an enforced guardrail. This is exactly the "deterministic guardrails outperform prompt-only rules" pattern (rubric §4.1 D06, D13, D15), applied recursively to compliance itself.

Not a git hook per se — the kit doesn't install anything into the target repo's git config. But the target repo can wire the script into whatever hook / CI step / manual check it wants.

**Resolution:**

1. The deterministic audit ships as `skill/scripts/ai-native-verify` — pure bash, no Node/Python/Claude Code runtime dependency.
2. Contract: `ai-native-verify [--format=text|json] [--check=D01,...] <target-repo>`.
3. Exit codes: 0 = pass/n/a, 1 = at least one partial, 2 = at least one fail, 3 = preflight failure.
4. New §10 in the spec documents the contract and enumerates target-repo use cases (GH Actions step, pre-push hook via `.pre-commit-config.yaml`, manual sanity check).
5. §6 step 3 updated to say the workflow calls `ai-native-verify --format=json`, not an internal `audit.sh`.
6. §5 directory layout: `audit.sh` renamed to `ai-native-verify` and moved to a first-class position.

**Folded into spec:** new §10, §5, §6 step 3.

---

## Q-04 — Governance on the kit's own repo

**Original phrasing (spec draft §11):** Should the kit itself commit a `.claude/settings.json` blocking edits to `templates/**`?

**Reviewer response:**
> "this is for dictating the changes using AI within the kit repo?"
>
> (after clarification) "Deny-list in .claude/settings.json (Recommended)"

**Reasoning surfaced during review:**

The kit's `templates/` and `references/` directories are the source of truth for the kit's behavior. An agent working inside the kit's repo (helping refine templates, tune judge prompts) could silently rewrite them without human notice — templates are code masquerading as data.

The kit's whole premise is that deterministic guardrails outperform prompt-only rules. Applying that principle to the kit's own source is the ideologically consistent choice; any softer approach (warning hook, no protection) would undermine the message.

**Resolution:**

1. New §12 in spec: kit ships with committed `.claude/settings.json` that deny-lists Edit/Write on `skill/templates/**` and `skill/references/**`.
2. To modify any file in those trees, the engineer must lift the block in `settings.json` in the same PR — making intent explicit and reviewable.
3. Kit's own `AGENTS.md` will include matching guidance in its governance section so advisory and enforced layers agree.

**Folded into spec:** new §12 (Self-governance), removed from §11 open questions.

---

## Q-05 — Coupling to external distribution channels or reference repositories

**Original phrasing (spec draft §11):** Do we need a second install path for external curriculum / reference-repo users?

**Reviewer response:**
> "this project is completely independent from any curriculum or reference repo"

**Reasoning surfaced during review:**

The reviewer flagged that the spec had drifted toward describing the kit in terms of an external reference — treating some other project as "the blueprint" — when the kit is intended to be stand-alone and repo-agnostic. Any coupling to a specific curriculum, training program, or reference implementation weakens the kit's positioning as a general-purpose tool applicable to any repository.

The kit's rubric (spec §4) must be self-contained. Users install the kit the same way regardless of whether they arrived from a course, a blog post, or GitHub search: clone + `install.sh`. There is no "students' path" and no "external path" — there is one path.

**Resolution:**

Question deleted. Additionally, a follow-up sweep (see Q-07) removed all incidental references to any specific external repository or curriculum from the entire design record, so the coupling never re-emerges accidentally.

**Folded into spec:** removed from §11 open questions.

---

## Q-06 — When does the self-governance deny-list land?

**Original position (tasks draft):** T-02 landed the `.claude/settings.json` deny-list on `skill/templates/**` and `skill/references/**` in Phase 0, before any templates or references were authored. Rationale at the time: "protect the sources before they exist."

**Reviewer response:**
> "I feel like the project claude settings should be added at last after having finalized the repo."

**Reasoning surfaced during review:**

The Phase 0 placement was wrong for two reasons:

1. **Deny-lists on empty directories protect nothing.** There is no target to protect until authoring begins.
2. **During authoring, the block creates friction.** Every legitimate write to a template or reference during Phases 1 and 3 would require a lift-then-restore around the edit. Either that friction slows the build, or it trains everyone to reflexively bypass the guardrail — which defeats it. A guardrail that is routinely lifted stops being a guardrail.

The deny-list's real purpose is **post-authoring stability**: it becomes meaningful the moment the source of truth is stable and the next write is more likely to be a mistake than an intent. That's the end of the build, not the beginning.

Meanwhile, the *advisory* layer — the governance section in `AGENTS.md` documenting the intended deny-list — can and does ship in T-01, weeks before the enforced layer. This is the two-layer pattern captured in rubric §4.1 D03 and §4.2 A03: *advisory in AGENTS.md, enforced in settings.json*. The two layers do not need to land together.

**Placement decision — very last task, not "right before dogfood":**

- **T-29 (dogfood)** may surface edits to references (judge prompt tuning based on how the kit scores itself). Landing the deny-list before dogfood would pollute the dogfood signal with lift-restore friction.
- **T-30 (realistic-fixture e2e)** may also feed judge tuning changes into references.
- **T-31 (README polish)** touches only `README.md`, unrelated to templates or references.

So the deny-list going on as the very final act — "we're done, freeze the sources" — is the clean sequencing.

**Resolution:**

1. T-02 (Phase 0 self-governance) **removed** from the tasks file.
2. Phase 0 shrinks to just T-01.
3. Phase 1 references and Phase 3 templates now depend on T-01 (not T-02); the language around "authored under protection" reworded.
4. New **T-32** added at the end of Phase 6: commits `.claude/settings.json` with the deny-list, after T-31 (README polish) is complete.
5. Task-total count is preserved (31); T-02 removed, T-32 added.
6. Cumulative-estimates table updated (Phase 0 is now ~30m, not ~1h; Phase 6 is now "Dogfood + freeze"). Dependency graph and critical path updated to reflect the reshuffle.
7. AGENTS.md governance section (from T-01) is unchanged — it already documents the deny-list as the intended end-state. Spec §12 is unchanged — the design (deny-list exists, protects sources) is the same; only when it lands is different.

**Folded into spec:** no spec change needed — §12 already correctly describes the end-state.
**Folded into tasks:** T-02 deletion, T-32 addition, Phase 0/1/3/6 language, cumulative estimates, dependency graph, critical path, human-decision points list.

---

## Bonus decision — name of the standalone script

Raised during Q-03 resolution. Choices offered: `ai-native-verify`, `ai-native-audit`, `ai-native-check`.

**Reviewer response:**
> "ai-native-verify (Recommended)"

**Rationale:** `verify` reads as an action verb, fits well in CI YAML (`- run: ai-native-verify .`), and pairs naturally with the skill's `/ai-native-migration` command. No collision risk with other common tools named `check`.

**Folded into spec:** §10, §5, §6.

---

## Q-07 — Repo-agnostic design: strip all references to external repositories and curricula

**Original observation (reviewer):**
> "I don't want any references to the pet-clinic or any other repo! This is a repo agnostic and general purpose workflow."

**Context:**

Even after Q-05 removed the "distribution path for the training program" question, the design record still contained dozens of incidental references to specific external repositories and curricula: reference-implementation filepaths used as "blueprint" citations in the rubric, external repo names used as verification fixtures in task descriptions, curriculum lesson slugs used as source citations for design decisions. These are the residual coupling — they don't affect the kit's runtime behavior, but they compromise the design record's independence and set a bad precedent for future edits.

**Reasoning surfaced during review:**

An external example is legitimate authoring inspiration — it exists in the reviewer's mind while writing the rubric, and that's fine. But it does not belong in the *record* of a general-purpose tool, because:

1. **Verification fixtures must be portable.** Any task whose verify step names an external repo cannot be executed by anyone who doesn't have that repo. Fixtures the kit uses for its own tests must live inside the kit.
2. **Citations must trace to the kit's own rubric, not to external sources.** A user who runs the kit and gets a plan file with citations like "W1.D2.S1 §agents-md" cannot follow those links unless they have access to the specific curriculum that owns those slugs. The plan file's citations must resolve inside a single self-contained document — the rubric in spec §4.
3. **The kit's positioning is stand-alone.** Any implication that the kit is "the general-purpose version of X" concedes the framing that some *other* project is the primary artifact. The kit is the primary artifact.

**Resolution:**

Full sweep across the design record removed:

- All references to any specific external reference-implementation repository (both by name and by filepath).
- All references to any specific curriculum, training program, or course (both by name and by lesson slug).
- All uses of phrases like "training material", "the training teaches", "blueprint file", "lesson slug", "reference implementation" as citation sources.

Concrete changes in this sweep:

- **Spec §4.1 (deterministic rubric):** the "Blueprint reference" column renamed to "Example indicator" and every cell rewritten in terms of filenames/patterns only. No external filepaths remain.
- **Spec §4.2 (agentic judges):** every "per `<lesson-slug>`" reference stripped; the criteria stand on their own descriptive text.
- **Spec §6, §9, §12:** citations rewritten to reference the kit's own rubric sections (e.g., "rubric §4.1 D03") instead of external documents.
- **Spec §8 (plan file structure):** the sample "Source: `W1.D2.S1 §agents-md`" citation replaced with "Source: rubric §4.2 A01".
- **Tasks T-07, T-09, T-10, T-12, T-13, T-14, T-16, T-17, T-20, T-22, T-25, T-27:** verify sections rewritten to reference kit-owned synthetic fixtures under `tests/fixtures/{empty,perfect,partial,realistic,stacks/*}/` instead of external repositories.
- **T-30:** repurposed from "end-to-end verification against pet-clinic" to "end-to-end verification against a realistic fixture" — the fixture is kit-owned, author-of-the-kit's choice of stack, deliberately mixed strengths and gaps.
- **T-31 verify:** "A reader who has never seen the training program" → "A reader arriving at the repo cold — no prior context about the kit".
- **AGENTS.md, docs/DEVELOPMENT.md:** citations rewritten to reference the rubric.
- **Q-02, Q-03, Q-04, Q-05, Q-06 in this file:** any inline phrase like "the training teaches" or "training pattern" rewritten to cite the kit's rubric.

**Design invariant enshrined:**

Going forward, the "Deferred to v2" section of the tasks file names *"any coupling to a specific curriculum, training program, or reference repository"* as **permanently out of scope**, not merely v2. Any future PR that adds such a reference must lift this invariant explicitly in the same PR.

External *public standards* are still legitimate to cite — the [AGENTS.md open standard](https://agents.md/) at agents.md, Anthropic's Claude Code documentation, PIT / Stryker / mutmut project pages, the Pact contract-testing spec, etc. These are neutral public references, not proprietary curricula or private repositories.

**Folded into:** every file in the design record. This question is the record of that sweep.

---

## Q-08 — CI workflow file blocked by PAT scope

**Observed during:** T-12 (deterministic self-test harness).

**Context:**

The T-12 verify criterion in `01-tasks-initial-design.md` reads:
> "CI job wired for it under `.github/workflows/`."

The task deliverable includes a `.github/workflows/ci.yml` that invokes `bash tests/verify.test.sh` on push and PR. The file was authored, matches the T-12 acceptance criteria, and passes the harness locally. But pushing it via the `teogoulas` fine-grained PAT was rejected:

```
! [remote rejected] main -> main
(refusing to allow a Personal Access Token to create or update workflow
`.github/workflows/ci.yml` without `workflow` scope)
```

The REST content-create path (`PUT /repos/.../contents/.github/workflows/ci.yml`) returned the same 403 with the same reason. GitHub protects `.github/workflows/**` at the token level to prevent silent CI wiring — this is a security feature, not a bug.

**Resolution:**

1. The `ci.yml` file is preserved at `.github/workflows/ci.yml.pending` (untracked, not pushed) so it is not lost.
2. `.gitignore` gains an entry for `*.pending` so this pattern is reusable for any future scope-blocked artifact.
3. The user (repository owner) resolves this by one of two paths:
   - **(a) Preferred, permanent:** add the `workflow` (or fine-grained equivalent: *Actions → write*) scope to the `teogoulas` PAT via GitHub's PAT settings page, then rerun the T-12 commit path.
   - **(b) One-shot:** add the workflow file via the GitHub web UI ("Add file → Create new file" at `.github/workflows/ci.yml`, paste content from `.github/workflows/ci.yml.pending`).
4. Task T-12 is considered **feature-complete** — the harness (`tests/verify.test.sh`) is committed and functional. The CI wiring is an infrastructure blocker on user action, not a code gap.

**Invariant recorded:**

For any future workflow file the kit needs to ship (e.g., a lint job in Phase 4, a scheduled dogfood job in Phase 6), if the PAT still lacks `workflow` scope at that time, follow the same pattern: author, test locally, park as `*.pending`, document, hand off to the user.

**Folded into:** `.gitignore` (adds `*.pending`); task T-12 verify criterion (annotated as complete-modulo-scope in this file, no change to task text).

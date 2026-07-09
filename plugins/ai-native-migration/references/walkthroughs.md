# Walkthroughs — conversational bootstrap for mandatory artifacts

This file is the canonical script the reading agent follows during `/ai-native-migration:migrate --apply` (SKILL.md step 7) when a mandatory finding requires **project-specific content**, not just a rendered template.

Not every mandatory finding needs a walkthrough. `.editorconfig`, `.gitmessage`, `.coderabbit.yaml`, `.pre-commit-config.yaml`, `.devcontainer/*`, and the onboarding scripts are boilerplate — the templates render into a passing state without asking the human anything project-specific. Use `bootstrap.sh --template=<name> --check-after=<criterion>` for those.

The two artifacts below are different. Their templates ship with placeholders that only a human can fill in, and applying the template without those fills leaves the corresponding check in a `fail` state despite the file being present.

---

## Global rules for every walkthrough

Read these before starting any per-artifact script.

1. **Ask the questions in order.** Don't jump ahead. The human's answer to Q1 often shapes how you ask Q2.
2. **Show the draft, don't write it silently.** After enough questions to draft one section, paste the draft in the chat and ask "apply this?" — do not invoke Write before the human confirms.
3. **Iterate on each section, not the whole file.** A section-by-section rhythm keeps the review manageable. If the human wants to edit, edit; then re-show; then confirm.
4. **Verify after writing.** Immediately after the Write lands, run:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/ai-native-verify --check=<criterion> --format=json <target>
   ```
   Inspect the `results[]` entry for that criterion. If it's still `fail`, tell the human what's missing (from the `evidence` string) and loop.
5. **Never fabricate.** If the human doesn't answer a question or answers "I don't know," write a `TODO(name):` marker in the section rather than inventing content. Half-invented AGENTS.md content is worse than a TODO — one propagates false context, the other flags a task.
6. **Keep tone conversational, not procedural.** You're an editor collaborating with the human, not a form validator.

---

## Walkthrough 1 — AGENTS.md (fixes D01; raises A01, A02)

**Trigger:** D01 verdict is `fail` (missing canonical sections) OR the human accepts your offer to strengthen a `pass` file after seeing A01/A02 semantic gaps in the plan.

**Reference template:** `${CLAUDE_PLUGIN_ROOT}/templates/AGENTS.md.tmpl`. Read it first to see the section skeleton; do not render it and drop it as-is — that produces a file that passes D01 (structural section check) but reads as boilerplate to A01 (content quality).

**Step 1 — read the current state.**

If `<target>/AGENTS.md` exists, Read it. Identify which of the five canonical sections are present, which are missing, and which are stubs (heading present but body is a single placeholder line).

- **Missing everything:** you're doing a create. Skip to step 2.
- **File exists, some sections present:** you're doing an update. Loop over missing/stub sections only in steps 2–6; skip sections the human already wrote.
- **All five present:** D01 passes already. This walkthrough is only useful if A01/A02 flagged quality gaps — ask the human whether they want to work on those before proceeding.

**Step 2 — orient with three project-level questions.**

Ask (verbatim; wait for each answer):

> **Q1** (one sentence): What does this project do? Not what it is *made of* — what does it do for the user or for the system it plugs into?
>
> **Q2**: What's the primary stack? Language + framework + package manager. Answer with the tech-stack shorthand, not marketing text (e.g., "Java 21, Spring Boot 3.2, Maven" not "modern reactive microservices platform").
>
> **Q3**: What is the ONE gotcha you'd tell a new engineer joining this repo tomorrow? The thing they'd otherwise learn the hard way. This seeds the Things to Avoid section, which is the highest-value section and the most often skipped.

These three answers set the whole file's voice. Q1 → Project Overview. Q2 → Coding Standards + Architecture Notes. Q3 → Things to Avoid seed.

**Step 3 — draft the Project Overview section.**

Two or three sentences. Answer, in order:

- What the project does (from Q1).
- Its high-level shape (monolith / service / library / CLI / …) — infer from the stack detection if not obvious.
- Key technologies (from Q2).

Draft it, paste it, ask: *"How's this? Anything to adjust before I move on?"* Iterate. When the human accepts, hold the draft in mind — do not write the file yet.

**Step 4 — draft the Coding Standards section.**

Ask:

> **Q4**: Beyond what the linter enforces (D16), what are the coding rules a new contributor would need told explicitly? Test-naming convention, doc-comment expectations, forbidden patterns, style choices that surprised you when you inherited the code — that shape of thing. Give me two to five.

If they list fewer than two, ask a follow-up: *"Any specific rule about how tests are named?"* — since test-naming is A04's #2 property and the highest-value rule per the training. Draft the section as a short bulleted list, tightly worded. Paste, iterate.

**Step 5 — draft the Key Commands section.**

You already have the stack from Q2. Ask:

> **Q5**: What's the day-one command flow for a new engineer? Setup command, dev-loop command, test command, lint command, deploy command. Skip any that don't apply.

Draft as a shell code block, grouped by intent (setup / build / test / lint / deploy). Include `ai-native-verify .` as the last line — that's the AI-native compliance check. Paste, iterate.

**Step 6 — draft the Architecture Notes section.**

Ask:

> **Q6**: What's the directory shape and what are the 2–4 most important modules a new engineer needs to know about? Path + one-line responsibility per module.

Draft the section with a directory tree (list the top-level layout the human names) plus one bullet per module. Keep this section under ~30 lines — deeper detail lives in `docs/ARCHITECTURE.md` (D08). Paste, iterate.

**Step 7 — draft the Things to Avoid section (highest-value; do this carefully).**

Start with Q3's answer as the first entry. Then ask:

> **Q7**: Give me the top three to five patterns you catch yourself telling new contributors NOT to do. Things that look reasonable but bite. Deprecated APIs, in-flight migrations, security-sensitive spots, known flaky areas, non-obvious performance traps.

If the human gives you fewer than three specific entries, don't fill the gap with generic advice — that's the failure mode this section is supposed to fix. Instead, ask the follow-up: *"Even one more concrete gotcha?"* If they still can't produce, write what they gave you plus a `TODO(team): add 2-3 more project-specific gotchas over the next sprint` line at the end.

Also add the universal don't-commit-.env rule if their `.gitignore` doesn't already handle it (Read `.gitignore` to check).

Paste, iterate.

**Step 8 — draft the Agent Governance sub-section (raises A02).**

This is the sub-section under Things to Avoid or a separate `## Agent Governance` heading. Ask three questions in one message:

> **Q8**: Three questions on governance:
> **(a) Do not modify** — list any files or directories agents should never edit. Generated code (`src/generated/`, protobuf output), migrations already applied to production, CI configs. Aim for 3–8 entries; concrete paths only.
> **(b) Always run before committing** — the local commands that must succeed before any commit lands. Test suite, linter, `ai-native-verify .`, pre-commit run.
> **(c) Escalate to a human** — situations where an agent should stop and hand off. Auth changes, migrations, API-contract changes, cross-cutting refactors over N files.

Draft the three lists. If the human is thin on (a), ask about generated code specifically — nearly every project has some. Paste, iterate.

**Step 9 — assemble, show the whole file, then Write.**

Concatenate the sections in canonical order (Project Overview → Coding Standards → Key Commands → Architecture Notes → Things to Avoid → Agent Governance). Paste the full assembled draft in a single message. Ask: *"Any final adjustments before I write this to `<target>/AGENTS.md`?"*

Only after they accept: invoke Write with the full content to `<target>/AGENTS.md`.

**Step 10 — verify.**

Run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/ai-native-verify --check=D01 --format=json <target>
```

Parse the JSON, find the D01 result. If `verdict=pass`, report the flip (`fail → pass`) and move on. If it's still `fail`, the evidence string names what's missing — usually a canonical section heading typo (e.g., "Code Standards" written instead of "Coding Standards"). Fix in place with Edit, re-verify, then move on.

**Step 11 — offer the CLAUDE.md symlink.**

If D02 is also `fail` or `partial`, offer to run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh --target=<target> --template=__claude_md_symlink --check-after=D02
```

(Or just execute the `ln -sf AGENTS.md CLAUDE.md` from the target directory yourself with Bash. It's a one-liner; a full bootstrap invocation is overkill.)

---

## Walkthrough 2 — `.claude/settings.json` (fixes D03; raises A03)

**Trigger:** D03 verdict is `fail` (no settings.json) OR the file exists but the human accepts your offer to strengthen governance after A03 flagged drift between AGENTS.md advisory rules and settings.json enforced rules.

**Reference template:** `${CLAUDE_PLUGIN_ROOT}/templates/.claude/settings.json.tmpl`. The `denyList` baseline is universal; the `hooks` audit hook is universal. The gaps are:

- **denyList entries** specific to the project's threat surface (destructive DDL if there's a database, `kubectl delete` if there's a Kubernetes deployment, etc.).
- **PreToolUse or Stop hooks** enforcing the human's AGENTS.md governance advisory rules.

**Step 1 — read the current state.**

If `<target>/.claude/settings.json` exists, Read it. Assess:

- Missing entirely → create.
- Present but `denyList` is empty or `hooks` object is empty → complete.
- Present and populated → the walkthrough is only useful if A03 flagged drift; ask the human whether they want to close it.

**Step 2 — start from the template.**

Read `${CLAUDE_PLUGIN_ROOT}/templates/.claude/settings.json.tmpl`. Show the human what the baseline denyList and audit hook look like. Ask:

> **Q1**: Baseline denyList looks reasonable? (`git push --force`, destructive git resets, `DROP TABLE`, `kubectl delete`, `terraform destroy`, curl-piped-to-shell). Anything you'd add or remove for this specific project?

Adjust the array per their answer.

**Step 3 — mirror AGENTS.md governance into settings.json (raises A03).**

If `<target>/AGENTS.md` has an Agent Governance section (from Walkthrough 1, or already present), Read it. Extract the do-not-modify list and always-run list. For each entry, ask:

> **Q2**: AGENTS.md says do-not-modify `<path>`. Should I add a matching `Edit(<path>)` deny pattern to settings.json's permissions.deny array? (recommended)
>
> **Q3**: AGENTS.md says always-run `<command>`. Should I add a PostToolUse or Stop hook that runs this before session end?

Draft the additions as JSON diffs to show the human. Advisory rules with no enforced counterpart are the specific gap A03 catches; closing them is why this walkthrough exists.

**Step 4 — show the full JSON, then Write.**

Assemble the final `settings.json` — baseline denyList (adjusted per Q1) + governance-mirroring denies (per Q2) + baseline audit hook + any governance-enforcing hooks (per Q3). Paste the full JSON in a single message. Ask: *"Any final adjustments before I write to `<target>/.claude/settings.json`?"*

Only after they accept: invoke Write. **Confirm to yourself the JSON is valid before writing** — a malformed settings.json will fail D03 outright (invalid JSON = fail regardless of content).

**Step 5 — verify D03 and A03 (if the workflow ran).**

Run:

```
${CLAUDE_PLUGIN_ROOT}/scripts/ai-native-verify --check=D03 --format=json <target>
```

D03 verdict should be `pass` if `denyList` and `hooks` are both populated. If A03 findings from the agentic layer were surfaced in step 5's plan file, note whether the entries you just added covered them.

**Step 6 — remind the human about `.claude/audit.log`.**

The audit hook writes to `.claude/audit.log`. If the target's `.gitignore` doesn't include this path, remind the human to add it — the log is session-scoped and shouldn't be committed. Offer to append the line with Edit.

---

## Walkthroughs for the middle-tier docs (D08 sub-cases)

**docs/ARCHITECTURE.md, docs/DEVELOPMENT.md, docs/TESTING.md** — the templates carry rich structure but every section is a placeholder. These get **simplified walkthroughs**: one or two orienting questions, then apply the template with the answers filled in.

The specific per-doc questions:

- **ARCHITECTURE.md** — reuse the answer to AGENTS.md Q6 (directory shape + key modules) plus:
  > **What's the highest-risk external dependency the system relies on at runtime, and what happens if it's down?**
  Add this as the External dependencies section.

- **DEVELOPMENT.md** — reuse Q2 (stack) and Q5 (day-one command flow). Ask one additional:
  > **What are the two gotchas a new engineer hits in the first week of local dev?**
  Add these to the "What NOT to do locally" section.

- **TESTING.md** — the template's AI-legibility content is universal; just one question:
  > **Which test framework(s) does the project use per layer (unit / integration / E2E)?**
  Adjust the three per-layer sections to name the concrete framework.

These use the full template render with content substitution; the human's answers slot into named placeholders. Not a full section-by-section conversation like AGENTS.md.

---

## Loop-and-verify pattern (universal)

Every walkthrough ends with the same three-step tail:

```
1. Show the assembled draft (or diff, if updating an existing file).
2. On confirmation → Write to the target path.
3. Immediately run: ai-native-verify --check=<criterion> --format=json <target>
   - verdict == pass → report flip, move on
   - verdict == partial → tell the human what needs fixing (from evidence), iterate
   - verdict == fail → same, but harder; the write clearly didn't cover the check
```

This tail is not optional. A migration is measured by verdicts flipping, not by files written.

---

## What's NOT in this file (and why)

- **Nice-to-have artifacts** (D14 AI review, D17 `.claude/commands/`). These are optional; the human decides whether to adopt them. Offer the template, apply if they accept, skip if not. No conversation needed.
- **Conditional artifacts** (D04 `.mcp.json`, A08 stack conventions). These only need attention when the target's context makes them apply. Follow the plan file's specific recommendation, don't force adoption.
- **`.editorconfig`, `.gitmessage`, `.coderabbit.yaml`, `.pre-commit-config.yaml`, `.devcontainer/*`, onboarding scripts.** Boilerplate. Use `bootstrap.sh --template=<name> --check-after=<criterion>` — no walkthrough needed.
- **`docs/PRECOMMIT.md`.** Mostly boilerplate reference material; the template renders into a passing state without asking the human anything. Simple template flow.

## Maintenance rules

1. If the rubric adds a new mandatory criterion that needs project-specific content, add a walkthrough here in the same PR.
2. Every question in a walkthrough must be verbatim. Rephrasing on the fly leads to inconsistent conversations across runs.
3. The verify-after-write step is not optional. If you find yourself tempted to skip it "because the template obviously works," don't — the whole point of Q-10's severity introduction was to enforce that verdicts flip, not that files land.
4. No coupling to external repos or curricula. Framework names remain neutral references.

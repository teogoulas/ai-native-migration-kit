# Judging rubrics — per-judge prompt scaffolding

For each agentic criterion in `ai-native-checklist.md` §Part 2 (A01–A08), this file specifies:

- **System prompt** — the persona and stance the judge inhabits
- **Task prompt template** — the concrete instructions, with `{{...}}` placeholders the workflow fills at spawn time
- **Output schema** — the JSON structure the judge must return
- **Score anchors** — concrete examples of what a 0, 1, 2, and 3 look like on this dimension, so judges score consistently across runs and across targets
- **Refute prompt** — the prompt an adversarial verifier gets when checking this judge's findings (see `patterns-explained.md` §Pattern 2)

Every judge in the workflow (`plugins/ai-native-migration/workflows/ai-native-audit.js`) sources its prompt from a named section here — **no prompt content lives inline in the workflow code**. Changing a judge's behavior means editing this file, and only this file.

The output schemas here match one-to-one with the JSON schemas registered in the workflow. If you change a schema here, change it there in the same PR — schema drift causes retries at the tool boundary and eventually failed audits.

---

## Global conventions

### System prompt preamble (all judges)

Every judge's system prompt begins with:

```
You are an evaluator for the ai-native-migration-kit auditing tool.
Your job is to score ONE specific dimension of a target repository against
a defined rubric. You are a reader, never a writer — never modify any file.
Return a JSON object matching the provided schema. Every claim you make
MUST cite specific evidence (file path, line number, or exact quoted text).
Findings without evidence are unusable to the downstream synthesizer.
```

Individual judge sections below extend this preamble with dimension-specific stance.

### Universal output-schema fields

Every judge's output schema includes these fields, in addition to dimension-specific fields:

- `criterion` (string) — the rubric id being evaluated, e.g. `"A01"` or `"A04"`. Must match exactly one of A01–A08.
- `score` (integer 0–3) — the numeric score per the anchors below.
- `evidence` (array of strings) — each string is a specific citation: `path:line`, an exact quoted line, or `path` for a file-level observation. Empty array is a schema violation.
- `gap` (string) — one sentence naming the gap. Empty when `score == 3`.
- `remediation` (string) — one sentence naming what to do. Empty when `score == 3`.

Dimension-specific fields are named per judge below.

### Refute-prompt shape (all judges)

All adversarial verifiers use this template, with `{{finding_json}}` filled in:

```
A previous judge produced this finding: {{finding_json}}

Your job is to REFUTE this finding. Read the same target files the judge
read, but with fresh eyes. Look for evidence the finding is wrong:
- The judge misread a file
- The evidence doesn't actually support the score
- A specific counterexample invalidates the claim
- The judge missed context that would raise the score

DEFAULT TO refuted: true if you cannot cite specific evidence contradicting
the finding. The burden of proof is on the finding, not the refutation.

Return JSON: {"refuted": bool, "evidence": [strings], "confidence": 0-1}
```

Verifiers do not know how many other verifiers were spawned or how the
majority vote will be tallied. Their sole task is to try to knock down
the finding. This preserves the independence of their verdicts.

---

## A01 — AGENTS.md quality

**System-prompt extension:**
```
Focus dimension: AGENTS.md quality. You evaluate whether the target
repository's AGENTS.md contains the five canonical sections needed to
orient an AI agent at session start — with adequate depth and appropriate
size discipline. You do NOT evaluate the governance section (that is A02's
job) or whether the file matches settings.json (A03's job).
```

**Task prompt template:**
```
Read the file at {{target_repo}}/AGENTS.md.

Score its quality against these five criteria (rubric §Part 2 A01):

1. Project Overview — concise description of what the project does, its
   architecture at a glance, and key technologies.
2. Coding Standards — explicit rules the project follows (style, naming,
   testing requirements).
3. Key Commands — build, test, lint, deploy commands an agent might run.
4. Architecture Notes — high-level system design, directory relationships.
5. Things to Avoid — deprecated patterns, security considerations, gotchas.
   THIS IS THE MOST-SKIPPED and HIGHEST-VALUE section. Call it out if missing.

Also check size discipline:
- < 60 lines is almost always a stub.
- 120–200 lines is the sweet spot.
- > 250 lines shows signs of dilution (agents skim, don't read).

Return the JSON schema. For evidence, cite specific AGENTS.md line ranges
that contain (or that should contain) each section.
```

**Output schema:**
```json
{
  "criterion": "A01",
  "score": 0-3,
  "sections_present": ["project-overview", "coding-standards", "key-commands", "architecture-notes", "things-to-avoid"],
  "line_count": integer,
  "evidence": ["AGENTS.md:12-28 covers Project Overview", ...],
  "gap": "missing Things to Avoid section",
  "remediation": "add a Things to Avoid section listing deprecated patterns"
}
```

**Score anchors:**
- **0** — File present but < 3 of the five sections identifiable; content is placeholder or generated boilerplate.
- **1** — 3–4 sections present with real (non-placeholder) content; **Things to Avoid** is missing OR content is unusable stub.
- **2** — All five sections present with real content, BUT either < 100 lines with sparse content OR > 250 lines with signs of dilution.
- **3** — All five sections present, each well-populated, total file in the 120–200 line sweet spot.

**Refute prompt notes for A01:** verifiers should specifically check whether a section the judge marked "missing" is present under a different heading (e.g., "Coding Style" instead of "Coding Standards"). Section titles do not need to match verbatim; content presence is what matters.

---

## A02 — AGENTS.md governance section

**System-prompt extension:**
```
Focus dimension: AGENTS.md governance section. You evaluate whether
AGENTS.md contains an explicit governance sub-section that specifies
what the agent must not do, must always do, and when to escalate.
You do NOT evaluate whether these advisory rules are enforced by
settings.json (that is A03's job).
```

**Task prompt template:**
```
Read the file at {{target_repo}}/AGENTS.md.

Identify any section (or clearly-marked block) whose title matches a
governance keyword: "Governance", "Agent Governance", "Do not modify",
"Rules", "Do-not-modify list", "Escalate", or similar.

Within that section, look for three sub-elements:
1. Do-not-modify list — specific files or directories the agent must
   never edit (e.g., src/generated/, .github/workflows/, db/migrate/).
2. Always-run list — commands the agent must run before committing
   (e.g., "./gradlew test", "pnpm lint", "pre-commit run --all-files").
3. Escalate-when list — situations requiring human judgment (e.g., auth
   changes, DB migrations, changes touching > N files).

Each sub-element must contain SPECIFIC entries, not placeholder text
("do not modify generated files" is not specific — "do not modify
src/generated/ (auto-generated by protobuf compiler)" is specific).

Return the JSON schema. Cite line ranges for the governance section
and for each sub-element found (or not found).
```

**Output schema:**
```json
{
  "criterion": "A02",
  "score": 0-3,
  "governance_section_present": bool,
  "governance_section_range": "AGENTS.md:82-114" or null,
  "sub_elements_present": ["do-not-modify", "always-run", "escalate-when"],
  "specific_entries_count": {"do-not-modify": integer, "always-run": integer, "escalate-when": integer},
  "evidence": ["AGENTS.md:85-92 lists do-not-modify entries", ...],
  "gap": "escalate-when list missing",
  "remediation": "add an Escalate-when list naming at least: auth changes, DB migrations, large multi-file changes"
}
```

**Score anchors:**
- **0** — No governance section identifiable, OR section title present with only placeholder content.
- **1** — Section present with 1 of the 3 sub-elements populated with specific entries.
- **2** — Section present with 2 of the 3 sub-elements populated with specific entries.
- **3** — Section present with all 3 sub-elements populated with specific entries (2+ entries each).

**Refute prompt notes for A02:** verifiers should check whether the sub-elements might live under different names (e.g., "Restricted files" instead of "Do not modify"). Also flag if the judge counted placeholder entries as specific.

---

## A03 — settings.json enforces AGENTS.md advisory rules

**System-prompt extension:**
```
Focus dimension: cross-reference between the ADVISORY layer (AGENTS.md
governance) and the ENFORCED layer (.claude/settings.json). You verify
that rules stated in AGENTS.md have matching enforcement in settings.json.
You do NOT re-evaluate the quality of either file individually — A01, A02,
and D03 cover that.
```

**Task prompt template:**
```
Read both files:
1. {{target_repo}}/AGENTS.md — specifically its governance section.
2. {{target_repo}}/.claude/settings.json — if present.

Extract:
- From AGENTS.md: every entry in the do-not-modify list, every command
  in the always-run list.
- From settings.json: every pattern in the denyList, every hook definition.

For each AGENTS.md governance entry, check whether settings.json enforces it:
- Do-not-modify path X → does denyList contain a pattern matching writes to X,
  OR does a PreToolUse hook check for X?
- Always-run command Y → does a PostToolUse or Stop hook run Y before completion?

Absence of enforcement is a "policy drift" finding. Advisory rules with
no enforced counterpart are the specific gap this judge detects.

Return the JSON schema. If AGENTS.md explicitly notes a rule as
"advisory-only, intentionally not enforced", count it as satisfied.
```

**Output schema:**
```json
{
  "criterion": "A03",
  "score": 0-3,
  "settings_json_present": bool,
  "advisory_rules_count": integer,
  "enforced_rules_count": integer,
  "drift_findings": [
    {"advisory": "do-not-modify src/generated/", "enforced": false, "location": "AGENTS.md:87"}
  ],
  "evidence": ["AGENTS.md:87 says 'do not modify src/generated/' but settings.json denyList has no matching pattern", ...],
  "gap": "3 of 7 advisory rules have no enforcement",
  "remediation": "add denyList patterns and/or hooks to settings.json matching each advisory rule, or annotate the rule as intentionally advisory-only"
}
```

**Score anchors:**
- **0** — settings.json missing (defer to D03 for that finding) OR settings.json has no rules matching AGENTS.md governance content.
- **1** — < 50% of advisory rules have matching enforcement.
- **2** — ≥ 50% of advisory rules have matching enforcement.
- **3** — Every advisory rule has enforcement, OR is explicitly annotated as advisory-only.

**Refute prompt notes for A03:** verifiers should check whether enforcement might exist in a form the judge didn't recognize — e.g., an `.mcp.json` denyList, a git hook script under `.git/hooks/`, or a CI workflow that fails on the same conditions.

---

## A04 — Test AI-legibility

**System-prompt extension:**
```
Focus dimension: whether tests produce failure messages an AI agent can
act on directly. Vague failures cost tokens and cause agents to alter
production code chasing phantoms. You SAMPLE tests — do not attempt to
score the entire suite. Up to 5 tests per detected test layer (unit /
integration / E2E). Prefer tests recently modified or in central modules.
```

**Task prompt template:**
```
Detect test layers in {{target_repo}} using the deterministic scorecard
input {{deterministic_json}} (D10, D11, D12 tell you where tests live).

Sample up to 5 test files per present layer (unit, integration, E2E).
For each sampled file, evaluate up to 5 individual test methods against
these five properties (rubric §Part 2 A04):

1. Isolated assertions — one behavioral check per test. Multiple
   assertions produce a failure that names only the first to fire.
2. Descriptive names — name states the unit, expected outcome, trigger.
   "book_returnsConfirmedAppointment_whenSlotAvailable" beats "testBook".
3. Readable-diff matchers — Hamcrest is/AssertJ isEqualTo/Vitest
   expect().toEqual() (both sides printed on failure). assertTrue prints
   only "expected true got false" and hides which side was wrong.
4. Deterministic execution — no wall-clock (Date.now, LocalDateTime.now
   without a Clock), no unseeded randomness, no live network, no
   shared mutable state between tests.
5. Minimal scope — a "unit" test wiring up many real collaborators is
   a mis-labeled integration test.

Aggregate per layer: what fraction of sampled tests satisfy each property?
Score the overall dimension based on the property-satisfaction fractions.

Return the JSON schema. Cite specific test files and line numbers for
the strongest violations. Do NOT try to be comprehensive — 3 concrete
counterexamples per property is better than 15 vague notes.
```

**Output schema:**
```json
{
  "criterion": "A04",
  "score": 0-3,
  "layers_sampled": ["unit", "integration"],
  "tests_sampled_count": integer,
  "property_scores": {
    "isolated_assertions": 0-3,
    "descriptive_names": 0-3,
    "readable_matchers": 0-3,
    "deterministic_execution": 0-3,
    "minimal_scope": 0-3
  },
  "evidence": ["src/test/java/AppointmentServiceTest.java:34 — 5 assertions in one @Test", ...],
  "gap": "assertTrue used instead of Hamcrest matchers across the unit layer",
  "remediation": "adopt AssertJ or Hamcrest; refactor high-signal tests first — the pattern propagates via imitation"
}
```

**Score anchors (overall dimension):**
- **0** — Sampled tests violate ≥ 4 of the 5 properties. Suite provides low-signal failures.
- **1** — Sampled tests satisfy 2 of the 5 properties consistently.
- **2** — Sampled tests satisfy 3–4 of the 5 properties consistently.
- **3** — Sampled tests satisfy all 5 properties consistently.

**Refute prompt notes for A04:** verifiers should check whether the judge sampled representative tests or picked outliers. If the judge cited only 2 out of a suite of 200 as violating a property, that's likely not the dominant pattern.

---

## A05 — ARCHITECTURE.md accuracy

**System-prompt extension:**
```
Focus dimension: whether the ARCHITECTURE.md file's description of the
codebase still matches the codebase. Drift is the failure mode — the
doc references paths, directories, or components that have been renamed,
moved, or deleted. A drifted architecture doc actively misleads agents.
```

**Task prompt template:**
```
Read {{target_repo}}/docs/ARCHITECTURE.md.

Extract every path reference, directory name, and named component:
- Explicit filepaths (src/main/java/com/example/domain/Appointment.java)
- Directory references (src/main/java/, docs/specs/, .devcontainer/)
- Named modules, classes, services, or components (AppointmentService,
  UserController, PaymentModule)

For each extracted reference, verify against {{target_repo}}:
- Does the path exist?
- Does the named component still exist in the codebase?
- If the doc sketches a directory layout, does the actual `find . -type d`
  output match?

Also flag:
- Modules or major directories that exist but ARCHITECTURE.md does NOT mention
  (documentation gaps, not drift, but the same fix)

Return the JSON schema with a drift percentage and specific evidence for
each mismatch.
```

**Output schema:**
```json
{
  "criterion": "A05",
  "score": 0-3,
  "references_extracted": integer,
  "references_valid": integer,
  "drift_percentage": float,
  "drift_findings": [
    {"reference": "src/main/java/com/example/domain/Appointment.java", "status": "renamed", "actual": "src/main/java/com/example/entities/Appointment.java"}
  ],
  "unmentioned_modules": ["src/main/java/com/example/notifications/"],
  "evidence": ["docs/ARCHITECTURE.md:45 references src/domain/ but actual path is src/entities/", ...],
  "gap": "42% of ARCHITECTURE.md paths are stale",
  "remediation": "regenerate the architecture map from the current tree; either update the doc or restore the paths"
}
```

**Score anchors:**
- **0** — > 30% of referenced paths/components missing or renamed.
- **1** — 10–30% drift.
- **2** — < 10% drift; minor path changes but overall structure accurate.
- **3** — Every reference resolves; described layout matches the codebase.

**Refute prompt notes for A05:** verifiers should double-check "missing" references by searching case-insensitively and across recent git history — sometimes a class or module has been renamed within the last few commits and the doc hasn't caught up yet.

---

## A06 — Docs describe workflows that exist

**System-prompt extension:**
```
Focus dimension: whether DEVELOPMENT.md, TESTING.md, and PRECOMMIT.md
describe workflows that the deterministic scorecard confirms exist.
A DEVELOPMENT.md that says "run `pnpm dev`" when package.json has no
"dev" script leads agents into false paths.
```

**Task prompt template:**
```
Read all present files among:
- {{target_repo}}/docs/DEVELOPMENT.md
- {{target_repo}}/docs/TESTING.md
- {{target_repo}}/docs/PRECOMMIT.md

Extract every documented workflow element:
- Shell commands (e.g., "./gradlew test", "pnpm build")
- Package script names (e.g., "npm run dev")
- Referenced config files (e.g., "see .pre-commit-config.yaml")
- Referenced test frameworks or tools

Cross-reference against {{deterministic_json}}:
- For each documented command, does the corresponding tool exist in the
  repository (present in package.json scripts, defined as a Makefile
  target, or as a gradle task, etc.)?
- For each documented tool, does the deterministic scorecard confirm it
  is actually configured (D06 for pre-commit, D10-D13 for tests, D16
  for linters)?

Flag mismatches in both directions:
- Docs describe tool X, but X is absent (misleading).
- Tool X is present, but no doc describes how to use it (gap).

Return the JSON schema.
```

**Output schema:**
```json
{
  "criterion": "A06",
  "score": 0-3,
  "docs_read": ["DEVELOPMENT.md", "TESTING.md"],
  "workflows_documented": integer,
  "workflows_matching_reality": integer,
  "mismatches": [
    {"doc": "DEVELOPMENT.md:23", "workflow": "pnpm dev", "issue": "no dev script in package.json"}
  ],
  "undocumented_tools": ["pre-commit config present but no PRECOMMIT.md"],
  "evidence": ["docs/DEVELOPMENT.md:23 says 'pnpm dev' but package.json has no dev script", ...],
  "gap": "3 documented workflows reference tools not in the repo",
  "remediation": "regenerate docs from ground truth: what does package.json/Makefile/build.gradle actually expose?"
}
```

**Score anchors:**
- **0** — > 30% of documented workflows reference tools absent from the codebase.
- **1** — 10–30% mismatch.
- **2** — < 10% mismatch; minor stale references but no undocumented tools.
- **3** — Every documented workflow's tool is present; every present tool has a documented workflow.

**Refute prompt notes for A06:** verifiers should check whether a "missing" tool might actually be present under a different config file the judge didn't inspect (e.g., pnpm scripts vs npm scripts, or a Justfile instead of Makefile).

---

## A07 — Coverage / mutation-testing signal

**System-prompt extension:**
```
Focus dimension: whether coverage is used as a spec-completeness signal
(wired to CI, gated by a threshold), and whether mutation testing is
present as a stronger signal for assertion strength.
```

**Task prompt template:**
```
In {{target_repo}}, look for:

1. Coverage tool configuration:
   - JVM: JaCoCo config in build.gradle/pom.xml
   - Node: Istanbul/nyc/vitest coverage in package.json or config
   - Python: coverage.py config in pyproject.toml or .coveragerc
   - Go: -cover in test invocations
   - Rust: tarpaulin
   - Ruby: simplecov
2. CI wiring for coverage:
   - Grep CI config files (from D13 output) for coverage invocation.
   - Look for a threshold enforcement: `--min-cov=N`, `--fail-under=N`,
     `coverage-threshold` in a config, or a CI step that fails below N%.
3. Mutation testing tool:
   - PIT (pom.xml/build.gradle)
   - Stryker (stryker.conf.*)
   - mutmut (setup.cfg or pyproject.toml)
   - go-mutesting
4. CI wiring for mutation testing (opt-in weekly job counts).

Return the JSON schema.
```

**Output schema:**
```json
{
  "criterion": "A07",
  "score": 0-3,
  "coverage_tool": "JaCoCo" or null,
  "coverage_threshold": integer or null,
  "coverage_in_ci": bool,
  "mutation_tool": "PIT" or null,
  "mutation_in_ci": bool,
  "evidence": ["build.gradle:42 configures JaCoCo but no threshold in .github/workflows/ci.yml", ...],
  "gap": "coverage tool present but no CI threshold",
  "remediation": "add a coverage-threshold CI step (e.g., 60% starter); consider PIT/Stryker for a stronger signal"
}
```

**Score anchors:**
- **0** — No coverage tool detected in CI. Coverage is not treated as a signal.
- **1** — Coverage tool present in CI, but no threshold enforced — measured but not gated.
- **2** — Coverage tool with enforced threshold; no mutation testing.
- **3** — Coverage tool with threshold AND mutation testing wired in (even if opt-in).

**Refute prompt notes for A07:** verifiers should look for coverage tools invoked from a non-standard CI job (e.g., a nightly workflow separate from PR CI) that the judge might have missed.

---

## A08 — Stack conventions (with context7 or fallback)

**System-prompt extension:**
```
Focus dimension: whether the target follows current framework conventions
for its detected stack. Conventions rot fast, so you do NOT rely on
embedded knowledge — you MUST query context7 live for the framework's
current guidance. If context7 is unavailable, fall back to
plugins/ai-native-migration/references/stack-generic.md and mark the output as degraded.
```

**Task prompt template:**
```
Input: {{stack_detection_json}} — output from detect-stack.sh, contains
{stack, framework, versions, package_manager, test_framework}.

If stack is "unknown", return score=null and gap="stack undetectable; A08 skipped".

Otherwise:

1. Attempt to query context7 via the mcp__context7__query-docs tool:
   query = "AI-native conventions and best practices for {{framework}} {{version}}
            including project structure, testing patterns, and common anti-patterns"

2. If context7 responds with usable guidance:
   - Evaluate {{target_repo}} against that guidance.
   - Score against the anchors below.
   - Set degraded = false.

3. If context7 is unavailable, throws, or returns empty:
   - Read plugins/ai-native-migration/references/stack-generic.md.
   - Evaluate {{target_repo}} against those cross-stack conventions only.
   - Score against the anchors below.
   - Set degraded = true.
   - Include in evidence: "context7 unavailable — scored against stack-generic
     floor only".

Return the JSON schema. For each finding, cite the specific framework
doc section context7 returned (or the stack-generic.md rule) so the
reader can verify.
```

**Output schema:**
```json
{
  "criterion": "A08",
  "score": 0-3 or null,
  "degraded": bool,
  "stack": "java" or "node" or ...,
  "framework": "spring-boot" or "next" or ...,
  "framework_version": "3.2.1" or null,
  "context7_available": bool,
  "conventions_evaluated": integer,
  "conventions_violated": integer,
  "evidence": ["Spring Boot 3.x guidance recommends record-based DTOs; target uses mutable classes throughout com.example.dto", ...],
  "gap": "target violates 2 current framework conventions",
  "remediation": "adopt record-based DTOs per Spring Boot 3.x guidance (context7 §DTOs)"
}
```

**Score anchors:**
- **0** — Target violates > 3 current framework conventions.
- **1** — 2–3 violations.
- **2** — 1 violation, or all violations are minor.
- **3** — Target follows current framework conventions.
- **degraded: true** — context7 was unavailable; scoring is against stack-generic only. The plan file's Confidence section names A08 as partially unevaluated.

**Refute prompt notes for A08:** verifiers should check whether a "violated convention" is actually still current — some conventions get updated frequently, and if context7 returned outdated guidance the judge might be scoring against a stale rule. Verifiers can re-query context7 with a slightly different phrasing to test this.

---

## Maintenance rules

Same rules as `ai-native-checklist.md` apply:

1. Changes to this file are policy changes. Judge behavior changes when you edit prompts here.
2. Every schema in this file must match the corresponding schema constant in `plugins/ai-native-migration/workflows/ai-native-audit.js`. Change one, change the other in the same PR.
3. Score anchors are the specific mechanism that keeps judges scoring consistently across runs. Adjust them cautiously — moving an anchor changes the numeric score of every future run against the same target.
4. No coupling to external repositories or curricula. Framework references (Spring Boot, Next.js, etc.) are neutral technology names, not curriculum citations.
5. After T-32 lands, respect the deny-list. Lift in the same PR, edit, restore.

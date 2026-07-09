# AI-native checklist — canonical rubric

The single source of truth for what the kit measures. Consumed by two callers:

- **`ai-native-verify`** (bash) reads the D-criteria only. Each `D` in this file corresponds to one deterministic check in the script. If a D-criterion is added, removed, or renamed here, the script must change in the same PR.
- **Workflow synthesizer** (`plugins/ai-native-migration/workflows/ai-native-audit.js`) reads both sections. Judges cite the `A` criterion they scored against; the synthesizer cites the `D` or `A` id in the plan file.

No downstream code embeds its own copy of the criteria. Drift between this file and the code is a bug.

Every criterion is anchored to one of four through-lines:

- **Explicit over implicit** — implicit knowledge in a human's head becomes explicit in a file an agent can read.
- **Verification at every level** — deterministic guardrails that catch regressions without depending on anyone's attention.
- **Structured artifacts** — stable, load-on-demand context anchors that let an agent skim without exhausting its window.
- **Stable context anchors** — reproducible environment and configuration so context is identical across sessions and machines.

Format is deliberate: one section per criterion, all fields required, no free-form prose. Judges and the deterministic script both need to parse this file mechanically.

---

## Part 1 — Deterministic criteria (D01–D18)

Structural facts about the target repository. Each check resolves to exactly one of `{pass, partial, fail, n/a}`. No LLM required; every check must be implementable in bash with standard tools (`test`, `readlink`, `jq`, `grep`, `find`).

### D01 — `AGENTS.md` present and non-trivial

**Intent:** The target has a canonical context file for AI agents at the repo root, and it contains actual content rather than being an empty placeholder.

**Example indicator:**
- File `AGENTS.md` exists at repo root.
- Size > 0 bytes.
- Contains at least 3 top-level Markdown headings (`^#` or `^##`).

**Through-line:** Explicit over implicit.

**Pass:** file exists, non-empty, ≥ 3 top-level headings.
**Partial:** file exists and non-empty, but < 3 top-level headings (probably a stub).
**Fail:** file missing or empty.
**N/A:** never — every AI-native repo must have this.

**Remediation hint:** *"Create AGENTS.md at the repo root. See rubric §Part 2 A01 for the five canonical sections; use `plugins/ai-native-migration/templates/AGENTS.md.tmpl` as a starting point."*

---

### D02 — `CLAUDE.md` is a symlink to `AGENTS.md`

**Intent:** Claude Code reads `CLAUDE.md` natively. Symlinking it to `AGENTS.md` means the single source of truth stays in the vendor-neutral file, while Claude Code sees the same content — one file, two entry points.

**Example indicator:**
- `readlink CLAUDE.md` returns exactly `AGENTS.md`.

**Through-line:** Explicit over implicit.

**Pass:** `CLAUDE.md` exists and is a symbolic link resolving to `AGENTS.md`.
**Partial:** `CLAUDE.md` exists as a regular file (content may be identical or drifting — either way it's a duplicate that needs to be maintained separately).
**Fail:** `CLAUDE.md` missing.
**N/A:** target repo declares in AGENTS.md that Claude Code is explicitly not a supported client (rare; requires an explicit AGENTS.md declaration).

**Remediation hint:** *"From repo root: `rm -f CLAUDE.md && ln -s AGENTS.md CLAUDE.md`. Verify with `readlink CLAUDE.md`."*

---

### D03 — `.claude/settings.json` present with denyList and hooks

**Intent:** Policy-as-code lives in a project-scoped file that Claude Code loads automatically. Every developer who clones the repo gets the same denyList and audit hooks without manual configuration.

**Example indicator:**
- File `.claude/settings.json` exists.
- Parses as valid JSON.
- Contains a top-level `denyList` array with at least one entry.
- Contains a top-level `hooks` object with at least one hook definition.

**Through-line:** Explicit over implicit.

**Pass:** file valid JSON, `denyList` non-empty, `hooks` non-empty.
**Partial:** file exists and valid JSON, but only one of `denyList` / `hooks` is populated.
**Fail:** file missing OR file present but invalid JSON OR neither `denyList` nor `hooks` populated.
**N/A:** never — even in a Claude-Code-not-used repo, a comment-only settings.json documenting the choice is preferable to absence.

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/.claude/settings.json.tmpl` into `.claude/settings.json`. Baseline denyList should include destructive git and infra commands (`git push --force`, `kubectl delete`, `DROP TABLE`). Baseline hooks should include a PostToolUse audit hook writing to `.claude/audit.log`."*

---

### D04 — `.mcp.json` present when MCP servers are declared

**Intent:** MCP servers used by the team are declared in a committed config file so every developer gets the same tools available at session start.

**Example indicator:**
- File `.mcp.json` exists at repo root, OR
- AGENTS.md explicitly declares "no MCP servers used" (searchable phrase or dedicated section).

**Through-line:** Stable context anchors.

**Pass:** `.mcp.json` present and parses as valid JSON, OR AGENTS.md declares no MCP usage.
**Partial:** `.mcp.json` present but empty or invalid JSON.
**Fail:** `.mcp.json` missing AND AGENTS.md does not declare MCP status.
**N/A:** never — silence about MCP usage is itself a governance gap; either declare it or configure it.

**Remediation hint:** *"If the team uses MCP servers, copy `plugins/ai-native-migration/templates/.mcp.json.tmpl` and edit. If the team explicitly does not use MCP, add a paragraph to AGENTS.md's Project Overview section stating so."*

---

### D05 — `.devcontainer/` provides a reproducible environment

**Intent:** Agents and humans get the identical toolchain via a preconfigured container, eliminating environment drift.

**Example indicator:**
- Directory `.devcontainer/` exists.
- Contains `devcontainer.json`.
- Contains `Dockerfile` OR `devcontainer.json` references an image explicitly.

**Through-line:** Stable context anchors.

**Pass:** `.devcontainer/devcontainer.json` exists AND (Dockerfile exists OR devcontainer.json declares an image).
**Partial:** `.devcontainer/` exists but is missing either `devcontainer.json` or an image source.
**Fail:** `.devcontainer/` missing entirely.
**N/A:** target repo is a pure documentation repo with no build/runtime dependencies (declared in AGENTS.md).

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/.devcontainer/` into place. Adjust the Dockerfile base and installed tools to match the detected stack."*

---

### D06 — `.pre-commit-config.yaml` present

**Intent:** Local pre-commit hooks catch style, security, and formatting issues before commits leave the developer's machine.

**Example indicator:**
- File `.pre-commit-config.yaml` (or `.pre-commit-hooks.yaml`) exists.
- Parses as valid YAML.
- Contains a top-level `repos:` key.

**Through-line:** Verification at every level.

**Pass:** file valid YAML with non-empty `repos:` list.
**Partial:** file exists but `repos:` list is empty or the file is otherwise a stub.
**Fail:** file missing OR file is invalid YAML.
**N/A:** never — every repo benefits from at least trailing-whitespace and merge-conflict-marker hooks.

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/.pre-commit-config.yaml.tmpl`. Pair with D18 — the hooks are only active when the onboarding script runs `pre-commit install`."*

---

### D07 — `.editorconfig` present

**Intent:** Editor-level consistency (indent width, line endings, final newline) is codified so agents and humans can't accidentally introduce whitespace drift.

**Example indicator:**
- File `.editorconfig` exists at repo root.

**Through-line:** Explicit over implicit.

**Pass:** file exists at repo root.
**Partial:** file exists in a subdirectory only (missing the root sentinel needed for cross-tool discovery).
**Fail:** file missing.
**N/A:** never.

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/.editorconfig.tmpl` to repo root."*

---

### D08 — Core docs trio present (`ARCHITECTURE.md`, `DEVELOPMENT.md`, `TESTING.md`)

**Intent:** Three stable, load-on-demand context anchors so an agent can look up how the project is shaped, how to develop in it, and how to test it — without having to read all the source.

**Example indicator:**
- All three files present under `docs/`:
  - `docs/ARCHITECTURE.md`
  - `docs/DEVELOPMENT.md`
  - `docs/TESTING.md`

**Through-line:** Structured artifacts.

**Pass:** all three files present, each non-empty.
**Partial:** 1–2 of the three present.
**Fail:** 0 of the three present.
**N/A:** never.

**Remediation hint:** *"Copy the three templates from `plugins/ai-native-migration/templates/docs/`. Fill each with the target-repo-specific content — the templates prompt for what to include."*

---

### D09 — `docs/specs/` directory exists

**Intent:** SDD artifacts (specs, task breakdowns, questions files) have a canonical home. Presence of the directory signals the team has adopted spec-driven development, even if only a handful of specs exist.

**Example indicator:**
- Directory `docs/specs/` exists (need not contain files).

**Through-line:** Structured artifacts.

**Pass:** `docs/specs/` is a directory.
**Partial:** `docs/plans/` exists (implies SDD-adjacent workflow) but no `docs/specs/`.
**Fail:** neither exists.
**N/A:** never.

**Remediation hint:** *"`mkdir -p docs/specs/` and add a `docs/specs/README.md` explaining the naming convention (`NN-slug/NN-spec-slug.md`, `NN-tasks-slug.md`, `NN-questions-N-slug.md`)."*

---

### D10 — Unit test folder(s) exist

**Intent:** Unit tests provide the fastest feedback loop for AI-generated code. Their existence is the minimum bar for verification-at-every-level.

**Example indicator:**
- At least one folder matching the target's stack convention:
  - Java: `src/test/java/`
  - JS/TS: `test/`, `tests/`, `__tests__/`, or files matching `*.test.{js,ts,jsx,tsx}`
  - Python: `tests/`, `test/`, or `test_*.py` files under a package
  - Go: `*_test.go` files alongside source
  - Rust: `#[cfg(test)]` blocks or `tests/` directory
  - Ruby: `spec/` or `test/`
  - Generic fallback: any folder named `unit/` under `test/` or `tests/`

**Through-line:** Verification at every level.

**Pass:** at least one convention-matching folder or file pattern found.
**Partial:** stack detected but only test scaffolding (config files) found, no actual test files.
**Fail:** no test structure detected.
**N/A:** target repo is documentation-only (declared in AGENTS.md).

**Remediation hint:** *"Add stack-appropriate unit test scaffolding. See `docs/TESTING.md` template for the AI-legibility properties tests should have (isolated assertions, deterministic execution, readable-diff matchers)."*

---

### D11 — Integration test folder(s) exist

**Intent:** Integration tests catch wiring issues that unit tests can't. Their presence signals the team has thought beyond isolated units.

**Example indicator:**
- Folder or file pattern matching `**/integration/**`, OR
- Test tags or naming conventions indicating integration (e.g., `@IntegrationTest` in Java, `*.integration.test.ts` in Node, `pytest.mark.integration` in Python).

**Through-line:** Verification at every level.

**Pass:** at least one folder or tagged test file matches.
**Partial:** convention exists but no actual integration test files (empty folder).
**Fail:** no integration test structure detected.
**N/A:** target is a pure library with no external integrations declared.

**Remediation hint:** *"Create `<test-root>/integration/` (or equivalent stack convention) and add one representative integration test. The point is the discipline of separating scope, not comprehensive coverage from day one."*

---

### D12 — E2E test folder exists

**Intent:** End-to-end tests verify user-facing behavior and generate proof artifacts (screenshots, traces) that agents can inspect after runs. Configured presence is enough — the point is the harness exists.

**Example indicator:**
- Folder `e2e-tests/`, `e2e/`, or `tests/e2e/` exists, OR
- Config file present: `playwright.config.{ts,js,mjs}`, `cypress.config.{ts,js}`, `wdio.conf.{ts,js}`, `.geb-config.groovy`, etc.

**Through-line:** Verification at every level.

**Pass:** folder OR config file present.
**Partial:** folder exists but config is missing.
**Fail:** no E2E harness detected.
**N/A:** target repo has no UI, API, or CLI to E2E-test (declared in AGENTS.md).

**Remediation hint:** *"Add stack-appropriate E2E scaffolding. Playwright is the default recommendation for web apps because of first-class screenshot and trace support."*

---

### D13 — CI configuration with build + test + lint gates

**Intent:** CI is the enforced verification tier. Every PR runs the same checks before merge; humans cannot bypass by forgetting.

**Example indicator:**
- Any of:
  - `.github/workflows/*.{yml,yaml}` with jobs containing keywords matching `build`, `test`, and `lint`.
  - `.gitlab-ci.yml`
  - `.circleci/config.yml`
  - `Jenkinsfile`
  - `bitbucket-pipelines.yml`
  - `azure-pipelines.yml`
  - `.buildkite/pipeline.yml`

**Through-line:** Verification at every level.

**Pass:** CI file present AND grep for the three keyword classes finds all three.
**Partial:** CI file present but only 1–2 of the three keyword classes detected.
**Fail:** no CI configuration detected.
**N/A:** never — every repo of any consequence needs CI.

**Remediation hint:** *"Add a CI workflow that runs, at minimum: (a) build (compile / install), (b) test (unit + integration), (c) lint (stack-specific linter from D16). See `plugins/ai-native-migration/templates/.github/workflows/ci.yml.tmpl` for a starting point."*

---

### D14 — AI review layer configured

**Intent:** Automated AI code review is a policy-independent second opinion on every PR, applying consistent standards regardless of reviewer availability.

**Example indicator:**
- Any of:
  - `.coderabbit.yaml` or `.coderabbit.yml`
  - `.github/copilot-review-config.yml` (or equivalent for the review-bot ecosystem in use)
  - A CI job explicitly named `ai-review`, `copilot-review`, `coderabbit`, or invoking a well-known AI reviewer

**Through-line:** Verification at every level.

**Pass:** at least one AI review configuration detected.
**Partial:** CI job exists but references an AI reviewer without a corresponding config file — probably in a starter state.
**Fail:** no AI review layer present.
**N/A:** target repo policy explicitly rejects automated review in AGENTS.md governance section (rare; must be justified).

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/.coderabbit.yaml.tmpl` and adjust. If your team uses a different AI reviewer, add its config with equivalent scope."*

---

### D15 — Conventional Commits enabled

**Intent:** Commit messages are machine-readable, enabling automated changelog generation, semantic-version bumps, and easier review by agents that scan history.

**Example indicator:**
- Any of:
  - `.gitmessage` file at repo root (referenced from `commit.template` in `.git/config` or `.gitconfig` snippets).
  - `commitlint.config.{js,ts,mjs,json}` file.
  - Pre-commit hook enforcing `conventional-commits` (grep the `.pre-commit-config.yaml` for `conventional-pre-commit` or similar).
  - `.claude/commands/commit.md` or `.claude/skills/conventional-commits/` present.
  - `commitizen` config in `package.json` or standalone.

**Through-line:** Explicit over implicit.

**Pass:** at least one convention-enforcement mechanism detected.
**Partial:** `.gitmessage` present but no enforcement (hook or slash command).
**Fail:** no mechanism detected.
**N/A:** never — Conventional Commits is nearly free to adopt.

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/.gitmessage.tmpl` to repo root, add `git config commit.template .gitmessage` to onboarding script (see D18), and add commitlint or the conventional-pre-commit hook to `.pre-commit-config.yaml`."*

---

### D16 — Stack-specific linter/style config present

**Intent:** Code style rules are enforced by the toolchain, not by human reviewers or agent prompts. The specific tool depends on stack.

**Example indicator:**
- File matching the detected stack:
  - Java: `checkstyle.xml`, `.checkstyle`, or `spotbugs-exclude.xml`
  - JS/TS: `eslint.config.{js,mjs,ts,cjs}`, `.eslintrc.{json,js,yml}`, `biome.json`
  - Python: `.ruff.toml`, `pyproject.toml` with `[tool.ruff]` or `[tool.black]` sections, `.pylintrc`
  - Go: `.golangci.{yml,yaml,toml}`
  - Rust: `.rustfmt.toml`, `rustfmt.toml`, `clippy.toml`
  - Ruby: `.rubocop.yml`
  - Shell: `.shellcheckrc`
  - Multi-stack: `.pre-commit-config.yaml` with stack-specific linter hooks

**Through-line:** Verification at every level.

**Pass:** stack detected AND at least one matching linter config file present.
**Partial:** stack detected, linter config present but empty/default (no project-specific rules).
**Fail:** stack detected but no matching linter config detected.
**N/A:** stack detection returned `unknown`.

**Remediation hint:** *"Add the standard linter for the detected stack. If the team dislikes the defaults, override in the config file — but do not skip the config file, or agents will invent inconsistent style rules."*

---

### D17 — `.claude/commands/` or `.claude/skills/` non-empty

**Intent:** The team has invested in reusable agent workflows (slash commands or skills) rather than relying on ad-hoc prompting each session.

**Example indicator:**
- Either `.claude/commands/` OR `.claude/skills/` exists and contains at least one file.

**Through-line:** Explicit over implicit.

**Pass:** either directory exists with ≥ 1 file inside.
**Partial:** directory exists but is empty (scaffolded but unused).
**Fail:** neither directory exists.
**N/A:** target repo declares in AGENTS.md governance that agent workflows live externally (e.g., in a shared skills repo).

**Remediation hint:** *"Add at least one project-scoped slash command or skill. Common starters: a `/commit` command backed by a conventional-commits skill, or a `/review` command for the team's PR-review checklist."*

---

### D18 — Onboarding automation activates committed guardrails

**Intent:** A committed pre-commit config (D06) or CI config (D13) is only enforced when the developer's local environment is actually set up. A one-command script (or Makefile target) makes activation reliable — otherwise, some developers will forget, and the guardrail becomes a suggestion.

**Example indicator:**
- Any of:
  - Executable script under `scripts/setup-*.sh` (e.g., `setup-precommit.sh`, `setup-dev.sh`) containing `pre-commit install` or stack-equivalent activation commands.
  - Makefile target named `setup`, `bootstrap`, `install-hooks`, or similar containing `pre-commit install`.
  - `package.json` `postinstall` script or npm-scripts entry that activates hooks.
  - Devcontainer `postCreateCommand` hook in `.devcontainer/devcontainer.json` running the activation.

**Through-line:** Verification at every level.

**Pass:** at least one activation mechanism found.
**Partial:** activation script exists but doesn't include `pre-commit install` (or stack equivalent) — hooks configured but never active.
**Fail:** no activation mechanism found. D06 hooks are effectively inert.
**N/A:** D06 is `fail` (no pre-commit config to activate). This check depends on D06; if D06 fails, D18 is `n/a` and the plan file surfaces D06 as the higher-priority fix.

**Remediation hint:** *"Copy `plugins/ai-native-migration/templates/scripts/setup-precommit.sh.tmpl` to `scripts/` and reference it from AGENTS.md's Key Commands section. Consider also adding it as a devcontainer `postCreateCommand` so containerized environments activate hooks automatically."*

---

## Part 2 — Agentic criteria (A01–A08)

Semantic judgments requiring an LLM subagent. Each `A` corresponds to one judge in the workflow. Judges must return a JSON object matching the schema in `plugins/ai-native-migration/references/judging-rubrics.md` — this file specifies *what* the judge evaluates; the rubrics file specifies *how* it scores.

### A01 — AGENTS.md quality

**Intent:** AGENTS.md exists (D01 confirmed that), but does it actually contain the content that makes it useful at session start?

**Evaluates:**
1. Presence of five canonical sections:
   - Project Overview
   - Coding Standards
   - Key Commands
   - Architecture Notes
   - **Things to Avoid** (the most-skipped, highest-value section — call it out when missing)
2. Section content quality (specificity, not just headings with placeholder text).
3. Size discipline: ~120–200 lines total. A 400-line AGENTS.md is almost always over-comprehensive and gets partially ignored. A < 60-line file is almost always a stub.

**Through-line:** Explicit over implicit.

**Score 0–3:**
- **0** — file present but < 3 of the five canonical sections identifiable; content is placeholder.
- **1** — 3–4 sections present with real content; missing Things-to-Avoid.
- **2** — all five sections present, real content, but either too short (< 100 lines with sparse content) or too long (> 250 lines with signs of dilution).
- **3** — all five sections present, well-populated, in the 120–200 line sweet spot.

**Remediation hint:** *"Compare against `plugins/ai-native-migration/templates/AGENTS.md.tmpl`. If missing Things-to-Avoid, this is almost certainly the highest-leverage single fix — this section is the most skipped and the most useful for constraining agent action."*

---

### A02 — AGENTS.md governance section

**Intent:** Beyond orientation (§A01), AGENTS.md must contain a governance sub-section that specifies what the agent should not do, what it must do, and when to escalate. This is the advisory layer of the two-layer governance pattern (advisory in AGENTS.md, enforced in settings.json — see D03 and A03).

**Evaluates:**
1. Presence of a section (or clearly-marked block) titled with a governance keyword (`Governance`, `Agent Governance`, `Do not modify`, `Rules`).
2. Three sub-elements:
   - **Do-not-modify list** — files/directories the agent must not edit (e.g., `src/generated/`, `db/migrate/`, `.github/workflows/`).
   - **Always-run list** — commands the agent must run before committing (e.g., `./gradlew test`, `pnpm lint`).
   - **Escalate-when list** — situations that require human judgment (e.g., "auth/authorization changes", "database migrations", "any change touching > 5 files").

**Through-line:** Explicit over implicit.

**Score 0–3:**
- **0** — no governance section identifiable.
- **1** — section present with 1 of the 3 sub-elements.
- **2** — section present with 2 of the 3 sub-elements.
- **3** — section present with all 3 sub-elements, each containing specific entries (not placeholder text).

**Remediation hint:** *"Add a `## Agent Governance` section to AGENTS.md with all three sub-elements. Concrete entries beat generic ones — 'do not modify src/generated/ (auto-generated by protobuf)' beats 'do not modify generated files'."*

---

### A03 — Settings.json enforces AGENTS.md's advisory rules

**Intent:** The two-layer governance pattern only works when the enforced layer (settings.json) actually implements the advisory layer (AGENTS.md governance section). Cross-reference the two.

**Evaluates:**
1. If AGENTS.md's do-not-modify list names path X, does `settings.json`'s denyList (or a hook) block writes to X?
2. If AGENTS.md's always-run list names command Y, is there a PostToolUse or Stop hook that runs Y before completion?
3. Absence in settings.json of a rule stated in AGENTS.md is a "policy drift" finding — the enforcement doesn't match the intent.

**Through-line:** Explicit over implicit.

**Score 0–3:**
- **0** — either settings.json is missing (see D03) or has no rules matching AGENTS.md.
- **1** — some AGENTS.md rules have matching enforcement (< 50%).
- **2** — most AGENTS.md rules have matching enforcement (≥ 50%).
- **3** — every advisory rule in AGENTS.md has a corresponding enforced rule in settings.json (or AGENTS.md notes explicitly that a rule is intentionally advisory-only).

**Remediation hint:** *"For every entry in AGENTS.md's do-not-modify list, add a matching denyList pattern or PreToolUse hook to settings.json. For every always-run command, add a PostToolUse or Stop hook."*

---

### A04 — Test AI-legibility

**Intent:** Tests are the primary feedback loop for AI-generated code. When a test fails, the failure message is what the agent uses to self-correct. Vague failures cost tokens and cause agents to alter production code chasing phantoms.

**Evaluates (samples up to 5 tests per detected test layer):**
1. **Isolated assertions** — one behavioral check per test method. A test with five assertions produces a failure that names only the first assertion that fired; the other four are invisible.
2. **Descriptive names** — `book_returnsConfirmedAppointment_whenSlotAvailable` beats `testBook2`. The name should state the unit, the expected outcome, and the trigger condition.
3. **Readable-diff matchers** — matchers that print both expected and actual on failure: Hamcrest `is`, AssertJ `isEqualTo`, Vitest `expect().toEqual`. `assertTrue(x.equals(y))` prints only "expected true, got false" and hides which side was wrong.
4. **Deterministic execution** — no wall-clock time, no unseeded randomness, no live network calls, no shared mutable state between tests. Injected `Clock`, seeded RNG, Testcontainers or `@Transactional` rollback for state.
5. **Minimal scope** — a "unit" test that wires up twelve real collaborators is a slow integration test misnamed. When it fails, the failure surface is the whole dependency graph.

**Through-line:** Verification at every level.

**Score 0–3:**
- **0** — sampled tests violate ≥ 4 of the 5 properties. Failure messages will be low-signal for any agent trying to self-correct.
- **1** — sampled tests satisfy 2 of the 5 properties.
- **2** — sampled tests satisfy 3–4 of the 5 properties.
- **3** — sampled tests satisfy all 5 properties consistently.

**Remediation hint:** *"Refactor sampled failing-property tests to match the AI-legibility properties. Even a handful of well-refactored tests raise the bar; agents extending tests tend to imitate the pattern they see."*

---

### A05 — ARCHITECTURE.md accuracy

**Intent:** ARCHITECTURE.md is a stable, load-on-demand context anchor — but only if it still matches the code. A drifted architecture doc actively misleads agents.

**Evaluates:**
1. Extract every filepath, directory reference, and component name mentioned in ARCHITECTURE.md.
2. Verify each still exists in the current codebase.
3. Sketch the actual top-level directory layout and compare to what ARCHITECTURE.md describes.
4. Flag drift: renamed components, deleted directories, and modules the doc doesn't mention.

**Through-line:** Structured artifacts.

**Score 0–3:**
- **0** — > 30% of referenced paths/components missing or renamed. Doc is actively misleading.
- **1** — 10–30% drift.
- **2** — < 10% drift; some minor path changes but overall structure is accurate.
- **3** — every referenced path exists and the described layout matches the codebase.

**Remediation hint:** *"Update ARCHITECTURE.md against the current directory tree. For each flagged discrepancy, either update the doc or fix the code path — either is fine, but they must match."*

---

### A06 — Docs describe workflows that exist

**Intent:** DEVELOPMENT.md, TESTING.md, and PRECOMMIT.md must describe workflows the deterministic scorecard actually confirms. A DEVELOPMENT.md that says "run `pnpm dev`" when `package.json` has no `dev` script leads agents into false paths.

**Evaluates:**
1. Extract every shell command, package script name, and workflow step from the docs.
2. Cross-reference against the deterministic scorecard: is the command's containing tool present (from D06, D10–D13, D16, D18)?
3. Flag docs that describe workflows for tools that are absent, or fail to describe workflows for tools that are present.

**Through-line:** Structured artifacts.

**Score 0–3:**
- **0** — > 30% of documented workflows reference tools absent from the codebase.
- **1** — 10–30% mismatch.
- **2** — < 10% mismatch; minor stale references but no undocumented tools.
- **3** — every documented workflow's tool is present, and every present tool has a documented workflow.

**Remediation hint:** *"Regenerate the docs from ground truth: what does `package.json`/`build.gradle`/`Makefile` actually expose? What does `pre-commit-config.yaml` actually enforce? Docs should mirror those, not aspiration."*

---

### A07 — Coverage / mutation-testing signal

**Intent:** Line coverage as a raw number is a weak signal, but its *presence in CI* signals the team treats coverage as a spec-completeness check. Mutation testing (PIT, Stryker, mutmut) is a much stronger signal — high coverage with weak assertions produces surviving mutants.

**Evaluates:**
1. Is a coverage tool wired to CI? (JaCoCo, Istanbul/nyc, coverage.py, tarpaulin, simplecov, etc.)
2. Is there a coverage threshold in CI config (fail below N%)?
3. Is a mutation-testing tool present and wired to CI, even if only opt-in?
4. Are surviving-mutant reports treated as findings (linked from CI output, discussed in PR review)?

**Through-line:** Verification at every level.

**Score 0–3:**
- **0** — no coverage tool detected in CI. Coverage is not treated as a signal.
- **1** — coverage tool present in CI, but no threshold enforced — coverage is measured but not gated.
- **2** — coverage tool with enforced threshold; no mutation testing.
- **3** — coverage tool with threshold AND mutation testing wired in (even if opt-in).

**Remediation hint:** *"Add the stack's standard coverage tool to CI with a modest threshold (60–70% is a reasonable starting point; higher without mutation testing rewards gaming). Add mutation testing next; a weekly PIT/Stryker run against changed files is enough to start."*

---

### A08 — Stack conventions

**Intent:** Beyond the general rubric, does the target follow current framework conventions for the detected stack? These conventions rot faster than the general rubric, so the kit does not embed them — it queries the `context7` MCP live at audit time for the framework's current guidance.

**Evaluates:**
1. Read `detect-stack.sh` output: `{stack, framework, versions}`.
2. Query `mcp__context7__query-docs` with the framework name and version for its current AI-native / testing / structural guidance.
3. Evaluate the target against that live guidance (typical structure, common anti-patterns, deprecated APIs, current recommended tools).

**Through-line:** all four (varies by stack).

**Fallback behavior:**
- If `context7` is unavailable in the calling session (headless environment, MCP not connected), fall back to `plugins/ai-native-migration/references/stack-generic.md` — a thin cross-stack floor covering conventions that hold across all stacks. In that case, judgment output is marked with `degraded: true` and the plan file's Confidence section names A08 as partially unevaluated.

**Score 0–3:**
- **0** — target violates > 3 current framework conventions.
- **1** — target violates 2–3 conventions.
- **2** — target violates 1 convention, or all violations are minor.
- **3** — target follows current framework conventions.
- **degraded** — context7 was unavailable; scoring done against `stack-generic.md` only. Emit `degraded: true` alongside the score.

**Remediation hint:** *"For each finding, cite the framework doc section from context7's response so the reader can verify. If context7 was unavailable, this judge only checked the generic floor — surface that in the Confidence section and recommend re-running with context7 available for a full stack judgment."*

---

## Maintenance rules

Changes to this file must:

1. Be reviewed as a policy change, not just a docs change. The rubric is what the kit *is* — changing a criterion changes the product.
2. Land in the same PR as the corresponding change to `ai-native-verify` (for D-criteria) or `workflows/ai-native-audit.js` (for A-criteria). Drift between rubric and code is a bug that will surface as unreachable checks or unbacked judge outputs.
3. Not couple to any specific external repository, curriculum, or training program. Example indicators are filenames, patterns, and public standards only. See spec §11 and questions file Q-07 for the invariant.
4. After T-32 lands, respect the deny-list in `.claude/settings.json`. Lift it in the same PR, make the change, restore it.

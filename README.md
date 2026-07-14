# ai-native-migration-kit

A Claude Code skill + workflow for auditing and migrating any repository toward **AI-native** status — a repo that is instrumented for an agent, not just decorated for one.

The kit combines a deterministic bash audit (18 structural checks, ~2 seconds, no LLM) with an adversarially-verified agentic audit (up to 8 semantic judges + N-vote skeptic verification), then synthesizes a human-reviewable migration plan. It **never converts findings into commits autonomously** — human-in-the-loop is a design guarantee, not a preference.

## What is "AI-native"?

Four through-lines characterize the pattern:

- **Explicit over implicit** — implicit knowledge in a human's head becomes explicit in a file an agent can read (`AGENTS.md`, `.editorconfig`, governance rules).
- **Verification at every level** — deterministic guardrails that catch regressions without depending on anyone's attention (pre-commit, CI, mutation testing).
- **Structured artifacts** — stable, load-on-demand context anchors so an agent can skim without exhausting its window (`docs/ARCHITECTURE.md`, `docs/specs/`).
- **Stable context anchors** — reproducible environment (`.devcontainer/`) and configuration (`.mcp.json`) so context is identical across sessions and machines.

The full rubric — 18 deterministic criteria + 8 semantic judges — lives in [`plugins/ai-native-migration/references/ai-native-checklist.md`](plugins/ai-native-migration/references/ai-native-checklist.md).

## Install

The kit ships as a Claude Code plugin. Install it from any Claude Code session:

```
/plugin marketplace add teogoulas/ai-native-migration-kit
/plugin install ai-native-migration@ai-native-migration-kit
```

Claude Code clones the repo into its plugin cache, wires up the skill (`/ai-native-migration:migrate`), and keeps it updated as new commits land. `/plugin marketplace update ai-native-migration-kit` pulls the latest.

To uninstall: `/plugin uninstall ai-native-migration@ai-native-migration-kit` (then optionally `/plugin marketplace remove ai-native-migration-kit`).

**Requirements** at runtime: `bash`, `git`, `jq`. `python3` recommended (a naive-grep fallback runs without it). `node` needed only for running the workflow tests locally.

### Local development

If you're hacking on the kit itself, load it without going through the marketplace:

```bash
git clone https://github.com/teogoulas/ai-native-migration-kit.git
claude --plugin-dir ./ai-native-migration-kit/plugins/ai-native-migration
```

The plugin appears in the current session; `/reload-plugins` picks up your edits.

## Usage

### Full audit (deterministic + agentic + plan file)

From any Claude Code session:

```
/ai-native-migration:migrate <path-to-target-repo>
```

Produces a Markdown plan at `<target>/docs/plans/ai-native-migration-<date>.md`. The default flow writes exactly that one file into the target — nothing else. Depth levels:

- `--depth=light` — 3 judges (A01 + A02 + A04), no verification, no critic. Fastest, noisiest.
- `--depth=standard` (default) — 5 judges (A01 + A02 + A04 + A05 + A06), single-vote adversarial verify.
- `--depth=thorough` — all 8 judges (A01–A08), 3-vote majority verify, completeness critic loop (up to 2 rounds).
- `--depth=custom --judges=A01,A04 --verify=2 --critic=on` — surgical.

See [The semantic judges (A01–A08)](#the-semantic-judges-a01a08) below for what each judge evaluates.

Add `--apply` to enter an interactive per-template bootstrap after the plan is written.

### Deterministic layer only (fast, no LLM, no Claude Code needed)

`ai-native-verify` is pure bash + jq — it doesn't need Claude Code to run. Two ways to use it from a target repo's own guardrails:

**A. Clone once, invoke by path:**

```bash
git clone https://github.com/teogoulas/ai-native-migration-kit.git ~/tools/ai-native-migration-kit
~/tools/ai-native-migration-kit/plugins/ai-native-migration/scripts/ai-native-verify <target>
```

**B. Vendor into the target repo** (best for CI on repos that may not have git access to arbitrary GitHub URLs):

```bash
# One-time:
cp -r plugins/ai-native-migration/scripts <your-repo>/scripts/ai-native-verify-tool

# Then in .github/workflows/ai-native.yml:
- run: ./scripts/ai-native-verify-tool/ai-native-verify .
```

Exit codes: `0` = all pass or n/a, `1` = ≥1 partial, `2` = ≥1 fail, `3` = preflight/usage error. Ready for pre-push hooks, PR gates, or a quick sanity check.

### Sample output

Against the kit's own realistic fixture ([`tests/fixtures/realistic/`](tests/fixtures/realistic/)) — a small Next.js project with deliberate mixed strengths and gaps:

```
ai-native-verify — tests/fixtures/realistic
rubric 0.2.0

  pass      D01 — AGENTS.md present and non-trivial
            AGENTS.md present, 4 top-level headings
  partial   D02 — CLAUDE.md is a symlink to AGENTS.md
            CLAUDE.md is a regular file (should be a symlink to AGENTS.md)
  fail      D03 — .claude/settings.json with denyList and hooks
            .claude/settings.json missing
  ...
  partial   D08 — docs quartet (ARCHITECTURE, DEVELOPMENT, TESTING, PRECOMMIT)
            docs quartet incomplete — present: ARCHITECTURE.md DEVELOPMENT.md; missing: TESTING.md PRECOMMIT.md
  ...
  partial   D13 — CI config with build+test+lint gates
            CI has 2/3 gates; missing: lint
  ...
  n/a       D18 — Onboarding automation activates guardrails
            no .pre-commit-config to activate (D06 fails first)

summary  3 pass · 3 partial · 11 fail · 1 n/a
```

Every finding carries evidence (`file:line` or exact quote) and a remediation hint pointing at the specific template that fixes it.

### Bootstrap templates into a target

If the plan surfaced gaps you want to fix with the kit's own baseline templates, the plugin's `bootstrap.sh` walks each template one at a time with `apply / skip / edit-then-apply / quit`. Under normal use, the `/ai-native-migration:migrate --apply <target>` invocation from step 7 of the skill calls it for you. To run bootstrap directly against a target from a shell:

```bash
# Assuming you cloned the kit as in "Deterministic layer" above:
~/tools/ai-native-migration-kit/plugins/ai-native-migration/scripts/bootstrap.sh --target=<path-to-target>
```

Security-sensitive templates (`.claude/settings.json`, `.mcp.json`) always prompt regardless of any flag. Files land unstaged — the human decides what to `git add`.

## The human-in-the-loop guarantees

Encoded in code, not prose:

1. **The default flow writes exactly one file into the target repo** — the plan file. Nothing else.
2. **`--apply` is per-template interactive.** No batch mode, no `--yes`.
3. **Security-sensitive templates are always interactive**, regardless of any flag.
4. **Every recommendation traces to the rubric** — cites a section of the kit's [checklist](plugins/ai-native-migration/references/ai-native-checklist.md). No external-curriculum or reference-repo citations.
5. **The plan file names its own limits** — a Confidence section lists what the audit could NOT judge (skipped judges, unavailable `context7`, dirty working trees).

## How the agentic layer works

Three prompting patterns, documented in plain language for humans-in-the-loop in [`plugins/ai-native-migration/references/patterns-explained.md`](plugins/ai-native-migration/references/patterns-explained.md):

- **Judge** — one `agent()` call per criterion, structured JSON output, parallel execution.
- **Adversarial verify (N-vote)** — for each finding, spawn N independent skeptics with fresh contexts, prompted to *refute*. Majority-refuted findings drop silently. Standard depth = 1 verifier; thorough = 3.
- **Completeness critic** — final agent (thorough mode) reads aggregated findings and identifies gaps in the audit itself. Loop-back up to 2 rounds.

Framework-specific guidance is queried live from the [`context7`](https://context7.com) MCP at audit time (judge A08). No hand-authored per-stack overlays — guidance never rots.

## The semantic judges (A01–A08)

Each judge is one `agent()` call in the workflow, scored 0–3 against a subset of the four through-lines. A judge returns `null` (abstain) when the input it needs is absent — e.g., A05 abstains when `docs/ARCHITECTURE.md` doesn't exist, because there is nothing to check drift against. Every judge's full scoring rubric lives in [`plugins/ai-native-migration/references/judging-rubrics.md`](plugins/ai-native-migration/references/judging-rubrics.md); the summaries below are intent-only.

| ID | Judge | Through-line | Evaluates |
|---|---|---|---|
| **A01** | AGENTS.md quality | Explicit | The five canonical sections (Project Overview, Coding Standards, Key Commands, Architecture Notes, Things to Avoid), real content per section, and size discipline (~120–200 lines). |
| **A02** | AGENTS.md governance section | Explicit | The advisory layer of the two-layer governance pattern: **do-not-modify**, **always-run**, and **escalate-when** lists — each with specific entries, not placeholders. |
| **A03** | Settings.json ↔ AGENTS.md alignment | Explicit | For every advisory rule in AGENTS.md, is there a matching denyList entry or hook in `.claude/settings.json`? Flags policy drift between the advisory and enforced layers. |
| **A04** | Test AI-legibility | Verification | Five properties of legible tests: isolated assertions, descriptive names, readable-diff matchers, deterministic execution, minimal scope. Per-workspace in monorepos. |
| **A05** | ARCHITECTURE.md drift | Structured | Every filepath, directory, and component name referenced in `docs/ARCHITECTURE.md` still exists; the described layout matches the codebase. Abstains when the doc is absent. |
| **A06** | Docs describe workflows that exist | Structured | Commands and scripts in `DEVELOPMENT.md` / `TESTING.md` / `PRECOMMIT.md` are actually present (`package.json` scripts, Makefile targets, pre-commit hooks). |
| **A07** | Coverage / mutation-testing signal | Verification | Coverage tool wired to CI with an enforced threshold; mutation-testing tool present, even if opt-in. |
| **A08** | Stack conventions | Varies by stack | Framework-specific conventions queried live from the `context7` MCP at audit time. Falls back to a stack-generic floor when `context7` is unavailable, marking the judgment `degraded`. |

**How the depth presets choose judges:**

- **light** — A01 + A02 + A04. The three highest-signal judges for a first-pass audit on a repo that hasn't been touched yet.
- **standard** — A01 + A02 + A04 + A05 + A06. Adds the structured-artifact judges once the target has some docs to check drift against.
- **thorough** — all 8 (adds A03 alignment check, A07 coverage signal, A08 stack conventions). Combined with 3-vote adversarial verify and the completeness critic.
- **custom** — pass `--judges=A01,A03,A08` to name your own subset; combine with `--verify=<N>` and `--critic=on|off`.

Every finding a judge emits must cite its rubric section (e.g., `§Part 2 A04`). Uncited findings are dropped by the synthesizer — recommendations in a plan file always trace back to the rubric.

## Monorepo support (v0.2.0)

The kit detects the monorepo topology of the target and applies per-criterion scope from [rubric §5](plugins/ai-native-migration/references/ai-native-checklist.md#5-scope-in-monorepos-added-in-v020). Supported workspace managers: pnpm, yarn, npm workspaces, lerna, nx, turbo, rush, gradle multi-module, maven multi-module, cargo workspaces, `go.work`, composer path repositories, and Bazel (detect-only).

Behavior in a monorepo:

- **Per-workspace checks** (D10/D11/D12/A04): each workspace scored independently, aggregated to `pass` / `partial` / `fail` per [§5.2](plugins/ai-native-migration/references/ai-native-checklist.md#52-aggregation-rule-for-per-workspace-checks).
- **Root-primary checks** (D08/D16/A05/A06/A07): root artifact scored first; workspace fallbacks can upgrade a root fail to `partial` per [§5.4](plugins/ai-native-migration/references/ai-native-checklist.md#54-root-primary-semantics).
- **Cross-stack repos** (workspaces disagree on stack): the deterministic scorecard reports `stack.stack == "cross-stack"`, and A08 runs per-workspace with no overall aggregate per [§5.3](plugins/ai-native-migration/references/ai-native-checklist.md#53-cross-stack-monorepos-and-a08).
- **Plan file** gains a `## Workspace layout` section listing every detected workspace and its per-workspace stack. Per-workspace evidence renders as a nested bullet list under each finding.

Full design record: [`docs/specs/02-monorepo-support/`](docs/specs/02-monorepo-support/).

## Design record

Every non-obvious design decision is captured under [`docs/specs/`](docs/specs/):

- [`01-initial-design/`](docs/specs/01-initial-design/) — the initial design + Q&A trail + 31-task build plan.
- [`02-monorepo-support/`](docs/specs/02-monorepo-support/) — the v0.2.0 monorepo work: detection model, per-criterion scope, cross-stack semantics, phased rollout.

## Testing the kit

```bash
./tests/all.sh
```

Four harnesses (bash ai-native-verify + bash detect-workspaces + bash common.sh + node workflow logic). CI runs the same command.

## Repo layout

```
ai-native-migration-kit/
├── .claude-plugin/
│   └── marketplace.json               # marketplace catalog: lists the plugin below
├── AGENTS.md                          # kit's own context file (self-dogfood)
├── CLAUDE.md → AGENTS.md
├── plugins/
│   └── ai-native-migration/           # THE plugin
│       ├── .claude-plugin/
│       │   └── plugin.json            # plugin manifest (name, version, author)
│       ├── skills/
│       │   └── migrate/
│       │       └── SKILL.md           # /ai-native-migration:migrate entry point
│       ├── scripts/
│       │   ├── ai-native-verify       # deterministic audit — pure bash + jq
│       │   ├── detect-stack.sh        # stack + framework detection
│       │   ├── detect-workspaces.sh   # monorepo topology detection
│       │   └── bootstrap.sh           # interactive template application
│       ├── workflows/
│       │   └── ai-native-audit.js     # agentic audit workflow
│       ├── references/
│       │   ├── ai-native-checklist.md # canonical rubric (D01–D18 + A01–A08)
│       │   ├── judging-rubrics.md     # per-judge scoring rubrics + JSON schemas
│       │   ├── patterns-explained.md  # judge / adversarial verify / critic
│       │   ├── stack-generic.md       # cross-stack floor for A08 fallback
│       │   └── walkthroughs.md        # per-artifact conversational scripts for --apply
│       └── templates/                 # baseline artifacts bootstrap.sh applies
├── tests/
│   ├── all.sh                         # combined runner
│   ├── verify.test.sh                 # deterministic-layer harness
│   ├── common.test.sh                 # scripts/lib/common.sh harness
│   ├── detect-workspaces.test.sh      # monorepo detection harness
│   ├── workflow.test.mjs              # workflow-logic harness (Node)
│   └── fixtures/                      # kit-owned, no external repos
│       ├── empty/                     # baseline for structural absence
│       ├── perfect/                   # baseline for 18/18 pass
│       ├── partial/                   # baseline for the partial verdict paths
│       ├── realistic/                 # T-30 regression baseline
│       └── monorepos/                 # per-workspace-manager topology fixtures
└── docs/
    ├── ARCHITECTURE.md
    ├── DEVELOPMENT.md
    ├── TESTING.md
    ├── PRECOMMIT.md
    ├── plans/
    │   └── dogfood-decisions.md       # accepted findings from the T-29 self-audit
    └── specs/
        ├── 01-initial-design/         # initial design + Q&A trail + 31-task build plan
        └── 02-monorepo-support/       # v0.2.0 monorepo work
```

## License

[MIT](LICENSE) — © 2026 Theodoros Goulas.

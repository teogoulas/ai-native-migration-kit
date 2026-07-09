# Development

How to work on `ai-native-migration-kit` locally. Companion to [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Setup

The kit ships as a Claude Code plugin. Two ways to work on it:

**A. Load directly with `--plugin-dir` (recommended for local dev):**

```bash
git clone https://github.com/teogoulas/ai-native-migration-kit.git
cd ai-native-migration-kit
claude --plugin-dir ./plugins/ai-native-migration
```

Edits to the plugin are picked up by `/reload-plugins` — no re-clone needed.

**B. Install from the marketplace (for consumers, not developers):**

```
/plugin marketplace add teogoulas/ai-native-migration-kit
/plugin install ai-native-migration@ai-native-migration-kit
```

Requirements at runtime: `bash`, `git`, `jq`. `python3` recommended; `node` needed only for `tests/all.sh`.

## Working on the kit

The design is stable — see [`specs/01-initial-design/`](specs/01-initial-design/). Non-obvious decisions are captured in `01-questions-1-initial-design.md`. Read the questions file before proposing a design change.

### Historical task list

The initial build was tracked as `T-01` through `T-32` in [`specs/01-initial-design/01-tasks-initial-design.md`](specs/01-initial-design/01-tasks-initial-design.md). All complete. Preserved for the design record; not a live todo list.

### Commits

Direct-to-`main` for solo work; feature-branch + PR for external contributions.

Conventional Commits format:

```
<type>(<scope>): <subject>

<body>
```

The commit-msg pre-commit hook enforces the convention — the `.gitmessage` template opens on `git commit` (once you run `git config commit.template .gitmessage`).

### The deny-list

`plugins/ai-native-migration/templates/**` and `plugins/ai-native-migration/references/**` are deny-listed for Edit/Write in `.claude/settings.json` (spec §12). To change a file under those trees:

1. In the same PR, edit `.claude/settings.json` to lift the block.
2. Make the template/reference change.
3. Restore the deny-list before committing.

This is the "policy as code" invariant the kit teaches, applied recursively.

### Dogfood

The kit's own repo is the primary regression fixture (spec §14). Run `./plugins/ai-native-migration/scripts/ai-native-verify .` against it frequently — the T-29 baseline (documented in [`docs/plans/dogfood-decisions.md`](plans/dogfood-decisions.md)) is 14 pass / 3 fail-with-justification / 1 n/a-with-justification. Any drift from that shape means either the rubric changed intentionally, or the kit regressed.

## Repo layout

```
ai-native-migration-kit/
├── .claude-plugin/
│   └── marketplace.json               # marketplace catalog
├── .claude/
│   └── settings.json                  # kit's own repo-scoped settings + deny-list
├── AGENTS.md                          # kit's own context file (CLAUDE.md → this)
├── CLAUDE.md                          # symlink → AGENTS.md
├── LICENSE                            # MIT
├── README.md                          # public-facing intro
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT.md                 # (this file)
│   ├── TESTING.md
│   ├── plans/
│   │   └── dogfood-decisions.md
│   └── specs/01-initial-design/
├── plugins/
│   └── ai-native-migration/
│       ├── .claude-plugin/
│       │   └── plugin.json            # plugin manifest
│       ├── skills/
│       │   └── migrate/SKILL.md       # /ai-native-migration:migrate
│       ├── scripts/
│       ├── workflows/
│       ├── references/
│       └── templates/
└── tests/
    ├── all.sh
    ├── verify.test.sh
    ├── workflow.test.mjs
    └── fixtures/
```

## Testing

- **`ai-native-verify` self-tests** land in T-12 (bats-core against three kit-owned synthetic fixtures: `tests/fixtures/empty/`, `tests/fixtures/perfect/`, `tests/fixtures/partial/`).
- **Judge output validation** happens at the `agent()` schema boundary — no separate test harness needed. Malformed judge output triggers automatic retry inside the workflow.
- **End-to-end acceptance** is T-30: run the kit against `tests/fixtures/realistic/` — a kit-owned fixture with deliberate mixed strengths and gaps — and human-review the plan.

## `ai-native-verify --format=json` schema

The JSON output is stable and versioned. Downstream consumers (the agentic workflow, target-repo CI jobs) parse it by key; field order is cosmetic. Current schema version: `"1"`.

```jsonc
{
  "schema_version": "1",           // Bumped on any breaking schema change.
  "target": "/abs/path/to/repo",   // Absolute path passed to ai-native-verify.
  "rubric_version": "0.1.0",       // Rubric version this run was scored against.
  "checks_requested": "all",       // "all" OR an array of check IDs like ["D01","D06"].
  "stack": {                       // Cached output of detect-stack.sh, embedded so
    "stack": "node",               // downstream callers don't have to re-invoke it.
    "framework": "next" | null,
    "package_manager": "pnpm" | null,
    "test_framework": "vitest" | null
  },
  "results": [                     // One entry per requested check, in rubric order.
    {
      "id": "D01",                 // Rubric criterion id: D01..D18.
      "label": "AGENTS.md ...",    // One-line human-readable summary from the rubric.
      "verdict": "pass"            // One of: "pass", "partial", "fail", "n/a".
              | "partial"
              | "fail"
              | "n/a",
      "evidence": "AGENTS.md ...", // Concrete finding statement. Never empty.
      "remediation_hint": "..."    // Actionable one-liner. Empty when verdict=pass or n/a.
    }
  ],
  "summary": {                     // Aggregate counts across `results`.
    "pass": 18,
    "partial": 0,
    "fail": 0,
    "na": 0
  },
  "exit_code": 0                   // The same exit code the process returns to the shell.
}
```

Downstream consumers should:

- Look results up by `id`, not by index — a future rubric addition may insert new checks.
- Treat `checks_requested == "all"` and `checks_requested = [D01, D02, ...]` symmetrically for filtering purposes.
- Use `stack` as-is; do not re-invoke `detect-stack.sh` separately.
- Watch `schema_version` for changes and refuse to interpret unknown versions.

## Contributing

External contributions are welcome once v1 lands. Until then, the maintainer is iterating directly to `main`. Open an issue if you have a use case that the current design doesn't cover — that's the most useful feedback right now.

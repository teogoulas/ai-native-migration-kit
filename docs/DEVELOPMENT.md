# Development

How to work on `ai-native-migration-kit` locally. Companion to [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Setup

Nothing to install yet — the kit's runtime dependencies (bash, jq, git, Claude Code) will be checked by `install.sh` in Phase 5. During Phases 0–4, the repo is prose + specs only.

Once tooling lands, the dev flow will be:

```bash
# Clone
git clone https://github.com/teogoulas/ai-native-migration-kit.git
cd ai-native-migration-kit

# Install the skill into ~/.claude/skills/ (symlink; edits reflect immediately)
./install.sh

# Verify install
ls ~/.claude/skills/ai-native-migration/
```

## Working on the kit

The design is stable — see [`specs/01-initial-design/`](specs/01-initial-design/). Non-obvious decisions are captured in `01-questions-1-initial-design.md`. Read the questions file before proposing a design change.

### Task selection

Pick the next `pending` task from [`specs/01-initial-design/01-tasks-initial-design.md`](specs/01-initial-design/01-tasks-initial-design.md) whose dependencies are all complete. Tasks are numbered `T-01` through `T-31` and grouped into 7 phases with strict phase ordering.

### Commits

Direct-to-`main` is fine for the initial build (per the maintainer's convention). Once v1 lands, switch to feature-branch + PR for external contributions.

Conventional Commits format:

```
<type>(<scope>): <subject>

<body>
```

Types used so far: `docs`, `feat`, `chore`. Full vocabulary lands with the pre-commit config in T-15.

### The deny-list

`skill/templates/**` and `skill/references/**` are deny-listed for Edit/Write in `.claude/settings.json` (spec §12). To change a file under those trees:

1. In the same PR, edit `.claude/settings.json` to lift the block.
2. Make the template/reference change.
3. Restore the deny-list before committing.

This is the "policy as code" invariant the kit teaches, applied recursively.

### Dogfood

The kit's own repo is the primary regression fixture (spec §14). Once T-11 (`ai-native-verify` JSON output) lands, run it against the kit itself frequently — every phase should leave the kit's own audit score higher, never lower.

## Repo layout

```
ai-native-migration-kit/
├── AGENTS.md               # single source of truth for AI context (CLAUDE.md → this)
├── CLAUDE.md               # symlink to AGENTS.md
├── LICENSE                 # MIT
├── README.md               # public-facing intro
├── .gitignore
├── .claude/                # populated by T-02: settings.json deny-list
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT.md      # (this file)
│   └── specs/
│       └── 01-initial-design/
│           ├── 01-spec-initial-design.md
│           ├── 01-questions-1-initial-design.md
│           └── 01-tasks-initial-design.md
└── skill/                  # populated by Phases 1–5
    ├── SKILL.md            # T-18
    ├── scripts/            # T-07 to T-12, T-27
    ├── workflows/          # T-19 to T-26
    ├── references/         # T-03 to T-06
    └── templates/          # T-13 to T-17
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

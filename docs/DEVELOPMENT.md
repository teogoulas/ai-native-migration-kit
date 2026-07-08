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

## Contributing

External contributions are welcome once v1 lands. Until then, the maintainer is iterating directly to `main`. Open an issue if you have a use case that the current design doesn't cover — that's the most useful feedback right now.

# ai-native-migration-kit

A Claude Code skill + workflow for auditing and migrating any repository toward **AI-native** status — a repo that is instrumented for an agent, not just decorated for one.

The kit combines a deterministic bash audit (18 structural checks) with an adversarially-verified agentic audit (up to 8 semantic judges), then produces a human-reviewable migration plan. It **never converts findings into commits autonomously** — human-in-the-loop is a design guarantee, not a preference.

## Status

Under active development. See [`docs/specs/01-initial-design/`](docs/specs/01-initial-design/) for the full design record:

- [`01-spec-initial-design.md`](docs/specs/01-initial-design/01-spec-initial-design.md) — the design
- [`01-questions-1-initial-design.md`](docs/specs/01-initial-design/01-questions-1-initial-design.md) — the Q&A trail from spec review
- [`01-tasks-initial-design.md`](docs/specs/01-initial-design/01-tasks-initial-design.md) — 31 tasks across 7 phases

Installation and usage documentation will land as Phase 5 (T-28) and Phase 6 (T-31) complete.

## License

[MIT](LICENSE)

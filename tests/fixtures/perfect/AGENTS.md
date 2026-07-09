# AGENTS.md

## Project Overview
A minimal fixture repo used to test ai-native-verify D01–D18. Node/Next-flavored so stack detection succeeds.

## Coding Standards
Two-space indent for shell, Prettier defaults elsewhere. All shell scripts pass shellcheck.

## Key Commands
- `pnpm test` — runs the vitest unit suite.
- `pnpm lint` — runs eslint.
- `pnpm dev` — starts the Next dev server.

## Architecture Notes
Trivial fixture: `src/app/` for the Next App Router entry points, `tests/` split into `unit/` and `integration/`, `e2e-tests/` for Playwright.

## Things to Avoid
- Do not commit `.env` — only `.env.example`.
- Do not disable pre-commit hooks with `--no-verify`.

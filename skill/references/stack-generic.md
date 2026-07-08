# Stack-generic conventions

The thin cross-stack floor A08 uses when `context7` is unavailable.

This file exists **only** as a degraded fallback. When A08 can query `context7` live, that query returns current, framework-specific guidance that is always more precise than anything below. This file is what A08 evaluates against when there's no live query — a headless session, an MCP-less environment, a context7 outage — so the judge doesn't have to skip entirely.

Deliberately short. If this file grows past ~100 lines, it is drifting toward being a per-stack overlay, which is the pattern the kit intentionally rejects (see spec §11 and questions file Q-01).

Conventions below hold across all stacks the kit is likely to encounter.

---

## G01 — Tests describe behavior, not method mechanics

Test names should state what a caller can observe, not what the implementation does. `book_returnsConfirmedAppointment_whenSlotAvailable` describes an observable outcome; `testBookMethod` describes a method's existence. Agents extending the suite imitate whichever pattern dominates — set the pattern deliberately.

**Applies to:** any test file in any language.

## G02 — Configuration lives in files, not code

Runtime configuration — database URLs, feature flags, API endpoints, log levels — belongs in files the agent can find by convention (e.g., `application.yml`, `.env.example`, `config/*.toml`) rather than embedded in source. Config in code is invisible to agents doing static analysis and forces them to run the code to see current values.

**Applies to:** any project with runtime configuration.

## G03 — Public API surface is documented in code

Every exported/public function, class, or endpoint has a doc comment at its declaration explaining its contract: inputs, outputs, side effects, error modes. The specific doc-comment syntax varies by stack (JavaDoc, JSDoc, docstrings, rustdoc, godoc), but presence is universal — an undocumented public symbol is a context leak.

**Applies to:** any project exposing an API surface (library, service, module).

## G04 — Errors carry actionable context

An error message identifies what failed, what was expected, and — when possible — what to do about it. `"database connection failed"` is a bad message. `"database connection failed: cannot resolve host 'db.example.com' (DNS_LOOKUP_ERROR); check network config or DNS_HOST env var"` gives an agent enough to self-correct. This is the log-and-error analog of A04's test-failure guidance.

**Applies to:** any project that produces error output.

## G05 — Secrets are never in committed files

No API keys, tokens, passwords, or private certs in the repository — ever. Look for the following as red flags:
- Files matching `**/secrets.*`, `**/*.env` (except `.env.example` or `.env.sample`), `**/*credentials*`
- High-entropy string literals in source files (base64-like sequences ≥ 32 chars)
- Hardcoded connection strings containing `:password@` patterns

An AI-native repo has a documented mechanism for secrets — env vars sourced from a secret store, sealed secrets, or a dedicated secrets manager — and its `.gitignore` / `.gitattributes` protect against accidental commits.

**Applies to:** every project without exception.

## G06 — Generated code is marked and separated

Auto-generated code (protobuf output, GraphQL types, ORM migrations that have been applied, OpenAPI clients) lives in a clearly-named directory (`generated/`, `_generated/`, `.gen/`) and every file starts with a `DO NOT EDIT` comment. The AGENTS.md governance section's do-not-modify list should include these paths. This tells agents to regenerate rather than edit.

**Applies to:** any project with a codegen step.

## G07 — Dependency versions are pinned

Dependencies are pinned to specific versions (lockfiles committed, exact-version constraints in manifests where the ecosystem supports them). `~` and `^` version ranges in production dependencies are the failure mode: two developers or two CI runs get different code without any git change. Agents cannot reason about which version is running.

**Applies to:** any project consuming external dependencies.

## G08 — Formatting is enforced by a tool, not a style guide

Every AI-native repo has a formatter that runs in pre-commit and CI. The specific tool depends on stack (`prettier`, `black`, `gofmt`, `rustfmt`, `spotless`), but its output is deterministic: reformat, and either nothing changes or the change is a diff. This eliminates a whole class of PR bikeshedding and lets agents match style without inferring rules.

**Applies to:** every project (a formatter exists for essentially every language).

## G09 — README says what and quick-start; details live elsewhere

The `README.md` covers three things: what this repo is (2–3 sentences), how to run it quickly (one command block), and links to `docs/` for anything longer. Everything else — architecture, dev workflow, testing, contribution guide — lives under `docs/`. A README that tries to be the full docs is unreadable; agents skim and miss what matters.

**Applies to:** any project with a README.

## G10 — Public entry points are named consistently

Whatever the stack calls "the thing you run to start development" is named the same across the team's repositories: `pnpm dev` or `make dev` or `just dev` or `./gradlew bootRun`. Consistency across repos matters more than absolute choice — an agent moving between repos should not have to relearn the entry command. Document the choice in `docs/DEVELOPMENT.md` and reference it from AGENTS.md's Key Commands section.

**Applies to:** any project a developer runs locally.

---

## Scoring guidance for A08 in degraded mode

When A08 falls back to this file, score against the 10 rules above:

- Count how many rules the target repo violates (a rule is either satisfied or violated; there is no partial credit for a per-rule check at this floor level).
- Map violation count to a score:
  - 0 violations → score 3
  - 1 violation → score 2
  - 2–3 violations → score 1
  - > 3 violations → score 0
- Always emit `degraded: true` in the output.
- In the plan file's Confidence section, note: *"A08 evaluated against stack-generic floor only (context7 unavailable). Re-run with context7 for full framework-specific guidance."*

The floor deliberately under-detects. Framework-specific conventions that context7 would catch (Spring Boot record-based DTOs, Next.js App Router structure, Django's ORM anti-patterns) are not in this file and cannot be.

---

## Maintenance rules

1. This file must stay short (~100 lines). Growth is a sign of drift toward per-stack overlays. If a specific stack needs specialized advice, that advice lives in context7's world, not here.
2. Every rule here holds across essentially all stacks. Rules that only apply to a subset of languages do not belong.
3. No coupling to external repositories or curricula (public tool and framework names remain neutral references, as always).
4. After T-32 lands, respect the deny-list. Lift in the same PR, edit, restore.

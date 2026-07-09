# Testing

<!--
  Test strategy + AI-legibility guidance. This file exists because tests
  serve two audiences in an AI-native repo: the human who reads a failure
  message at 4 PM on a Friday, and the AI agent that reads the same
  failure message and has to self-correct without a career of pattern
  recognition to fall back on.

  Judge A04 samples up to 5 tests per layer and scores against five
  AI-legibility properties. This file explains those properties so a
  contributor knows what "good" looks like BEFORE the audit finds
  what "bad" looks like.
-->

## The three layers

<!--
  Every AI-native repo runs three layers of tests. This section is the
  team's authoritative statement of which layer holds what — new tests
  land in the layer whose contract they satisfy, not "wherever it feels
  right".
-->

### Unit tests

- **Location:** [path — e.g., `src/test/unit/` or `tests/unit/`]
- **Command:** `[test unit]`
- **Contract:** exercise one behavior of one unit with no external I/O. No database, no network, no filesystem beyond in-memory fakes.
- **Feedback loop:** milliseconds. Runs on every save via watch mode.
- **Coverage aim:** [%] line, but see the AI-legibility section — coverage without meaningful assertions is decorative.

### Integration tests

- **Location:** [path — e.g., `tests/integration/`]
- **Command:** `[test integration]`
- **Contract:** exercise the wiring between components (controller ↔ service, service ↔ repository, adapter ↔ external). Real dependencies where practical (Testcontainers for databases, in-memory brokers for queues); mock only what is genuinely expensive or unavailable.
- **Feedback loop:** seconds to a minute.
- **Coverage aim:** every controller/handler entry point has at least one integration test that exercises the happy path.

### End-to-end tests

- **Location:** [path — e.g., `e2e-tests/`]
- **Command:** `[test e2e]`
- **Contract:** simulate a real user journey against a running instance. Produce proof artifacts (screenshots, traces, video) that a reviewer or agent can inspect after the run.
- **Feedback loop:** minutes.
- **Coverage aim:** every user-facing workflow the team owns has one E2E covering the happy path.

## AI-legibility properties

<!--
  The five properties judge A04 scores against. Every AI-native repo
  should be able to answer YES to each. Concrete examples are worth
  more than abstract rules — swap in your own idioms if the examples
  below don't match your stack.
-->

The failure message a test produces is the primary signal an AI agent uses to self-correct. Vague failures cost tokens and cause agents to alter production code chasing phantoms. Every test in this repo satisfies five properties:

### 1. Isolated assertions

**One behavioral check per test method.** A test with five assertions produces a failure that names only the first assertion that fired — the other four are invisible.

Bad:

```javascript
test('createAppointment', () => {
  const appt = service.book(slot, owner, pet)
  expect(appt).not.toBeNull()
  expect(appt.status).toBe('CONFIRMED')
  expect(appt.owner).toBe(owner)
  expect(appt.pet).toBe(pet)
  expect(appt.createdAt).toBeAfter(yesterday)
})
```

Good:

```javascript
test('book_returnsConfirmedAppointment_whenSlotAvailable', () => {
  const appt = service.book(slot, owner, pet)
  expect(appt.status).toBe('CONFIRMED')
})

test('book_associatesOwner_withAppointment', () => {
  const appt = service.book(slot, owner, pet)
  expect(appt.owner).toBe(owner)
})
```

### 2. Descriptive names

`testBook2` tells an agent nothing. `book_returnsConflictError_whenSlotAlreadyBooked` tells an agent the unit under test, the expected outcome, and the trigger condition — three pieces of context for the price of a method name.

Convention: `<subject>_<expectedOutcome>_<whenTrigger>` or the equivalent idiom in your test framework's DSL.

### 3. Readable-diff matchers

Matchers that print both expected and actual values on failure:

- **Java (AssertJ):** `assertThat(actual).isEqualTo(expected)` — prints both sides
- **Java (Hamcrest):** `assertThat(actual, is(expected))` — prints both sides
- **JS/TS (Vitest / Jest):** `expect(actual).toEqual(expected)` — prints a diff
- **Python (pytest):** `assert actual == expected` — pytest's assertion rewriter prints the diff
- **Go:** `testify/assert.Equal(t, expected, actual)` — prints both sides

Never use `assertTrue(x.equals(y))` or `assert x == y` where the failure will just say "expected true, got false" and hide which side was wrong.

### 4. Deterministic execution

Flaky tests are the enemy. A human can shrug and retry; an AI agent will alter production code chasing a phantom. Common sources of non-determinism, with fixes:

- **Wall-clock time** (`Date.now`, `LocalDateTime.now`, `datetime.now()`) — inject a `Clock` (or equivalent) and freeze it in tests.
- **Random UUIDs and unseeded RNGs** — seed randomness explicitly.
- **Unordered collections asserted with `equals`** — assert against sets when order is irrelevant, sort explicitly when it matters.
- **Live HTTP calls** — record with WireMock / MSW / pytest-httpx / vcrpy, replay in tests.
- **Shared database state between tests** — use Testcontainers per suite, `@Transactional` rollback per test, or explicit `beforeEach` truncation.

### 5. Minimal scope

A "unit" test that wires up twelve real collaborators is a slow integration test wearing a misleading name. When it fails, the failure surface is the whole dependency graph — too wide for an agent to isolate efficiently.

Keep unit tests narrow. Let integration tests carry broader scope explicitly, with a name and tag that says so (see §Integration tests above).

## Coverage as a spec-completeness signal

Line coverage on its own is a weak quality metric — every line ran, not every behavior was checked. The AI-native reframing: **treat uncovered branches as candidate spec gaps**.

Workflow:

1. Write a spec with acceptance criteria (see `docs/specs/`).
2. Generate code and tests against the spec.
3. Run coverage.
4. For each uncovered branch, ask: *is this behavior I forgot to specify, or dead code I forgot to delete?*
5. Either add an acceptance criterion to the spec, or remove the dead branch.
6. Regenerate tests.

### Mutation testing

Stronger signal than line coverage: [PIT](https://pitest.org/) for JVM, [Stryker](https://stryker-mutator.io/) for JS/TS/.NET, [mutmut](https://mutmut.readthedocs.io/) for Python. Flip an operator, swap a return value, delete a statement — if the test suite still passes, your assertions are weak. Rubric §Part 2 A07 checks whether either tool is wired to CI.

## Contract testing between services

<!--
  Only relevant if the repo consumes or provides an API. Delete this
  section for libraries or pure back-end services.
-->

When two components communicate over the wire (front-end ↔ back-end, service-A ↔ service-B), consumer-driven contract tests (Pact, Spring Cloud Contract) close the drift gap. The consumer declares what it expects; the provider verifies against the declared contract; the build fails if they drift.

If the spec defines the API contract, the contract test IS the spec validation.

## Snapshot testing

<!--
  Only relevant if the repo produces structured outputs (API response
  bodies, rendered templates, serialized events). Delete otherwise.
-->

Snapshots are high-value for: API response shapes, rendered UI, serialized events, formatted error messages. A snapshot diff is never noise:

- Intentional change → update the snapshot in the same PR with a note explaining why.
- Unintentional change → treat as a regression, fix the code.

Never auto-accept snapshot updates — that defeats the purpose. Never over-snapshot a 500-line payload; snapshot the contract (field names, types, representative values), not every byte.

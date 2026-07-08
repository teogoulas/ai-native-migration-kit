# Patterns explained

This file explains three multi-agent patterns the kit uses inside its audit workflow: **judge**, **adversarial verify (N-vote)**, and **completeness critic**. It is written for the humans-in-the-loop who read a generated migration plan file and want to understand how each finding got there — no ML background required.

The kit's workflow is a chain of these three patterns applied to the target repository. Each pattern is a specific way of using an AI agent to answer a specific kind of question about a codebase. They are not separate frameworks or tools — they are three different *prompting recipes* built on the same primitive: **spawn an AI subagent with a narrow prompt and a strict JSON output schema, then use its return value as data**.

Read this file once to build the mental model. Then when a plan file cites "judge A04 finding, refuted 1/3, survived" you'll know exactly what happened.

---

## The primitive: `agent()` with a schema

Every AI action the kit takes is a single `agent()` call. The call:

1. Spawns a fresh subagent — a new AI conversation with a **clean context window** (it does not see the parent's history).
2. Gives it a prompt targeting one specific question.
3. Requires the subagent to return a JSON object matching a schema — not free-form text.
4. Validates the JSON at the tool boundary. If it doesn't match the schema, the subagent retries automatically until it does.

The parent workflow gets back a validated object it can inspect with plain code — `finding.score`, `finding.evidence`, `verdict.refuted`. No parsing, no "what does this string mean," no leaking prose into control flow.

This matters because the three patterns below are just three different ways of composing this primitive. Nothing else.

---

## Pattern 1: Judge

**A judge is one `agent()` call that evaluates one dimension of a target and returns a scored, structured verdict.**

The kit runs up to eight judges, each focused on a single dimension of AI-nativeness:

- A01 — Is the AGENTS.md file well-structured and complete?
- A02 — Does AGENTS.md have a proper governance section?
- A03 — Do the rules stated in AGENTS.md match what settings.json actually enforces?
- A04 — Are the tests AI-legible (isolated assertions, deterministic, readable failure messages)?
- A05 — Is ARCHITECTURE.md still accurate against the current directory tree?
- A06 — Do the docs describe workflows that actually exist?
- A07 — Is there a coverage or mutation-testing signal wired to CI?
- A08 — Does the codebase follow current framework conventions for its detected stack?

Each judge gets a prompt like:

> "Read the file at `<target>/AGENTS.md`. Evaluate it against these six criteria: [list]. For each criterion, return `{criterion, score: 0–3, evidence, gap}`."

The judge reads the file. Not the whole repo — just what its prompt directs it to read. It scores each criterion, cites a concrete piece of evidence (a line number, a file path, an exact quote), and names the gap in one sentence.

### Why judges instead of one big analyzer

Two reasons, both about context economy:

1. **Each judge stays small in its own head.** A judge asked to score AGENTS.md doesn't need to know anything about tests. Its context window fills only with what its narrow question requires. A single "score everything" agent would drown in information and lose focus.
2. **Judges run in parallel.** Because they don't depend on each other's findings (governance-in-AGENTS.md doesn't depend on how the tests are written), the workflow spawns them concurrently. Wall-clock time is one judge's runtime, not the sum of all judges.

### Judge output is structured, not prose

A judge doesn't return "the AGENTS.md is pretty good but the governance section is thin." It returns:

```json
{
  "criterion": "governance-section",
  "score": 1,
  "evidence": "AGENTS.md lines 82-95 name 'do-not-modify' but no 'escalate-when' triggers.",
  "gap": "escalation triggers section missing"
}
```

The plan file's synthesizer takes this JSON and turns it into a human-readable finding with a cited source. If the judge had returned prose, the synthesizer would have to parse it, and parsing free-text is where multi-agent systems break down.

### What judges are *not*

Judges are **readers, not writers**. They score. They cite evidence. They never modify anything. Every edit to the target repo happens through the `bootstrap.sh` script, which is bash — not a judge, not any agent. A judge that tried to write a file would be a bug.

---

## Pattern 2: Adversarial verify (N-vote)

**Adversarial verify spawns N independent skeptics per judge finding, each prompted to *refute* the finding. Findings that survive a majority-of-skeptics vote reach the plan file; the rest are silently dropped.**

This exists because judges have a systematic bias worth naming.

### The plausibility bias of judges

A judge asked "how good is this AGENTS.md?" almost always finds *something* to critique. It's writing a report; a report of "everything is fine" feels incomplete. Judges are motivated to have output, and empty output feels like failure.

The result: judges produce plausible-sounding findings that are sometimes real, sometimes borderline, and sometimes just wrong — an artifact of the agent looking for something to say. Without a filter, all of those findings reach the plan file, and the human reviewer has to sort real from spurious. That's the exact work the kit is supposed to save.

### Inverting the bias

Adversarial verify inverts it. For each finding a judge produces, the workflow spawns N fresh subagents whose *only* job is to try to refute the finding. Each gets a prompt like:

> "A previous agent claimed: [finding]. Try to refute this claim by finding evidence to the contrary. Default to `refuted: true` if you cannot cite specific evidence that supports the finding. Return `{refuted: bool, evidence, confidence: 0-1}`."

The verifier reads the same file the judge read — but with a **fresh context window** and a **refute-first stance**. It looks for anything that would make the finding wrong. If it can't find such evidence, it says `refuted: true` — the burden of proof is on the finding, not the refutation.

Plain code (not another agent) then counts the votes:

- If majority say `refuted: true` → drop the finding, silently. It never reaches the plan file.
- If majority say `refuted: false` → the finding survives. It goes into the synthesizer.

### The three depth levels

- **Light** (`--depth=light`): no verify at all. Judges' findings go straight to synthesis. Fast, cheap, but noisier.
- **Standard** (`--depth=standard`, the default): 1 verifier per finding. Single skeptic; if it refutes, finding is dropped.
- **Thorough** (`--depth=thorough`): 3 verifiers per finding, majority rule. Catches more failure modes than a single skeptic because three independent contexts approach the finding from different angles.

### Why fresh contexts matter

A verifier that saw the judge's reasoning would be biased toward agreeing with it — anchoring. Fresh contexts break the anchoring. Each verifier reads only the target file and the finding claim. It has no access to the judge's chain of thought. Its verdict is independent.

### What survives adversarial verify

Only findings robust enough that N skeptics-with-fresh-context can't knock them down. That set is smaller than the set the judges produced, but it's the set that's actually worth acting on. Silent drops are the point.

### What adversarial verify does *not* do

It does not correct false negatives — if a judge missed a real issue, the verifier isn't going to find it either. False-negative coverage is the job of the completeness critic, next.

---

## Pattern 3: Completeness critic

**The completeness critic is one `agent()` call, run after all judges and verifiers finish, that asks a single question: what's missing?**

Judges answer "how good is what's here?" The completeness critic answers "what should have been evaluated but wasn't?"

### The prompt

The critic gets a prompt like:

> "Here are the aggregated findings from N judges: [findings]. Here is the full AI-native rubric the audit was supposed to cover: [rubric §4]. Identify: (a) any rubric criterion that has no finding — either passed silently or was skipped; (b) any claim in the findings that has no supporting evidence; (c) any file or convention named in the target repo that no judge looked at. Return `{gaps: [{type, description, suggested_action}]}`."

The critic reads the findings and the rubric side by side and reports what's missing. Not "here's another finding" — that's what the judges do. The critic reports **holes in the audit itself**.

### What the critic surfaces

Typical gap outputs:

- *"No judge evaluated criterion D18 (onboarding automation script). The check was defined in the rubric but no agent scored it."*
- *"Finding F-03 claims `.claude/settings.json` is missing audit hooks, but the finding cites no line number in the file. Evidence is unverified."*
- *"The target repo contains a `docs/decisions/` directory that appears to hold ADR-style architectural decision records, but no judge examined it. Consider adding a judge for architectural-decision-record presence in v2."*

### What happens with the gap list

In **thorough** mode, gaps drive another audit round. The workflow loops:

1. Judges run.
2. Verifiers run.
3. Critic runs.
4. If gaps → for each gap, spawn a judge (or verifier, or file-reader) to close it. Then go back to step 3.
5. If no gaps → done. Proceed to synthesis.

The loop is capped at 2 rounds. Two rounds is enough to close first-order gaps; further rounds usually just churn on edge cases.

In **standard** mode, the critic doesn't run at all. In **light** mode, neither the critic nor the verifiers run.

### Why the critic is separate from the judges

Judges are **inside-out** — each one starts from a criterion and looks at the target for evidence. The critic is **outside-in** — it starts from the aggregated output and looks for holes. Different mental posture, different prompt, different agent.

The critic also gets a broader view than any single judge: it sees *all* findings at once. That's how it can spot "no finding for D18" — no individual judge would notice, because each judge is only responsible for its own criterion.

### What the critic is *not*

- Not a validator. Verifying individual findings is the verifier's job.
- Not a scoring authority. The critic doesn't score anything on 0–3; it produces a list of holes.
- Not autonomous. The critic can identify gaps but does not decide how to fill them — the workflow's outer control flow does.

---

## The full assembly, in one paragraph

The target repo is inspected first by a bash script (`ai-native-verify`) for the 18 structural checks. Then, in the workflow: up to 8 judges run in parallel, each scoring one dimension of AI-nativeness against a JSON schema. For each judge finding, N adversarial verifiers try to refute it; findings that survive the majority vote proceed. In thorough mode, a completeness critic reads all surviving findings against the rubric and identifies any gaps in coverage; the workflow spawns additional agents to close those gaps and re-runs the critic. When the critic returns an empty gap list (or two rounds have elapsed), a final synthesis agent merges the deterministic scorecard and the verified findings into the migration plan file. Every finding in the plan cites the rubric section (§4.1 or §4.2) that motivates it. Nothing is written to the target repo except the plan file — everything else is either a decision the plan asks the human to make, or an interactive `bootstrap.sh --apply` step invoked separately.

That's the whole system.

---

## Reading a plan file with this mental model

When you read a migration plan the kit produced, each finding carries traces of these three patterns:

| Trace in plan | What it tells you |
|---|---|
| `Source: rubric §4.2 A04` | This finding came from judge A04 (test AI-legibility). Read §4.2 A04 in the spec to see the judging criteria. |
| `Verified: 3/3 survived` | Three adversarial verifiers were spawned; none of them could refute this finding. Highest confidence. |
| `Verified: 2/3 survived` | Three verifiers spawned; one refuted, two didn't. Passed the majority threshold, but consider re-reading before acting. |
| `Verified: single-vote (standard depth)` | Only one verifier ran; the finding survived. |
| `Coverage: gap closed via critic loop, round 2` | A completeness critic flagged this criterion as unjudged in round 1, and a follow-up judge in round 2 produced this finding. |
| `Coverage: critic surfaced no new gaps` | Thorough-mode signal that the audit converged cleanly. |

If a finding surprises you, trace it back to its judge, read the judge's evidence citation, and if you disagree, edit the target file or reject the finding — you are the human in the loop. The patterns above are how the kit narrows the space of things worth your attention. They don't make the decision for you.

# Architecture

One-page overview of how `ai-native-migration-kit` fits together. For the full design record with rationale, see [`specs/01-initial-design/01-spec-initial-design.md`](specs/01-initial-design/01-spec-initial-design.md).

## Flow

```
User invokes:  /ai-native-migration <target-repo> [--depth=...] [--apply]
                        │
                        ▼
             ┌──────────────────────┐
             │  skill/SKILL.md      │  (front door: describes the process to the reading agent)
             └──────────┬───────────┘
                        │
        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼
 detect-stack.sh   ai-native-verify   workflows/ai-native-audit.js
 {stack,           (18 deterministic  (8 semantic judges +
  framework,        structural checks; adversarial verify +
  versions}         JSON on stdout)   optional completeness critic)
                                      │
                                      ▼
                          synthesizer agent merges
                          deterministic + agentic findings
                                      │
                                      ▼
                     writes plan file into TARGET repo:
                     <target>/docs/plans/ai-native-migration-<date>.md
                                      │
                                      ▼
                     (default flow stops here — no other writes)
                                      │
                          IF --apply supplied:
                                      ▼
                         bootstrap.sh (per-template, interactive)
                         renders skill/templates/* into target repo,
                         unstaged, one file at a time
```

## Layer responsibilities

| Layer | Location | Purpose | Runtime |
|---|---|---|---|
| Skill front door | `skill/SKILL.md` | Describes the seven-step flow to the invoking agent; enforces human-in-the-loop guarantees in prose | Read by Claude Code on invocation |
| Deterministic audit | `skill/scripts/ai-native-verify` | 18 structural checks; emits JSON scorecard; exit code doubles as CI signal | Pure bash |
| Stack detection | `skill/scripts/detect-stack.sh` | Emits `{stack, framework, versions, ...}` from lockfiles | Pure bash |
| Agentic audit | `skill/workflows/ai-native-audit.js` | 8 semantic judges in parallel, adversarial verify, optional completeness critic, synthesis | Claude Code Workflow runtime |
| Reference rubric | `skill/references/ai-native-checklist.md` | Canonical criteria consumed by BOTH the deterministic script and the workflow synthesizer | Read-only text |
| Judge rubrics | `skill/references/judging-rubrics.md` | Per-judge prompt scaffolding + 0–3 score anchors | Read-only text |
| Pattern docs | `skill/references/patterns-explained.md` | Explains judge / adversarial verify / critic to humans reading a plan file | Read-only text |
| Bootstrap | `skill/scripts/bootstrap.sh` | Interactive, per-template application into target repo (spec §9) | Pure bash |
| Templates | `skill/templates/**` | Baseline AI-native artifacts rendered by bootstrap | Text templates |

## Human-in-the-loop boundaries

Two hard invariants enforced by code, not prompts:

1. **Default flow writes exactly one file** — the plan file, into the target repo's `docs/plans/`. Nothing else in the target repo is modified.
2. **`--apply` is per-template interactive** — no batch mode. Security-sensitive templates (`.claude/settings.json`, `.github/workflows/**`, `.mcp.json`) are always interactive regardless of any flag.

## Self-governance

The kit's own `.claude/settings.json` deny-lists Edit/Write on `skill/templates/**` and `skill/references/**` (spec §12). This applies the "policy as code" pattern the kit teaches, recursively, to the kit's own source of truth. To change any file in those trees, an engineer lifts the deny-list in `.claude/settings.json` in the same PR.

## What is NOT here

- No per-stack overlay files. A08's stack layer queries `context7` live at audit time (spec §11).
- No JSON audit sidecar. Plan file (markdown) is the sole persisted artifact in v1 (Q-02 resolution).
- No autonomous plan-to-PR pipeline. Permanently deferred (violates human-in-the-loop).

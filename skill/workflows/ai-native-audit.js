// ai-native-audit.js — the agentic audit workflow.
//
// Runs judges A01–A08 in parallel against a target repository, verifies
// findings adversarially, optionally runs a completeness critic, and
// synthesizes a plan file. The deterministic layer (ai-native-verify) runs
// first via a bash-invoking agent, and its scorecard is fed to the judges
// as ground truth.
//
// This file is T-19 scaffolding: it establishes the meta block, argument
// parsing, depth resolution, the deterministic-audit invocation, JSON
// schema constants, and the synthesis stage. Zero judges are wired.
// T-20/T-21/T-22 fill in the judge agents. T-23 wires adversarial verify.
// T-24 wires the completeness critic. T-25 finalizes the synthesizer.
// T-26 adds depth-flag routing overrides.
//
// Design notes for future editors:
//  - No filesystem or Date.now access from the workflow itself. Everything
//    goes through agent() calls whose subagents may use Bash/Read/Write.
//  - Every judge/verifier/synthesizer call uses a schema. Schema drift
//    with skill/references/judging-rubrics.md is a bug — same PR.
//  - Prompt content is sourced from references/*.md; do NOT inline
//    prompt bodies here. Each judge stage reads its prompt scaffolding
//    from references/judging-rubrics.md via the spawned agent.

export const meta = {
  name: 'ai-native-audit',
  description:
    'Audit a repository against the AI-native rubric (18 deterministic checks + up to 8 semantic judges) and synthesize a human-reviewable migration plan.',
  phases: [
    { title: 'Deterministic' },
    { title: 'Judge' },
    { title: 'Verify' },
    { title: 'Critique' },
    { title: 'Synthesize' },
  ],
}

// ─────────────────────────────────────────────────────────────────────────
// Argument parsing
// ─────────────────────────────────────────────────────────────────────────
//
// Expected `args` shape (passed from SKILL.md step 4):
//   {
//     target: '/absolute/path/to/target-repo',   // required
//     date:   '2026-07-08',                       // required (workflow can't
//                                                 //   call Date.now())
//     kitDir: '/abs/path/to/skill',               // required — where the
//                                                 //   scripts and references
//                                                 //   live
//     depth:  'light' | 'standard' | 'thorough' | 'custom',   // default 'standard'
//     judges: ['A01', 'A04'],   // custom-depth only; overrides the depth default
//     verify: 2,                // custom-depth only; N verifiers per finding
//     critic: 'on' | 'off',     // custom-depth only
//   }

if (!args || typeof args !== 'object') {
  throw new Error('ai-native-audit: args object is required (target, date, kitDir at minimum)')
}
if (!args.target) throw new Error('ai-native-audit: args.target is required')
if (!args.date) throw new Error('ai-native-audit: args.date is required (ISO YYYY-MM-DD)')
if (!args.kitDir) throw new Error('ai-native-audit: args.kitDir is required')

const TARGET = args.target
const DATE = args.date
const KIT_DIR = args.kitDir

const DEPTH_PRESETS = {
  light: {
    judges: ['A01', 'A04', 'A05'],
    verifiers: 0,
    critic: false,
    criticMaxRounds: 0,
  },
  standard: {
    judges: ['A01', 'A02', 'A04', 'A05', 'A06'],
    verifiers: 1,
    critic: false,
    criticMaxRounds: 0,
  },
  thorough: {
    judges: ['A01', 'A02', 'A03', 'A04', 'A05', 'A06', 'A07', 'A08'],
    verifiers: 3,
    critic: true,
    criticMaxRounds: 2,
  },
}

function resolveDepth(a) {
  const depth = a.depth || 'standard'
  if (depth !== 'custom') {
    if (!(depth in DEPTH_PRESETS)) {
      throw new Error(`unknown depth: ${depth} (valid: light, standard, thorough, custom)`)
    }
    return { name: depth, ...DEPTH_PRESETS[depth] }
  }
  // Custom depth — read overrides.
  const validJudges = ['A01', 'A02', 'A03', 'A04', 'A05', 'A06', 'A07', 'A08']
  const judges = Array.isArray(a.judges) ? a.judges : []
  for (const j of judges) {
    if (!validJudges.includes(j)) {
      throw new Error(`unknown judge id: ${j} (valid: ${validJudges.join(', ')})`)
    }
  }
  return {
    name: 'custom',
    judges,
    verifiers: typeof a.verify === 'number' ? a.verify : 0,
    critic: a.critic === 'on',
    criticMaxRounds: a.critic === 'on' ? 2 : 0,
  }
}

const CONFIG = resolveDepth(args)
log(
  `ai-native-audit: target=${TARGET} depth=${CONFIG.name} judges=[${CONFIG.judges.join(',') || 'none'}] verifiers=${CONFIG.verifiers} critic=${CONFIG.critic ? 'on' : 'off'}`,
)

// ─────────────────────────────────────────────────────────────────────────
// JSON schemas — must match skill/references/judging-rubrics.md
// ─────────────────────────────────────────────────────────────────────────
//
// Every agent() call that returns structured data uses one of these.
// The tool boundary validates the response against the schema and retries
// on mismatch, so drift between here and the judging-rubrics doc will
// surface as retry storms during a real run — fix by updating both files
// in the same PR.

// Deterministic scorecard — what ai-native-verify --format=json returns.
// Schema version 1 documented in docs/DEVELOPMENT.md.
const DETERMINISTIC_SCHEMA = {
  type: 'object',
  required: ['schema_version', 'target', 'rubric_version', 'stack', 'results', 'summary', 'exit_code'],
  properties: {
    schema_version: { type: 'string' },
    target: { type: 'string' },
    rubric_version: { type: 'string' },
    checks_requested: {},
    stack: {
      type: 'object',
      required: ['stack'],
      properties: {
        stack: { type: 'string' },
        framework: { type: ['string', 'null'] },
        package_manager: { type: ['string', 'null'] },
        test_framework: { type: ['string', 'null'] },
      },
    },
    results: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'verdict', 'evidence'],
        properties: {
          id: { type: 'string' },
          label: { type: 'string' },
          verdict: { enum: ['pass', 'partial', 'fail', 'n/a'] },
          evidence: { type: 'string' },
          remediation_hint: { type: 'string' },
        },
      },
    },
    summary: {
      type: 'object',
      required: ['pass', 'partial', 'fail', 'na'],
      properties: {
        pass: { type: 'integer' },
        partial: { type: 'integer' },
        fail: { type: 'integer' },
        na: { type: 'integer' },
      },
    },
    exit_code: { type: 'integer' },
  },
}

// Judge output — one per (A-criterion, target) evaluation. Fields per
// judging-rubrics.md §Global conventions "Universal output-schema fields".
// Dimension-specific fields (property_scores, drift_findings, etc.) live
// under `dimension_specific` so the schema stays single-shape here.
const JUDGE_SCHEMA = {
  type: 'object',
  required: ['criterion', 'score', 'evidence', 'gap', 'remediation'],
  properties: {
    criterion: { type: 'string', pattern: '^A0[1-8]$' },
    score: { type: ['integer', 'null'], minimum: 0, maximum: 3 },
    evidence: {
      type: 'array',
      items: { type: 'string' },
      minItems: 1,
    },
    gap: { type: 'string' },
    remediation: { type: 'string' },
    // Optional: A08 signals degraded=true when context7 was unavailable.
    degraded: { type: 'boolean' },
    // Optional: dimension-specific detail (property scores for A04,
    // drift findings for A05, etc.) — kept as a free-form object here;
    // per-judge schema strictness lives in the judge's prompt.
    dimension_specific: { type: 'object' },
  },
}

// Verifier output — one per (judge finding, verifier index).
const VERIFIER_SCHEMA = {
  type: 'object',
  required: ['refuted', 'evidence', 'confidence'],
  properties: {
    refuted: { type: 'boolean' },
    evidence: { type: 'array', items: { type: 'string' } },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
  },
}

// Completeness critic output — a list of gaps in the audit itself.
const CRITIC_SCHEMA = {
  type: 'object',
  required: ['gaps'],
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        required: ['type', 'description', 'suggested_action'],
        properties: {
          type: { enum: ['unjudged_criterion', 'unverified_claim', 'unread_source', 'missing_modality'] },
          description: { type: 'string' },
          suggested_action: { type: 'string' },
        },
      },
    },
  },
}

// Synthesizer output — the outcome-of-record. The synthesizer agent also
// writes the plan file to disk, so its returned object is a summary the
// workflow can log/return; the plan file is the persistent artifact.
const SYNTHESIS_SCHEMA = {
  type: 'object',
  required: ['plan_file_path', 'overall_score', 'top_findings'],
  properties: {
    plan_file_path: { type: 'string' },
    overall_score: {
      type: 'object',
      required: ['deterministic', 'agentic'],
      properties: {
        deterministic: { type: 'string' }, // e.g. "12/18 pass, 4 partial, 2 fail"
        agentic: { type: 'string' }, // e.g. "3.2/24 (weighted)" or "n/a"
      },
    },
    top_findings: {
      type: 'array',
      items: { type: 'string' },
      maxItems: 5,
    },
    degraded_layers: { type: 'array', items: { type: 'string' } },
  },
}

// ─────────────────────────────────────────────────────────────────────────
// Phase 1 — Deterministic audit
// ─────────────────────────────────────────────────────────────────────────
//
// The workflow itself can't invoke bash, so we spawn a small agent whose
// entire job is: run ai-native-verify, return the JSON. The agent has full
// tool access, so it can call Bash to run the script.

phase('Deterministic')

const deterministic = await agent(
  [
    `Run this exact command and return the JSON on stdout, PARSED, as your structured output:`,
    ``,
    `    ${KIT_DIR}/scripts/ai-native-verify --format=json ${TARGET}`,
    ``,
    `The exit code is not an error condition — 0, 1, 2 all indicate a successful audit.`,
    `Only exit code 3 or an inability to run the script counts as failure; in that case,`,
    `raise an error rather than returning a partial object.`,
    ``,
    `Do not modify the JSON. Do not add commentary. Return the parsed JSON object exactly.`,
  ].join('\n'),
  {
    label: 'ai-native-verify',
    schema: DETERMINISTIC_SCHEMA,
  },
)

if (!deterministic) {
  throw new Error('Deterministic audit failed — ai-native-verify did not return a parseable scorecard')
}

log(
  `Deterministic: ${deterministic.summary.pass} pass · ${deterministic.summary.partial} partial · ${deterministic.summary.fail} fail · ${deterministic.summary.na} n/a`,
)
log(`Stack detected: ${deterministic.stack.stack}${deterministic.stack.framework ? ` (${deterministic.stack.framework})` : ''}`)

// ─────────────────────────────────────────────────────────────────────────
// Phase 2 — Judges (T-20, T-21, T-22 fill this in)
// ─────────────────────────────────────────────────────────────────────────
//
// For each judge in CONFIG.judges, spawn a subagent with the appropriate
// prompt scaffolding from references/judging-rubrics.md, running in parallel
// via parallel() or pipeline() so findings flow to the verify phase as
// soon as each judge completes (no barrier).
//
// T-19 scaffolding: no judges yet. The array below is populated by later
// tasks. Because CONFIG.judges may still be non-empty (standard depth
// requests 5 judges), we filter to judges we know how to run — an empty
// filter means the judge phase is a no-op today.

phase('Judge')

const JUDGE_IMPLEMENTATIONS = {
  // T-20 populates A01, A02, A03, A04
  // T-21 populates A05, A06, A07
  // T-22 populates A08
}

const runnableJudges = CONFIG.judges.filter((j) => j in JUDGE_IMPLEMENTATIONS)
const skippedJudges = CONFIG.judges.filter((j) => !(j in JUDGE_IMPLEMENTATIONS))
if (skippedJudges.length > 0) {
  log(`Judges not yet implemented (skipped this run): ${skippedJudges.join(', ')}`)
}

const judgeFindings = [] // populated by T-20+ when judges land
// Placeholder: for each runnable judge, run the corresponding implementation.
// The implementations themselves live in JUDGE_IMPLEMENTATIONS above and
// are added in T-20 through T-22.

// ─────────────────────────────────────────────────────────────────────────
// Phase 3 — Adversarial verify (T-23 fills this in)
// ─────────────────────────────────────────────────────────────────────────

phase('Verify')

const verifiedFindings = judgeFindings // pass-through until T-23 lands
if (CONFIG.verifiers > 0 && judgeFindings.length > 0) {
  log(`Verify phase not yet implemented — pass-through of ${judgeFindings.length} finding(s)`)
}

// ─────────────────────────────────────────────────────────────────────────
// Phase 4 — Completeness critic (T-24 fills this in)
// ─────────────────────────────────────────────────────────────────────────

phase('Critique')

if (CONFIG.critic) {
  log('Critic phase not yet implemented — skipping')
}

// ─────────────────────────────────────────────────────────────────────────
// Phase 5 — Synthesize plan (T-25 finalizes)
// ─────────────────────────────────────────────────────────────────────────
//
// A synthesis agent takes the deterministic scorecard and the verified
// findings and writes the plan file to
//   <TARGET>/docs/plans/ai-native-migration-<DATE>.md
// It also returns a summary object matching SYNTHESIS_SCHEMA which the
// workflow returns to the caller. The plan file is the durable artifact;
// the returned object is for the caller (SKILL.md step 6) to log.
//
// T-19 scaffolding provides a working synthesizer that emits a
// deterministic-only plan file. T-25 replaces the prompt with the full
// through-line-organized structure from spec §8.

phase('Synthesize')

const synthesisPrompt = [
  `You are the synthesizer for the ai-native-migration-kit audit workflow.`,
  ``,
  `Your job is to write a plan file to disk AND return a JSON summary.`,
  ``,
  `Inputs:`,
  `  target repo:            ${TARGET}`,
  `  audit date:             ${DATE}`,
  `  depth:                  ${CONFIG.name}`,
  `  deterministic scorecard: (JSON below)`,
  `  agentic findings:       ${verifiedFindings.length} finding(s) (JSON below)`,
  ``,
  `Deterministic scorecard:`,
  '```json',
  JSON.stringify(deterministic, null, 2),
  '```',
  ``,
  `Agentic findings (may be empty if depth=light or if judges not yet implemented):`,
  '```json',
  JSON.stringify(verifiedFindings, null, 2),
  '```',
  ``,
  `Instructions:`,
  ``,
  `1. Write a Markdown plan file to:`,
  `     ${TARGET}/docs/plans/ai-native-migration-${DATE}.md`,
  `   Create the docs/plans/ directory if it does not exist. If a file with`,
  `   today's date already exists, append -2, -3, ... to the filename.`,
  ``,
  `2. Structure the plan per spec §8:`,
  ``,
  `     # AI-Native Migration Plan — <repo-name>`,
  `     **Generated:** ${DATE}`,
  `     **Depth:** ${CONFIG.name}`,
  `     **Stack detected:** ${deterministic.stack.stack}${deterministic.stack.framework ? ` (${deterministic.stack.framework})` : ''}`,
  `     **Overall score:** <n>/18 deterministic, <n>/<total> agentic (or "n/a" if 0 judges ran)`,
  ``,
  `     ## Executive summary`,
  `     3-5 sentences: what's strong, what's missing, biggest risks.`,
  ``,
  `     ## Findings by through-line`,
  `     Organize D-criteria and A-criteria findings into four groups based`,
  `     on the through-line each maps to (see references/ai-native-checklist.md):`,
  `       - Explicit over implicit`,
  `       - Verification at every level`,
  `       - Structured artifacts`,
  `       - Stable context anchors`,
  ``,
  `     For each finding, use this shape:`,
  `       - **Gap** (score X/3 or verdict): <one-line summary>`,
  `         - Evidence: <exact quote from the audit>`,
  `         - Recommendation: <specific action>`,
  `         - Source: \`rubric §Part 1 DNN\` OR \`rubric §Part 2 ANN\``,
  `         - Task: T-NN (assign sequential IDs)`,
  ``,
  `     ## Task list (PR-sized)`,
  `     One-line checkbox per task with an estimate.`,
  ``,
  `     ## Suggested sequencing`,
  `     Which tasks unlock which. Note the D18-depends-on-D06 fail cascade`,
  `     from the rubric.`,
  ``,
  `     ## Human-decision points`,
  `     Tasks that require a human call before an agent can proceed.`,
  ``,
  `     ## Confidence`,
  `     What could NOT be evaluated. Include:`,
  `       - Any judges not yet implemented (skippedJudges: ${skippedJudges.join(', ') || 'none'})`,
  `       - context7 availability if any A08 finding had degraded=true`,
  `       - Anything the deterministic layer reported as n/a`,
  ``,
  `3. Every recommendation MUST cite a rubric section (§Part 1 D01–D18 or`,
  `   §Part 2 A01–A08). No external citations.`,
  ``,
  `4. Return a JSON object matching the synthesis schema with:`,
  `   - plan_file_path: absolute path of the file you just wrote`,
  `   - overall_score: {deterministic: "<summary string>", agentic: "<summary string>"}`,
  `   - top_findings: up to 5 one-line strings for the highest-priority gaps`,
  `   - degraded_layers: any layers that were skipped or degraded`,
].join('\n')

const synthesis = await agent(synthesisPrompt, {
  label: 'synthesize',
  schema: SYNTHESIS_SCHEMA,
})

if (!synthesis) {
  throw new Error('Synthesis failed — no plan file was written')
}

log(`Plan file: ${synthesis.plan_file_path}`)
log(`Deterministic score: ${synthesis.overall_score.deterministic}`)
if (synthesis.overall_score.agentic && synthesis.overall_score.agentic !== 'n/a') {
  log(`Agentic score: ${synthesis.overall_score.agentic}`)
}
if (synthesis.degraded_layers && synthesis.degraded_layers.length > 0) {
  log(`Degraded layers: ${synthesis.degraded_layers.join(', ')}`)
}

// Return the synthesis result — SKILL.md step 6 uses this to report to
// the human.
return synthesis

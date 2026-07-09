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
//    with references/judging-rubrics.md is a bug — same PR.
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
// JSON schemas — must match references/judging-rubrics.md
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

// ─────────────────────────────────────────────────────────────────────────
// Shared prompt preamble — matches judging-rubrics.md §Global conventions.
// Every judge concatenates this with a dimension-specific extension.
// ─────────────────────────────────────────────────────────────────────────
const JUDGE_PREAMBLE = [
  'You are an evaluator for the ai-native-migration-kit auditing tool.',
  'Your job is to score ONE specific dimension of a target repository against',
  'a defined rubric. You are a reader, never a writer — never modify any file.',
  'Return a JSON object matching the provided schema. Every claim you make',
  'MUST cite specific evidence (file path, line number, or exact quoted text).',
  'Findings without evidence are unusable to the downstream synthesizer.',
  '',
].join('\n')

// ─────────────────────────────────────────────────────────────────────────
// JUDGE_IMPLEMENTATIONS — one function per A-criterion. Each returns a
// Promise for a JUDGE_SCHEMA-conforming object (or null on failure —
// filter(Boolean) downstream drops nulls silently, per pipeline() semantics).
//
// Judges run in parallel; keep them independent — no shared mutable state.
// The context object passed to each function is:
//   { target, det, kitDir }
// where `det` is the DETERMINISTIC_SCHEMA object from Phase 1. Judges use
// it to look up which folders/files to sample (e.g., A04 needs test-layer
// locations from D10–D12).
// ─────────────────────────────────────────────────────────────────────────

const JUDGE_IMPLEMENTATIONS = {
  A01: async ({ target }) =>
    agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: AGENTS.md quality. You evaluate whether the target',
        "repository's AGENTS.md contains the five canonical sections needed to",
        'orient an AI agent at session start — with adequate depth and appropriate',
        'size discipline. You do NOT evaluate the governance section (that is A02s',
        "job) or whether the file matches settings.json (A03's job).",
        '',
        'Task:',
        '',
        `Read the file at ${target}/AGENTS.md.`,
        '',
        'Score its quality against these five canonical sections:',
        '',
        '  1. Project Overview — concise description of what the project does,',
        '     its architecture at a glance, and key technologies.',
        '  2. Coding Standards — explicit rules the project follows (style,',
        '     naming, testing requirements).',
        '  3. Key Commands — build, test, lint, deploy commands an agent might run.',
        '  4. Architecture Notes — high-level system design, directory relationships.',
        '  5. Things to Avoid — deprecated patterns, security considerations,',
        '     gotchas. THIS IS THE MOST-SKIPPED and HIGHEST-VALUE section.',
        '     Call it out explicitly if missing.',
        '',
        'Also check size discipline:',
        '  - < 60 lines is almost always a stub (score down accordingly).',
        '  - 120–200 lines is the sweet spot.',
        '  - > 250 lines shows signs of dilution — agents skim, do not read.',
        '',
        'Section titles do NOT need to match verbatim. "Coding Style" satisfies',
        '"Coding Standards"; content presence is what matters.',
        '',
        'Score anchors (assign one of 0/1/2/3):',
        '  0 — File present but < 3 of the five sections identifiable, or all',
        '      content is placeholder / generated boilerplate.',
        '  1 — 3–4 sections present with real (non-placeholder) content;',
        '      Things-to-Avoid is missing OR is a stub.',
        '  2 — All five sections present with real content, BUT either < 100',
        '      lines with sparse content OR > 250 lines with signs of dilution.',
        '  3 — All five sections present, well-populated, in the 120–200-line',
        '      sweet spot.',
        '',
        'For evidence, cite specific AGENTS.md line ranges that contain (or',
        'should contain) each section — e.g., "AGENTS.md:12-28 covers Project',
        'Overview".',
        '',
        'Return JUDGE_SCHEMA with criterion="A01".',
      ].join('\n'),
      { label: 'A01: AGENTS.md quality', phase: 'Judge', schema: JUDGE_SCHEMA },
    ),

  A02: async ({ target }) =>
    agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: AGENTS.md governance section. You evaluate whether',
        'AGENTS.md contains an explicit governance sub-section that specifies',
        'what the agent must not do, must always do, and when to escalate.',
        'You do NOT evaluate whether these advisory rules are enforced by',
        "settings.json (that is A03's job).",
        '',
        'Task:',
        '',
        `Read the file at ${target}/AGENTS.md.`,
        '',
        'Identify any section (or clearly-marked block) whose title matches a',
        'governance keyword: "Governance", "Agent Governance", "Do not modify",',
        '"Rules", "Do-not-modify list", "Escalate", or similar.',
        '',
        'Within that section, look for three sub-elements:',
        '  1. Do-not-modify list — specific files or directories the agent',
        '     must never edit (e.g., src/generated/, .github/workflows/,',
        '     db/migrate/).',
        '  2. Always-run list — commands the agent must run before committing',
        '     (e.g., "./gradlew test", "pnpm lint", "pre-commit run --all-files").',
        '  3. Escalate-when list — situations requiring human judgment',
        '     (e.g., auth changes, DB migrations, changes touching > N files).',
        '',
        'Each sub-element must contain SPECIFIC entries, not placeholder text.',
        '"do not modify generated files" is not specific.',
        '"do not modify src/generated/ (auto-generated by protobuf)" is specific.',
        '',
        'Score anchors:',
        '  0 — No governance section identifiable, OR section title present with',
        '      only placeholder content.',
        '  1 — Section present with 1 of the 3 sub-elements populated with',
        '      specific entries.',
        '  2 — Section present with 2 of the 3 sub-elements populated with',
        '      specific entries.',
        '  3 — Section present with all 3 sub-elements populated with specific',
        '      entries (2+ entries each).',
        '',
        'For evidence, cite line ranges for the governance section and for each',
        'sub-element found (or not found).',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "governance_section_present": bool,',
        '    "sub_elements_present": [...],',
        '    "specific_entries_count": {"do-not-modify": N, "always-run": N, "escalate-when": N}',
        '  }',
        '',
        'Return JUDGE_SCHEMA with criterion="A02".',
      ].join('\n'),
      { label: 'A02: governance', phase: 'Judge', schema: JUDGE_SCHEMA },
    ),

  A03: async ({ target }) =>
    agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: cross-reference between the ADVISORY layer',
        '(AGENTS.md governance) and the ENFORCED layer (.claude/settings.json).',
        'You verify that rules stated in AGENTS.md have matching enforcement in',
        'settings.json. You do NOT re-evaluate the quality of either file',
        'individually — A01, A02, and D03 cover that.',
        '',
        'Task:',
        '',
        `Read both files:`,
        `  1. ${target}/AGENTS.md — specifically its governance section.`,
        `  2. ${target}/.claude/settings.json — if present.`,
        '',
        'Extract:',
        '  From AGENTS.md: every entry in the do-not-modify list, every',
        '                  command in the always-run list.',
        '  From settings.json: every pattern in the denyList, every hook',
        '                      definition.',
        '',
        'For each AGENTS.md governance entry, check whether settings.json',
        'enforces it:',
        '  Do-not-modify path X → does denyList contain a pattern matching',
        '    writes to X, OR does a PreToolUse hook check for X?',
        '  Always-run command Y → does a PostToolUse or Stop hook run Y before',
        '    completion?',
        '',
        'Absence of enforcement is a "policy drift" finding. Advisory rules',
        'with no enforced counterpart are the specific gap this judge detects.',
        '',
        'If AGENTS.md explicitly notes a rule as "advisory-only, intentionally',
        'not enforced", count it as satisfied.',
        '',
        'Score anchors:',
        '  0 — settings.json missing (defer to D03 for that finding) OR',
        '      settings.json has no rules matching AGENTS.md governance content.',
        '  1 — < 50% of advisory rules have matching enforcement.',
        '  2 — ≥ 50% of advisory rules have matching enforcement.',
        '  3 — Every advisory rule has enforcement, OR is explicitly annotated',
        '      as advisory-only.',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "settings_json_present": bool,',
        '    "advisory_rules_count": N,',
        '    "enforced_rules_count": N,',
        '    "drift_findings": [{advisory, enforced, location}, ...]',
        '  }',
        '',
        'Return JUDGE_SCHEMA with criterion="A03".',
      ].join('\n'),
      { label: 'A03: settings enforcement', phase: 'Judge', schema: JUDGE_SCHEMA },
    ),

  A04: async ({ target, det }) => {
    // A04 uses the deterministic scorecard to know where tests live.
    // Extract the D10–D12 evidence strings (they name test paths).
    const testEvidence = det.results
      .filter((r) => ['D10', 'D11', 'D12'].includes(r.id))
      .map((r) => `${r.id} ${r.verdict}: ${r.evidence}`)
      .join('\n  ')
    return agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: whether tests produce failure messages an AI agent',
        'can act on directly. Vague failures cost tokens and cause agents to',
        'alter production code chasing phantoms. You SAMPLE tests — do not',
        'attempt to score the entire suite. Up to 5 tests per detected test',
        'layer (unit / integration / E2E). Prefer tests recently modified',
        'or in central modules.',
        '',
        'Task:',
        '',
        `Detect test layers in ${target} using the deterministic scorecard`,
        `output (D10, D11, D12) which tells you where tests live:`,
        `  ${testEvidence || '(no test layers detected — see D10/D11/D12 verdicts)'}`,
        '',
        'If NO test layer was detected (all three fail or n/a), return score=null',
        "with gap='no tests to sample' and remediation pointing at D10.",
        '',
        'Otherwise, sample up to 5 test files per present layer. For each',
        'sampled file, evaluate up to 5 individual test methods against these',
        'five AI-legibility properties:',
        '',
        '  1. Isolated assertions — one behavioral check per test method.',
        '     Multiple assertions produce a failure that names only the first',
        '     to fire.',
        '  2. Descriptive names — name states the unit, expected outcome,',
        '     trigger. "book_returnsConfirmedAppointment_whenSlotAvailable"',
        '     beats "testBook".',
        '  3. Readable-diff matchers — Hamcrest is / AssertJ isEqualTo / Vitest',
        '     expect().toEqual() (both sides printed on failure). assertTrue',
        '     prints only "expected true, got false" and hides which side',
        '     was wrong.',
        '  4. Deterministic execution — no wall-clock (Date.now,',
        '     LocalDateTime.now without a Clock), no unseeded randomness,',
        '     no live network, no shared mutable state between tests.',
        '  5. Minimal scope — a "unit" test wiring up many real collaborators',
        '     is a mis-labeled integration test.',
        '',
        'Aggregate per layer: what fraction of sampled tests satisfy each',
        'property? Score the overall dimension based on the property-',
        'satisfaction fractions.',
        '',
        'Cite specific test files and line numbers for the strongest violations.',
        'Do NOT try to be comprehensive — 3 concrete counterexamples per',
        'property is better than 15 vague notes.',
        '',
        'Score anchors (overall dimension):',
        '  0 — Sampled tests violate ≥ 4 of the 5 properties.',
        '  1 — Sampled tests satisfy 2 of the 5 properties consistently.',
        '  2 — Sampled tests satisfy 3–4 of the 5 properties consistently.',
        '  3 — Sampled tests satisfy all 5 properties consistently.',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "layers_sampled": [...],',
        '    "tests_sampled_count": N,',
        '    "property_scores": {isolated_assertions: 0-3, descriptive_names: 0-3, ...}',
        '  }',
        '',
        'Return JUDGE_SCHEMA with criterion="A04".',
      ].join('\n'),
      { label: 'A04: test legibility', phase: 'Judge', schema: JUDGE_SCHEMA },
    )
  },

  A05: async ({ target }) =>
    agent(
      [
        JUDGE_PREAMBLE,
        "Focus dimension: whether the target's ARCHITECTURE.md still matches",
        'the codebase. Drift is the failure mode — the doc references paths,',
        'directories, or components that have been renamed, moved, or deleted.',
        'A drifted architecture doc actively misleads agents. This judge does',
        'not evaluate the QUALITY of the architecture description; it',
        'evaluates its ACCURACY against the current tree.',
        '',
        'Task:',
        '',
        `Read ${target}/docs/ARCHITECTURE.md.`,
        '',
        'If the file does not exist, return score=null with',
        "gap='ARCHITECTURE.md missing' and remediation pointing at D08.",
        '',
        'Otherwise, extract every path reference, directory name, and named',
        'component:',
        '  - Explicit filepaths (src/main/java/com/example/domain/Appointment.java)',
        '  - Directory references (src/main/java/, docs/specs/, .devcontainer/)',
        '  - Named modules, classes, services, or components',
        '    (AppointmentService, UserController, PaymentModule)',
        '',
        'For each extracted reference, verify against the target codebase:',
        '  - Does the path exist? (Use Bash or Read to check.)',
        '  - Does the named component still exist? (Use Grep to find it.)',
        '  - If the doc sketches a directory layout, does the actual',
        '    `find . -type d` output match?',
        '',
        'Also flag:',
        '  - Modules or major directories that exist but ARCHITECTURE.md does',
        '    NOT mention (documentation gaps, not drift, but the same fix).',
        '',
        'Score anchors:',
        '  0 — > 30% of referenced paths/components missing or renamed.',
        '  1 — 10–30% drift.',
        '  2 — < 10% drift; some minor path changes but overall structure accurate.',
        '  3 — Every referenced path exists and described layout matches.',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "references_extracted": N,',
        '    "references_valid": N,',
        '    "drift_percentage": 0.0-100.0,',
        '    "drift_findings": [{reference, status, actual?}, ...],',
        '    "unmentioned_modules": [...]',
        '  }',
        '',
        'For evidence, cite specific docs/ARCHITECTURE.md line numbers where',
        'stale references appear. Do NOT list every valid reference — only',
        "cite the mismatches, plus one or two illustrative valid ones if you're",
        'below 5% drift.',
        '',
        'Return JUDGE_SCHEMA with criterion="A05".',
      ].join('\n'),
      { label: 'A05: ARCHITECTURE accuracy', phase: 'Judge', schema: JUDGE_SCHEMA },
    ),

  A06: async ({ target, det }) => {
    // A06 cross-references docs against the deterministic scorecard the same
    // way A04 does. Extract the D06 (pre-commit), D10-D13 (tests + CI), D16
    // (linter), D18 (onboarding) verdicts so the judge knows what tooling
    // exists before scoring the docs against it.
    const toolEvidence = det.results
      .filter((r) => ['D06', 'D10', 'D11', 'D12', 'D13', 'D16', 'D18'].includes(r.id))
      .map((r) => `${r.id} ${r.verdict}: ${r.evidence}`)
      .join('\n  ')
    return agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: whether DEVELOPMENT.md, TESTING.md, and PRECOMMIT.md',
        'describe workflows that the deterministic scorecard confirms exist.',
        'A DEVELOPMENT.md that says "run pnpm dev" when package.json has no',
        '"dev" script leads agents into false paths.',
        '',
        'Task:',
        '',
        `Read all present files among:`,
        `  ${target}/docs/DEVELOPMENT.md`,
        `  ${target}/docs/TESTING.md`,
        `  ${target}/docs/PRECOMMIT.md`,
        '',
        'If none of the three exist, return score=null with',
        "gap='no dev docs present' and remediation pointing at D08.",
        '',
        'Extract every documented workflow element:',
        '  - Shell commands (e.g., "./gradlew test", "pnpm build")',
        '  - Package script names (e.g., "npm run dev")',
        '  - Referenced config files (e.g., "see .pre-commit-config.yaml")',
        '  - Referenced test frameworks or tools',
        '',
        'Cross-reference against the deterministic scorecard (the tooling the',
        'target actually has):',
        `  ${toolEvidence || '(no tool signals from deterministic scorecard)'}`,
        '',
        'For each documented command, check whether the corresponding tool',
        'exists in the repository — via package.json scripts, Makefile targets,',
        'gradle tasks, etc. For each documented tool, check whether the',
        'deterministic scorecard confirms it is actually configured.',
        '',
        'Flag mismatches in both directions:',
        '  - Docs describe tool X, but X is absent (misleading).',
        '  - Tool X is present, but no doc describes how to use it (gap).',
        '',
        'Score anchors:',
        '  0 — > 30% of documented workflows reference tools absent from the repo.',
        '  1 — 10–30% mismatch.',
        '  2 — < 10% mismatch; minor stale references but no undocumented tools.',
        '  3 — Every documented workflow tool is present; every present tool',
        '      is documented.',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "docs_read": [...],',
        '    "workflows_documented": N,',
        '    "workflows_matching_reality": N,',
        '    "mismatches": [{doc, workflow, issue}, ...],',
        '    "undocumented_tools": [...]',
        '  }',
        '',
        'Return JUDGE_SCHEMA with criterion="A06".',
      ].join('\n'),
      { label: 'A06: docs match reality', phase: 'Judge', schema: JUDGE_SCHEMA },
    )
  },

  A07: async ({ target, det }) => {
    const ciEvidence = det.results
      .filter((r) => r.id === 'D13')
      .map((r) => `D13 ${r.verdict}: ${r.evidence}`)
      .join('\n  ')
    return agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: whether coverage is used as a spec-completeness',
        'signal (wired to CI, gated by a threshold), and whether mutation',
        'testing is present as a stronger signal for assertion strength.',
        '',
        'Task:',
        '',
        `In ${target}, look for:`,
        '',
        '  1. Coverage tool configuration (varies by stack):',
        '     - JVM:    JaCoCo config in build.gradle or pom.xml',
        '     - Node:   Istanbul/nyc/vitest coverage in package.json or config',
        '     - Python: coverage.py config in pyproject.toml or .coveragerc',
        '     - Go:     -cover flags in test invocations',
        '     - Rust:   tarpaulin',
        '     - Ruby:   simplecov',
        '',
        '  2. CI wiring for coverage:',
        `     ${ciEvidence || '(no CI detected)'}`,
        '     Grep the CI config files (from D13) for coverage invocation and',
        '     a threshold enforcement: --min-cov=N, --fail-under=N,',
        '     coverage-threshold in a config, or a CI step that fails below N%.',
        '',
        '  3. Mutation testing tool configuration:',
        '     - PIT (pom.xml or build.gradle)',
        '     - Stryker (stryker.conf.*)',
        '     - mutmut (setup.cfg or pyproject.toml)',
        '     - go-mutesting',
        '',
        '  4. CI wiring for mutation testing (an opt-in weekly job counts).',
        '',
        'Score anchors:',
        '  0 — No coverage tool detected in CI. Coverage is not treated as a signal.',
        '  1 — Coverage tool present in CI, but no threshold enforced — measured',
        '      but not gated.',
        '  2 — Coverage tool with enforced threshold; no mutation testing.',
        '  3 — Coverage tool with threshold AND mutation testing wired in',
        '      (even if opt-in).',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "coverage_tool": "..." | null,',
        '    "coverage_threshold": N | null,',
        '    "coverage_in_ci": bool,',
        '    "mutation_tool": "..." | null,',
        '    "mutation_in_ci": bool',
        '  }',
        '',
        'Return JUDGE_SCHEMA with criterion="A07".',
      ].join('\n'),
      { label: 'A07: coverage signal', phase: 'Judge', schema: JUDGE_SCHEMA },
    )
  },

  A08: async ({ target, det, kitDir }) => {
    const stack = det.stack.stack
    const framework = det.stack.framework
    const packageManager = det.stack.package_manager
    const testFramework = det.stack.test_framework

    // Early exit: unknown stack means we can't ask context7 anything
    // meaningful, and the stack-generic floor covers the target no better
    // than the general rubric already does. Skip cleanly.
    if (stack === 'unknown' || !stack) {
      return {
        criterion: 'A08',
        score: null,
        evidence: ['stack detection returned "unknown" — no framework-specific evaluation possible'],
        gap: 'stack undetectable; A08 skipped',
        remediation: 'if the repo is intentionally polyglot or has no primary stack, declare it in AGENTS.md; otherwise ensure lockfiles/manifests are at the repo root so detect-stack.sh can classify',
        degraded: true,
        dimension_specific: {
          stack: 'unknown',
          reason: 'stack_undetectable',
        },
      }
    }

    return agent(
      [
        JUDGE_PREAMBLE,
        'Focus dimension: whether the target follows current framework',
        'conventions for its detected stack. Conventions rot fast, so you',
        'do NOT rely on embedded knowledge — you MUST query context7 live',
        "for the framework's current guidance. If context7 is unavailable,",
        `fall back to ${kitDir}/references/stack-generic.md and mark`,
        'the output as degraded.',
        '',
        'Detected stack:',
        `  stack:            ${stack}`,
        `  framework:        ${framework || '(none — pure language project)'}`,
        `  version:          ${det.stack ? JSON.stringify(det.stack) : '(unknown)'}`,
        `  package_manager:  ${packageManager || '(unknown)'}`,
        `  test_framework:   ${testFramework || '(unknown)'}`,
        '',
        'Task:',
        '',
        '1. ATTEMPT to query context7 via the mcp__context7__query-docs tool:',
        '',
        `   query: "AI-native conventions and best practices for ${framework || stack}`,
        '           including project structure, testing patterns,',
        '           and common anti-patterns"',
        '',
        '   Set the libraryName parameter to the framework name (or the',
        '   language name if framework is null).',
        '',
        '2. If context7 responds with usable guidance:',
        `   - Evaluate ${target} against that guidance using Read/Bash/Grep.`,
        '   - Cite the specific framework doc section context7 returned for',
        '     each finding so the reader can verify.',
        '   - Set degraded=false in your output.',
        '',
        '3. If context7 is unavailable, throws, or returns empty:',
        `   - Read ${kitDir}/references/stack-generic.md.`,
        '   - Evaluate the target against those cross-stack conventions only.',
        '   - Set degraded=true.',
        '   - Include this exact line in your evidence array:',
        '     "context7 unavailable — scored against stack-generic floor only"',
        '   - In stack-generic mode, use the scoring guidance embedded in',
        '     that file: count violations of G01-G10, map to a score.',
        '',
        'Score anchors (whether via context7 OR stack-generic):',
        '  0 — Target violates > 3 current framework conventions.',
        '  1 — 2–3 violations.',
        '  2 — 1 violation, or all violations are minor.',
        '  3 — Target follows current framework conventions.',
        '',
        'When degraded=true, note in the plan file that the score comes from',
        'the generic floor and is not a full framework-specific evaluation.',
        '',
        'In dimension_specific, include:',
        '  {',
        '    "stack": "...",',
        '    "framework": "...",',
        '    "framework_version": "..." | null,',
        '    "context7_available": bool,',
        '    "conventions_evaluated": N,',
        '    "conventions_violated": N',
        '  }',
        '',
        'Return JUDGE_SCHEMA with criterion="A08".',
      ].join('\n'),
      { label: `A08: ${framework || stack} conventions`, phase: 'Judge', schema: JUDGE_SCHEMA },
    )
  },
}

const runnableJudges = CONFIG.judges.filter((j) => j in JUDGE_IMPLEMENTATIONS)
const skippedJudges = CONFIG.judges.filter((j) => !(j in JUDGE_IMPLEMENTATIONS))
if (skippedJudges.length > 0) {
  log(`Judges not yet implemented (skipped this run): ${skippedJudges.join(', ')}`)
}

// Fan out judges in parallel. Each judge's result may be null (skipped by
// the runtime or terminal API error) — filter those out before verification.
const rawJudgeFindings =
  runnableJudges.length === 0
    ? []
    : await parallel(
        runnableJudges.map((j) => () =>
          JUDGE_IMPLEMENTATIONS[j]({ target: TARGET, det: deterministic, kitDir: KIT_DIR }),
        ),
      )

const judgeFindings = rawJudgeFindings.filter(Boolean)
log(`Judges: ${judgeFindings.length}/${runnableJudges.length} produced findings`)

// ─────────────────────────────────────────────────────────────────────────
// Phase 3 — Adversarial verify (T-23 fills this in)
// ─────────────────────────────────────────────────────────────────────────

phase('Verify')

// ─────────────────────────────────────────────────────────────────────────
// Adversarial verify — spawn N skeptics per finding, majority vote decides.
// See references/patterns-explained.md §Pattern 2 for the design rationale.
//
// Verifiers get:
//   - The judge's finding (JUDGE_SCHEMA object) as JSON.
//   - A refute-first prompt (default refuted=true when uncertain).
//   - A fresh context window (no view of the judge's chain of thought).
//
// The workflow then counts votes:
//   - Findings with score=null are pass-through (nothing to refute).
//   - Findings with score=3 are pass-through (no gap to challenge).
//   - Otherwise: majority-refuted → dropped silently; majority-not-refuted
//     → kept, with verify metadata attached so the synthesizer can show
//     "Verified: 2/3 survived" traces in the plan.
// ─────────────────────────────────────────────────────────────────────────

async function verifyFinding(finding, verifiersPerFinding) {
  // No-op verify: pass-through with a metadata marker so the synthesizer
  // knows this was seen but not challenged.
  if (verifiersPerFinding <= 0) {
    return { ...finding, verify: { skipped: true, ran: 0, refuted_count: 0 } }
  }
  // Score=null (judge deliberately abstained, e.g. A05 when ARCHITECTURE.md
  // missing) has no claim to refute — pass through.
  if (finding.score === null || finding.score === undefined) {
    return { ...finding, verify: { skipped: true, ran: 0, refuted_count: 0, reason: 'abstained' } }
  }
  // Score=3 with no gap: nothing to refute. Trust the pass verdict.
  if (finding.score === 3 && (!finding.gap || finding.gap.trim() === '')) {
    return { ...finding, verify: { skipped: true, ran: 0, refuted_count: 0, reason: 'clean_pass' } }
  }

  const findingJson = JSON.stringify(
    {
      criterion: finding.criterion,
      score: finding.score,
      evidence: finding.evidence,
      gap: finding.gap,
    },
    null,
    2,
  )

  // Spawn N verifiers in parallel. Each is a fresh subagent — the runtime
  // gives it an empty context window; nothing leaks between verifiers.
  const verifierResults = await parallel(
    Array.from({ length: verifiersPerFinding }, (_, i) => () =>
      agent(
        [
          `You are an adversarial verifier. A judge produced this finding for the ai-native-`,
          `migration-kit audit:`,
          '',
          '```json',
          findingJson,
          '```',
          '',
          `Your job is to REFUTE this finding. Read the same target files the judge read,`,
          `but with fresh eyes. Look for evidence the finding is wrong:`,
          `  - The judge misread a file.`,
          `  - The evidence doesn't actually support the score.`,
          `  - A specific counterexample invalidates the claim.`,
          `  - The judge missed context that would raise the score.`,
          '',
          `DEFAULT TO refuted: true if you cannot cite specific evidence contradicting`,
          `the finding. The burden of proof is on the finding, not the refutation.`,
          '',
          `Return {refuted: bool, evidence: [strings], confidence: 0-1}.`,
          '',
          `Verifier index: ${i + 1}/${verifiersPerFinding}. This is one of ${verifiersPerFinding}`,
          `independent verifications. Do not attempt to reason about the other verifiers'`,
          `outputs — you cannot see them.`,
        ].join('\n'),
        {
          label: `verify:${finding.criterion} #${i + 1}`,
          phase: 'Verify',
          schema: VERIFIER_SCHEMA,
        },
      ),
    ),
  )

  const verdicts = verifierResults.filter(Boolean)
  const refutedCount = verdicts.filter((v) => v.refuted === true).length
  // Majority vote. For N=1 this is "the one verifier said refuted".
  // For N=3 (thorough) this is "≥2 of 3 said refuted".
  const majorityRefuted = refutedCount > verdicts.length / 2

  return {
    ...finding,
    verify: {
      skipped: false,
      ran: verdicts.length,
      refuted_count: refutedCount,
      majority_refuted: majorityRefuted,
      // Preserve verifier evidence so the synthesizer can quote it in the
      // plan when a finding narrowly survives (e.g., 1-refuted of 3).
      verifier_evidence: verdicts.map((v) => ({
        refuted: v.refuted,
        confidence: v.confidence,
        evidence: v.evidence || [],
      })),
    },
  }
}

// Run verification serially over findings so the phase completes deterministically
// (each verify spawns its own parallel() burst internally). We could pipeline
// here — verify-A02 while verify-A01 runs — but the marginal wall-clock gain
// is small and the added complexity makes the log noisier for humans watching.
const verifyResults =
  CONFIG.verifiers > 0 && judgeFindings.length > 0
    ? await parallel(judgeFindings.map((f) => () => verifyFinding(f, CONFIG.verifiers)))
    : judgeFindings.map((f) => ({ ...f, verify: { skipped: true, ran: 0, refuted_count: 0, reason: 'depth' } }))

// Drop findings that majority-refuted. This is where noise silently
// disappears from the plan file — see patterns-explained.md.
const verifiedFindings = verifyResults.filter(Boolean).filter((f) => !f.verify?.majority_refuted)
const droppedCount = verifyResults.filter(Boolean).filter((f) => f.verify?.majority_refuted).length

if (CONFIG.verifiers > 0) {
  log(
    `Verify (${CONFIG.verifiers} verifier${CONFIG.verifiers > 1 ? 's' : ''}/finding): ${verifiedFindings.length} survived, ${droppedCount} refuted`,
  )
}

// ─────────────────────────────────────────────────────────────────────────
// Phase 4 — Completeness critic (T-24 fills this in)
// ─────────────────────────────────────────────────────────────────────────

phase('Critique')

// ─────────────────────────────────────────────────────────────────────────
// Completeness critic — outside-in view of the audit.
// See references/patterns-explained.md §Pattern 3.
//
// Only runs when CONFIG.critic is true (thorough depth). Reads all
// surviving findings + the deterministic scorecard + the rubric, and
// asks: what's missing? The gap list drives another audit round.
//
// Loop cap: CONFIG.criticMaxRounds. Empty gap list also exits.
// ─────────────────────────────────────────────────────────────────────────

// findingsAfterCritic is what flows into synthesis. In non-critic mode
// this is just the T-23 verifiedFindings; in critic mode it may grow as
// critic-driven rounds surface more findings.
let findingsAfterCritic = verifiedFindings

if (CONFIG.critic && CONFIG.criticMaxRounds > 0) {
  // Snapshot the criteria that ran this pass — the critic uses this to
  // identify unjudged criteria.
  const criteriaJudged = new Set(runnableJudges)

  // The rubric criteria the critic knows about. Kept inline (rather than
  // loaded from the checklist file) so the critic prompt doesn't require
  // extra tool calls just to know what a "criterion" is.
  const RUBRIC_A_CRITERIA = ['A01', 'A02', 'A03', 'A04', 'A05', 'A06', 'A07', 'A08']

  for (let round = 1; round <= CONFIG.criticMaxRounds; round++) {
    const criticInput = {
      round,
      max_rounds: CONFIG.criticMaxRounds,
      deterministic_summary: deterministic.summary,
      findings: findingsAfterCritic.map((f) => ({
        criterion: f.criterion,
        score: f.score,
        gap: f.gap,
        evidence_count: (f.evidence || []).length,
        verify: f.verify
          ? { ran: f.verify.ran, refuted_count: f.verify.refuted_count, skipped: f.verify.skipped }
          : null,
      })),
      criteria_judged: [...criteriaJudged],
      criteria_available: RUBRIC_A_CRITERIA,
    }

    const critique = await agent(
      [
        `You are the completeness critic for the ai-native-migration-kit audit.`,
        `You do NOT produce new findings yourself — you produce a list of GAPS`,
        `in the audit itself.`,
        '',
        `Input (round ${round} of up to ${CONFIG.criticMaxRounds}):`,
        '```json',
        JSON.stringify(criticInput, null, 2),
        '```',
        '',
        `Rubric context: the kit's semantic judges are A01 through A08. Their`,
        `full definitions live in references/ai-native-checklist.md`,
        `§Part 2. The deterministic layer (D01–D18) is fully covered by`,
        `ai-native-verify; you are NOT responsible for it here.`,
        '',
        `Identify gaps of these types:`,
        '',
        `  unjudged_criterion — a rubric criterion (A01–A08) that has no`,
        `    finding in the current round. Either the depth setting skipped`,
        `    it, or a judge silently failed. If it should be judged and`,
        `    isn't, list it.`,
        '',
        `  unverified_claim — a finding whose evidence is thin or where the`,
        `    verify layer clearly saw the finding but a claim within it`,
        `    remains unsupported (e.g., a judge cited files but the finding's`,
        `    gap statement references something the evidence doesn't cover).`,
        '',
        `  unread_source — a file or convention that would materially change`,
        `    a finding but no judge read it (e.g., a docs/decisions/ ADR that`,
        `    contradicts an A05 drift finding).`,
        '',
        `  missing_modality — a search angle no judge took. Rare but valuable`,
        `    (e.g., 'no judge examined .github/CODEOWNERS coverage patterns').`,
        '',
        `Do NOT surface gaps for things outside A01–A08 scope. Do NOT report`,
        `gaps if the audit is already complete against the rubric — an empty`,
        `gaps array is the correct output when the round has converged.`,
        '',
        `For each gap, include a suggested_action naming the specific judge`,
        `to re-run or the file to sample. The workflow uses these to drive`,
        `the next audit round.`,
        '',
        `Return CRITIC_SCHEMA (an object with a "gaps" array).`,
      ].join('\n'),
      { label: `critic round ${round}`, phase: 'Critique', schema: CRITIC_SCHEMA },
    )

    if (!critique || !critique.gaps || critique.gaps.length === 0) {
      log(`Critique round ${round}: no gaps (converged)`)
      break
    }

    log(`Critique round ${round}: ${critique.gaps.length} gap(s) surfaced`)

    // Resolve gaps to concrete follow-up judge invocations. This is
    // conservative — only unjudged_criterion gaps trigger a new judge
    // spawn today. unverified_claim / unread_source / missing_modality
    // gaps land in the plan file's Confidence section instead of triggering
    // another automated round, because their remediation is harder to
    // encode as a deterministic follow-up (T-25 handles that pass-through).
    const followupJudges = critique.gaps
      .filter((g) => g.type === 'unjudged_criterion')
      .map((g) => {
        // Extract the A-criterion id from the description. Format contract:
        // descriptions of this type should contain the criterion id verbatim.
        const m = g.description.match(/\b(A0[1-8])\b/)
        return m ? m[1] : null
      })
      .filter((j) => j && j in JUDGE_IMPLEMENTATIONS && !criteriaJudged.has(j))

    if (followupJudges.length === 0) {
      // The critic surfaced gaps but none translate to a re-runnable
      // criterion. Attach them to findings for the synthesizer to name
      // in Confidence, then exit the loop — running another critic pass
      // won't help.
      findingsAfterCritic = findingsAfterCritic.concat(
        critique.gaps.map((g) => ({
          criterion: '__CRITIC__',
          score: null,
          evidence: [g.description],
          gap: g.description,
          remediation: g.suggested_action,
          degraded: true,
          dimension_specific: { critic_gap_type: g.type, critic_round: round },
        })),
      )
      log(`Critique round ${round}: gaps do not resolve to unjudged criteria; folding into synthesis`)
      break
    }

    log(`Critique round ${round}: spawning follow-up judges: ${followupJudges.join(', ')}`)

    const followupFindings = (
      await parallel(
        followupJudges.map((j) => () =>
          JUDGE_IMPLEMENTATIONS[j]({ target: TARGET, det: deterministic, kitDir: KIT_DIR }),
        ),
      )
    ).filter(Boolean)

    // Mark these as critic-follow-ups.
    for (const f of followupFindings) {
      f.critic = { round, spawned_by_critic: true }
      criteriaJudged.add(f.criterion)
    }

    // Verify the new findings too, using the same verifier count.
    const verifiedFollowups = (
      await parallel(followupFindings.map((f) => () => verifyFinding(f, CONFIG.verifiers)))
    ).filter((f) => !f.verify?.majority_refuted)

    findingsAfterCritic = findingsAfterCritic.concat(verifiedFollowups)
  }
} else {
  log('Critique phase off (not thorough depth)')
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

// ─────────────────────────────────────────────────────────────────────────
// Compute derived signals the synthesizer references. Doing this in code
// (not asking the subagent to compute) avoids the class of bugs where the
// subagent miscounts because it read a small subset of the findings.
// ─────────────────────────────────────────────────────────────────────────

// Deterministic through-line mapping — matches references/ai-native-checklist.md.
// Kept inline so the synthesizer prompt is self-contained. The one place this
// list appears alongside the checklist is here; if the rubric adds a criterion,
// update both this map and the checklist file in the same PR.
const D_THROUGHLINE = {
  D01: 'Explicit over implicit',
  D02: 'Explicit over implicit',
  D03: 'Explicit over implicit',
  D04: 'Stable context anchors',
  D05: 'Stable context anchors',
  D06: 'Verification at every level',
  D07: 'Explicit over implicit',
  D08: 'Structured artifacts',
  D09: 'Structured artifacts',
  D10: 'Verification at every level',
  D11: 'Verification at every level',
  D12: 'Verification at every level',
  D13: 'Verification at every level',
  D14: 'Verification at every level',
  D15: 'Explicit over implicit',
  D16: 'Verification at every level',
  D17: 'Explicit over implicit',
  D18: 'Verification at every level',
}
const A_THROUGHLINE = {
  A01: 'Explicit over implicit',
  A02: 'Explicit over implicit',
  A03: 'Explicit over implicit',
  A04: 'Verification at every level',
  A05: 'Structured artifacts',
  A06: 'Structured artifacts',
  A07: 'Verification at every level',
  A08: 'varies (see A08 finding notes)',
}

// Degraded-layer signals the synthesizer will name in Confidence. Compute
// them here rather than trusting the subagent to grep across findings.
const degradedLayers = []
if (skippedJudges.length > 0) {
  degradedLayers.push(`judges not implemented this run: ${skippedJudges.join(', ')}`)
}
if (CONFIG.verifiers === 0 && CONFIG.judges.length > 0) {
  degradedLayers.push('adversarial verify off (depth=light) — findings are pre-verification')
}
if (!CONFIG.critic && CONFIG.judges.length > 0) {
  degradedLayers.push('completeness critic off — audit did not check itself for gaps')
}
if (findingsAfterCritic.some((f) => f.degraded === true)) {
  const degradedCriteria = findingsAfterCritic
    .filter((f) => f.degraded === true)
    .map((f) => f.criterion)
    .join(', ')
  degradedLayers.push(`degraded findings from: ${degradedCriteria}`)
}

// Deterministic score-summary strings the synthesizer can use verbatim.
const detSummaryStr = `${deterministic.summary.pass} pass · ${deterministic.summary.partial} partial · ${deterministic.summary.fail} fail · ${deterministic.summary.na} n/a`
const scoredFindings = findingsAfterCritic.filter((f) => typeof f.score === 'number')
const agenticAvg =
  scoredFindings.length > 0
    ? (scoredFindings.reduce((a, f) => a + f.score, 0) / scoredFindings.length).toFixed(1)
    : 'n/a'
const agenticSummaryStr =
  scoredFindings.length > 0
    ? `${scoredFindings.length} judge(s), avg score ${agenticAvg}/3`
    : 'n/a (no scored judges ran)'

const synthesisPrompt = [
  `You are the synthesizer for the ai-native-migration-kit audit workflow.`,
  ``,
  `Your job is to write a plan file to disk AND return a JSON summary.`,
  `You are a WRITER agent — use Read, Bash, and Write freely. Do NOT modify`,
  `any source file in the target repo; the plan file at docs/plans/ is the`,
  `only file you may create.`,
  ``,
  `───────────────────────────────────────────────────────────────────`,
  `INPUTS`,
  `───────────────────────────────────────────────────────────────────`,
  ``,
  `  target repo:              ${TARGET}`,
  `  audit date (ISO):         ${DATE}`,
  `  depth:                    ${CONFIG.name}`,
  `  judges configured:        ${CONFIG.judges.join(', ') || '(none)'}`,
  `  judges skipped (unimpl):  ${skippedJudges.join(', ') || '(none)'}`,
  `  verifiers per finding:    ${CONFIG.verifiers}`,
  `  critic enabled:           ${CONFIG.critic ? 'yes' : 'no'}`,
  `  deterministic summary:    ${detSummaryStr}`,
  `  agentic summary:          ${agenticSummaryStr}`,
  `  degraded layers:          ${degradedLayers.length > 0 ? degradedLayers.join('; ') : '(none)'}`,
  ``,
  `Deterministic scorecard (full JSON, one entry per D01–D18):`,
  '```json',
  JSON.stringify(deterministic, null, 2),
  '```',
  ``,
  `Agentic findings (${findingsAfterCritic.length} — includes __CRITIC__ pseudo-findings`,
  ` from the completeness critic if any surfaced non-runnable gaps):`,
  '```json',
  JSON.stringify(findingsAfterCritic, null, 2),
  '```',
  ``,
  `Through-line mapping for D-criteria (canonical, do not restate elsewhere):`,
  '```json',
  JSON.stringify(D_THROUGHLINE, null, 2),
  '```',
  ``,
  `Through-line mapping for A-criteria:`,
  '```json',
  JSON.stringify(A_THROUGHLINE, null, 2),
  '```',
  ``,
  `───────────────────────────────────────────────────────────────────`,
  `INSTRUCTIONS`,
  `───────────────────────────────────────────────────────────────────`,
  ``,
  `1. Write a Markdown plan file to:`,
  ``,
  `     ${TARGET}/docs/plans/ai-native-migration-${DATE}.md`,
  ``,
  `   Create the docs/plans/ directory if it does not exist. If a file`,
  `   with that exact name already exists, append -2, -3, ... to the`,
  `   filename before writing (do NOT overwrite existing plans).`,
  ``,
  `2. Plan file structure (write EXACTLY these top-level headings, in this`,
  `   order — the format is contractual):`,
  ``,
  `     # AI-Native Migration Plan — <repo basename from ${TARGET}>`,
  ``,
  `     **Generated:** ${DATE}  `,
  `     **Depth:** ${CONFIG.name}  `,
  `     **Stack detected:** ${deterministic.stack.stack}${deterministic.stack.framework ? \` (\${deterministic.stack.framework})\` : ''}  `,
  `     **Overall score:** ${detSummaryStr} (deterministic) · ${agenticSummaryStr} (agentic)`,
  ``,
  `     ## Executive summary`,
  ``,
  `     3–5 sentences: what's strong (name the through-lines the target`,
  `     scores well on), what's missing (the biggest gaps), what the`,
  `     highest-risk items are (rank by criterion severity — governance`,
  `     and testing gaps outrank cosmetic ones).`,
  ``,
  `     ## Findings by through-line`,
  ``,
  `     Four sub-sections, one per through-line, IN THIS ORDER:`,
  `       1. Explicit over implicit`,
  `       2. Verification at every level`,
  `       3. Structured artifacts`,
  `       4. Stable context anchors`,
  ``,
  `     Under each, list ONLY the findings whose criterion maps to that`,
  `     through-line via the mapping above. Skip through-lines with no`,
  `     findings entirely — do not emit "no findings" headers.`,
  ``,
  `     For each finding, use this exact format:`,
  ``,
  `       - **[<criterion>]** <one-line summary> — verdict/score`,
  `         - **Evidence:** <exact quote from the audit>`,
  `         - **Recommendation:** <specific action tied to a template or command>`,
  `         - **Source:** \`rubric §Part 1 <id>\` OR \`rubric §Part 2 <id>\``,
  `         - **Trace:** verify: <ran>/<ran> survived (or "skipped: <reason>"),`,
  `           critic: <round N | not applicable>`,
  `         - **Task:** T-<NN>  (assign sequential IDs across the whole plan)`,
  ``,
  `     Include ONLY findings that need action — a D-criterion with verdict`,
  `     "pass" or an A-criterion with score 3 and no gap has nothing to`,
  `     report here. D-criteria with verdict "n/a" go in the Confidence`,
  `     section, not here.`,
  ``,
  `     For A08 findings marked degraded=true, add a bold note at the end`,
  `     of the Recommendation: "**(A08 degraded — context7 unavailable`,
  `     during audit)**".`,
  ``,
  `     For findings with critic:{round:N} metadata, include "critic: round N"`,
  `     in the Trace line so the reader sees they came from a completeness`,
  `     loop, not a first-pass judge.`,
  ``,
  `     ## Task list (PR-sized)`,
  ``,
  `     Flat checkbox list, one line per T-NN task from the findings above.`,
  `     Include a rough estimate in parentheses: 15m / 30m / 1h / 2h+.`,
  ``,
  `       - [ ] **T-01** — <one-line title from the finding> (est: <estimate>)`,
  `       - [ ] **T-02** — …`,
  ``,
  `     Order tasks by CRITERION SEVERITY, not by through-line — the reader`,
  `     wants the highest-impact fixes at the top. Suggested severity`,
  `     ranking: governance (D03, A02, A03) > testing (D10-D12, A04) >`,
  `     context (D01, D02, A01) > docs (D08, A05, A06) > everything else.`,
  ``,
  `     ## Suggested sequencing`,
  ``,
  `     A short prose paragraph or numbered list explaining which tasks`,
  `     unlock which. Specifically:`,
  `       - D18 fails → do D06 first (fail cascade from the rubric).`,
  `       - A03 requires A02 (governance section) AND D03 (settings.json)`,
  `         to be at score 3 first.`,
  `       - Templates in plugins/ai-native-migration/templates/ resolve most D-criteria with one`,
  `         PR each; group them if the target is willing to accept 3+`,
  `         templates at once.`,
  ``,
  `     ## Human-decision points`,
  ``,
  `     List any tasks that require a human call before an agent can proceed.`,
  `     Common examples (include only if surfaced by the findings):`,
  `       - Governance policy (which paths belong on the do-not-modify list?`,
  `         which commands MUST run before commit?)`,
  `       - License / IP for adopted templates`,
  `       - Team decisions on which AI review layer to enable (D14)`,
  `       - Which framework version to target if A08 conflicts with the`,
  `         version detected`,
  ``,
  `     ## Confidence`,
  ``,
  `     What could NOT be evaluated, in prose. Include ALL of:`,
  `       - Any judges skipped: ${skippedJudges.join(', ') || 'none'}`,
  `       - Verify status: ${CONFIG.verifiers === 0 ? 'off (depth=light)' : CONFIG.verifiers + ' verifier(s) per finding'}`,
  `       - Critic status: ${CONFIG.critic ? 'on, up to ' + CONFIG.criticMaxRounds + ' rounds' : 'off'}`,
  `       - Any A08 finding with degraded=true → note context7 was unavailable`,
  `       - Any deterministic criteria with verdict "n/a" — list them with`,
  `         their evidence (this is where the reader learns what the audit`,
  `         legitimately skipped, e.g., D18 n/a when D06 fails)`,
  ``,
  `───────────────────────────────────────────────────────────────────`,
  `INVARIANTS (non-negotiable)`,
  `───────────────────────────────────────────────────────────────────`,
  ``,
  ` A. EVERY recommendation MUST carry a Source citation of the form`,
  `    \`rubric §Part 1 D<NN>\` or \`rubric §Part 2 A<NN>\`. No exceptions.`,
  ` B. Zero citations to any external curriculum, training program, or`,
  `    reference repository. Rubric §Part 1/§Part 2 is the ONLY citation`,
  `    source. See docs/specs/01-initial-design/01-questions-1-*.md Q-07.`,
  ` C. Do NOT overwrite an existing plan file — append -2, -3, ... to`,
  `    the filename instead.`,
  ` D. Do NOT modify any source file in the target repo. The plan file`,
  `    is the only artifact you create.`,
  ` E. If a finding lacks evidence, DROP it from the plan silently. Do`,
  `    not emit uncited claims — the whole point of adversarial verify`,
  `    is to filter these out; anything that leaks through is a bug in`,
  `    the caller's context.`,
  ``,
  `───────────────────────────────────────────────────────────────────`,
  `RETURN VALUE`,
  `───────────────────────────────────────────────────────────────────`,
  ``,
  `Return a JSON object matching the synthesis schema:`,
  `  - plan_file_path: absolute path of the file you just wrote (must`,
  `                    exist on disk when the workflow returns)`,
  `  - overall_score: {`,
  `      deterministic: "${detSummaryStr}",`,
  `      agentic:       "${agenticSummaryStr}"`,
  `    }`,
  `  - top_findings: up to 5 one-line strings for the highest-severity`,
  `                  gaps (governance/testing/context first)`,
  `  - degraded_layers: exactly this array, verbatim if non-empty:`,
  `                     ${JSON.stringify(degradedLayers)}`,
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

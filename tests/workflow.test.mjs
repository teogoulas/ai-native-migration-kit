// tests/workflow.test.mjs — unit tests for the workflow's pure logic.
//
// The workflow file (skill/workflows/ai-native-audit.js) executes inside
// the Claude Code Workflow runtime, so we can't run it end-to-end with
// plain node. But its pure logic — depth resolution, through-line
// mapping, degraded-layer computation — is testable in isolation.
//
// This harness extracts those pure functions/constants from the workflow
// source, evaluates them in a sandbox that stubs the Workflow-runtime
// primitives (agent/parallel/phase/log/args), and runs assertions.
//
// Zero deps beyond node. Run: node tests/workflow.test.mjs

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import vm from 'node:vm'

const HERE = dirname(fileURLToPath(import.meta.url))
const KIT_ROOT = join(HERE, '..')
const WORKFLOW_SRC = readFileSync(join(KIT_ROOT, 'skill/workflows/ai-native-audit.js'), 'utf8')

// ─────────────────────────────────────────────────────────────────────────
// Test framework — same shape as tests/verify.test.sh
// ─────────────────────────────────────────────────────────────────────────

let PASS = 0
let FAIL = 0
const FAIL_NAMES = []

const isTTY = process.stdout.isTTY
const green = isTTY ? '\x1b[32m' : ''
const red = isTTY ? '\x1b[31m' : ''
const gray = isTTY ? '\x1b[90m' : ''
const bold = isTTY ? '\x1b[1m' : ''
const reset = isTTY ? '\x1b[0m' : ''

function pass(msg) {
  PASS++
  console.log(`  ${green}✓${reset} ${msg}`)
}
function fail(msg, expected, actual) {
  FAIL++
  FAIL_NAMES.push(msg)
  console.log(`  ${red}✗${reset} ${msg}`)
  console.log(`    ${gray}expected:${reset} ${JSON.stringify(expected)}`)
  console.log(`    ${gray}actual:  ${reset} ${JSON.stringify(actual)}`)
}
function assertEq(label, expected, actual) {
  if (JSON.stringify(expected) === JSON.stringify(actual)) {
    pass(label)
  } else {
    fail(label, expected, actual)
  }
}
function section(name) {
  console.log(`\n${bold}${name}${reset}`)
}

// ─────────────────────────────────────────────────────────────────────────
// Extract the workflow's pure logic (before any top-level await / phase()
// call) by evaluating the file up to a sentinel and pulling globals out.
// We do this rather than parsing to keep the tests coupled to what the
// workflow actually runs — if the source drifts, the tests drift with it.
// ─────────────────────────────────────────────────────────────────────────

function makeContext(argsOverride) {
  const captured = {}
  const context = {
    // Workflow runtime stubs — return no-op values so pure logic runs
    // and top-level async calls are effectively skipped.
    async agent() {
      return null
    },
    async parallel(items) {
      // Execute thunks like the real runtime would, but each returns null.
      const results = await Promise.all(items.map((thunk) => thunk()))
      return results
    },
    async pipeline() {
      return []
    },
    phase() {},
    log() {},
    args: argsOverride,
    budget: { total: null, spent: () => 0, remaining: () => Infinity },
    workflow: async () => null,
    console: { log: () => {}, error: () => {}, warn: () => {} },
    JSON,
    Math,
    Array,
    Object,
    String,
    Number,
    Boolean,
    Promise,
    // Capture selected globals as the workflow evaluates.
    __capture: captured,
  }
  vm.createContext(context)
  return { context, captured }
}

// Extract only the top-of-file pure logic — everything up to the first
// `phase(` invocation (which is where side effects begin). This gives
// us DEPTH_PRESETS + resolveDepth + CONFIG + JUDGE_PREAMBLE + the schemas
// without triggering the deterministic-audit agent() call.
//
// vm.runInContext requires plain-script syntax (no ESM `export`), so we
// strip the leading `export ` keyword from the `export const meta = {...}`
// declaration. The `meta` const still binds in the sandbox — we just
// can't ES-export it.
function extractPreLogic(source) {
  const marker = source.indexOf("phase('Deterministic')")
  if (marker < 0) throw new Error('Could not find pre-phase marker in workflow source')
  return source.slice(0, marker).replace(/^export\s+/gm, '')
}

// Extract the through-line maps + degraded-layer computation from the
// synthesis prep block. These sit between "Compute derived signals" and
// the const synthesisPrompt =
function extractSynthesisPrep(source) {
  const start = source.indexOf('const D_THROUGHLINE')
  const end = source.indexOf('const synthesisPrompt')
  if (start < 0 || end < 0) throw new Error('Could not locate synthesis-prep block')
  return source.slice(start, end)
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

section('resolveDepth — presets')
{
  const preLogic = extractPreLogic(WORKFLOW_SRC)
  // Evaluate the pre-logic with a valid args object; extract DEPTH_PRESETS
  // and the resolveDepth function via the __capture object we hand back.
  const capture = `
    __capture.DEPTH_PRESETS = DEPTH_PRESETS;
    __capture.resolveDepth = resolveDepth;
  `
  const { context } = makeContext({ target: '/tmp', date: '2026-07-08', kitDir: '/kit', depth: 'standard' })
  vm.runInContext(preLogic + '\n' + capture, context, { timeout: 5000 })
  const { DEPTH_PRESETS, resolveDepth } = context.__capture

  const light = resolveDepth({ depth: 'light' })
  assertEq('light: judges', ['A01', 'A04', 'A05'], light.judges)
  assertEq('light: verifiers', 0, light.verifiers)
  assertEq('light: critic', false, light.critic)

  const standard = resolveDepth({ depth: 'standard' })
  assertEq('standard: judges', ['A01', 'A02', 'A04', 'A05', 'A06'], standard.judges)
  assertEq('standard: verifiers', 1, standard.verifiers)
  assertEq('standard: critic', false, standard.critic)

  const thorough = resolveDepth({ depth: 'thorough' })
  assertEq('thorough: all 8 judges', ['A01', 'A02', 'A03', 'A04', 'A05', 'A06', 'A07', 'A08'], thorough.judges)
  assertEq('thorough: verifiers', 3, thorough.verifiers)
  assertEq('thorough: critic', true, thorough.critic)
  assertEq('thorough: criticMaxRounds', 2, thorough.criticMaxRounds)

  const defaultDepth = resolveDepth({})
  assertEq('no depth argument defaults to standard', 'standard', defaultDepth.name)
}

section('resolveDepth — custom overrides')
{
  const preLogic = extractPreLogic(WORKFLOW_SRC)
  const capture = `__capture.resolveDepth = resolveDepth;`
  const { context } = makeContext({ target: '/tmp', date: '2026-07-08', kitDir: '/kit', depth: 'standard' })
  vm.runInContext(preLogic + '\n' + capture, context)
  const { resolveDepth } = context.__capture

  const custom1 = resolveDepth({ depth: 'custom', judges: ['A01'], verify: 2, critic: 'on' })
  assertEq('custom: named judges', ['A01'], custom1.judges)
  assertEq('custom: verifiers = 2', 2, custom1.verifiers)
  assertEq('custom: critic = on', true, custom1.critic)
  assertEq('custom: criticMaxRounds when critic on', 2, custom1.criticMaxRounds)

  const custom2 = resolveDepth({ depth: 'custom', judges: ['A03', 'A08'], verify: 0, critic: 'off' })
  assertEq('custom: two specific judges', ['A03', 'A08'], custom2.judges)
  assertEq('custom: verifiers = 0', 0, custom2.verifiers)
  assertEq('custom: critic = off', false, custom2.critic)
  assertEq('custom: criticMaxRounds when critic off', 0, custom2.criticMaxRounds)
}

section('resolveDepth — validation errors')
{
  const preLogic = extractPreLogic(WORKFLOW_SRC)
  const capture = `__capture.resolveDepth = resolveDepth;`
  const { context } = makeContext({ target: '/tmp', date: '2026-07-08', kitDir: '/kit', depth: 'standard' })
  vm.runInContext(preLogic + '\n' + capture, context)
  const { resolveDepth } = context.__capture

  let threw = false
  try {
    resolveDepth({ depth: 'zealous' })
  } catch (e) {
    threw = true
    assertEq('unknown depth error names valid options', true, /light, standard, thorough, custom/.test(e.message))
  }
  assertEq('unknown depth throws', true, threw)

  let threw2 = false
  try {
    resolveDepth({ depth: 'custom', judges: ['A01', 'A99'] })
  } catch (e) {
    threw2 = true
    assertEq('unknown judge id error names it', true, /A99/.test(e.message))
  }
  assertEq('unknown judge id throws', true, threw2)
}

section('through-line mappings — completeness')
{
  const prepBlock = extractSynthesisPrep(WORKFLOW_SRC)
  const capture = `
    __capture.D_THROUGHLINE = D_THROUGHLINE;
    __capture.A_THROUGHLINE = A_THROUGHLINE;
  `
  const { context } = makeContext({})
  // Provide the minimum context vars the prep block references.
  const stubVars = `
    const skippedJudges = [];
    const CONFIG = { verifiers: 0, judges: [], critic: false, criticMaxRounds: 0 };
    const findingsAfterCritic = [];
    const deterministic = { summary: { pass: 0, partial: 0, fail: 0, na: 0 } };
  `
  vm.runInContext(stubVars + '\n' + prepBlock + '\n' + capture, context)
  const { D_THROUGHLINE, A_THROUGHLINE } = context.__capture

  const validThroughLines = new Set([
    'Explicit over implicit',
    'Verification at every level',
    'Structured artifacts',
    'Stable context anchors',
    'varies (see A08 finding notes)',
  ])

  // Every D01-D18 mapped
  const expectedD = Array.from({ length: 18 }, (_, i) => 'D' + String(i + 1).padStart(2, '0'))
  const missingD = expectedD.filter((id) => !(id in D_THROUGHLINE))
  assertEq('D_THROUGHLINE covers D01-D18', [], missingD)
  for (const id of expectedD) {
    const line = D_THROUGHLINE[id]
    if (!validThroughLines.has(line)) {
      fail(`${id} → ${line} (unknown through-line)`, [...validThroughLines], line)
    }
  }

  // Every A01-A08 mapped
  const expectedA = Array.from({ length: 8 }, (_, i) => 'A0' + (i + 1))
  const missingA = expectedA.filter((id) => !(id in A_THROUGHLINE))
  assertEq('A_THROUGHLINE covers A01-A08', [], missingA)
  for (const id of expectedA) {
    const line = A_THROUGHLINE[id]
    if (!validThroughLines.has(line)) {
      fail(`${id} → ${line} (unknown through-line)`, [...validThroughLines], line)
    }
  }
}

section('degradedLayers computation')
{
  const prepBlock = extractSynthesisPrep(WORKFLOW_SRC)
  const capture = `__capture.degradedLayers = degradedLayers;`

  // Scenario 1: light depth with unimplemented judges — degraded_layers
  // should mention skipped judges AND verify-off.
  {
    const { context } = makeContext({})
    const stubVars = `
      const skippedJudges = ['A99'];
      const CONFIG = { verifiers: 0, judges: ['A01'], critic: false, criticMaxRounds: 0 };
      const findingsAfterCritic = [];
      const deterministic = { summary: { pass: 0, partial: 0, fail: 0, na: 0 } };
    `
    vm.runInContext(stubVars + '\n' + prepBlock + '\n' + capture, context)
    const { degradedLayers } = context.__capture
    const flags = degradedLayers.join(' | ')
    assertEq('degradedLayers: mentions skipped judge', true, /A99/.test(flags))
    assertEq('degradedLayers: mentions verify-off', true, /verify off/.test(flags))
  }

  // Scenario 2: thorough depth, no skipped, all clean — degraded_layers
  // should be empty.
  {
    const { context } = makeContext({})
    const stubVars = `
      const skippedJudges = [];
      const CONFIG = { verifiers: 3, judges: ['A01', 'A02'], critic: true, criticMaxRounds: 2 };
      const findingsAfterCritic = [{criterion: 'A01', score: 3, degraded: false}];
      const deterministic = { summary: { pass: 18, partial: 0, fail: 0, na: 0 } };
    `
    vm.runInContext(stubVars + '\n' + prepBlock + '\n' + capture, context)
    const { degradedLayers } = context.__capture
    assertEq('degradedLayers: empty on clean thorough run', [], degradedLayers)
  }

  // Scenario 3: degraded A08 finding — should surface in degradedLayers.
  {
    const { context } = makeContext({})
    const stubVars = `
      const skippedJudges = [];
      const CONFIG = { verifiers: 3, judges: ['A08'], critic: true, criticMaxRounds: 2 };
      const findingsAfterCritic = [{criterion: 'A08', score: 2, degraded: true}];
      const deterministic = { summary: { pass: 18, partial: 0, fail: 0, na: 0 } };
    `
    vm.runInContext(stubVars + '\n' + prepBlock + '\n' + capture, context)
    const { degradedLayers } = context.__capture
    assertEq('degradedLayers: mentions degraded A08', true, degradedLayers.some((l) => /A08/.test(l)))
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Report
// ─────────────────────────────────────────────────────────────────────────

console.log(`\n${bold}results${reset}  `)
if (FAIL === 0) {
  console.log(`${green}${PASS} passed${reset}`)
  process.exit(0)
}
console.log(`${green}${PASS} passed${reset}, ${red}${FAIL} failed${reset}`)
console.log('failed:')
for (const n of FAIL_NAMES) console.log(`  - ${n}`)
process.exit(1)

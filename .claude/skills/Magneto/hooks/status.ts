// Pure parsing and formatting, no `$`: the hooks module feeds them what it read.
import { simpleCommands, words } from './shell'

export type Outcome = { isOk: boolean; at: number }
export type BuildOutcome = Outcome & { warnings?: number }
export type TestOutcome = Outcome & { total?: number }

// What the status line remembers per repository, across sessions.
export type Record = { mac?: BuildOutcome; ios?: BuildOutcome; tests?: TestOutcome }

export type Install =
  | { kind: 'missing' }
  | { kind: 'fresh' }
  | { kind: 'stale'; newer: number }

export type Signature = 'team' | 'adhoc' | 'unknown'

// `isQuiet`: xcodebuild's -quiet prints warnings and errors only, no verdict.
// `derived`: its -derivedDataPath as written, where the test results land.
export type Job = { kind: 'build' | 'test' | 'install'; scheme: string; isQuiet?: boolean; derived?: string }

// The builds and test runs a command starts for `app`: its xcodebuild calls by
// scheme and action, and the repository's own scripts.
export function jobs(command: string, app: string): Job[] {
  const found: Job[] = []
  for (const simple of simpleCommands(command)) {
    const w = words(simple)
    const script = w[0]?.match(/(^|\/)scripts\/(install|dev)\.sh$/)?.[2]
    if (script === 'install') found.push({ kind: 'install', scheme: app })
    if (script === 'dev') found.push({ kind: 'build', scheme: app })
    if (w[0] !== 'xcodebuild') continue
    const at = w.indexOf('-scheme')
    const scheme = (at === -1 ? undefined : w[at + 1])?.replace(/^["']|["']$/g, '')
    if (scheme === undefined) continue
    const kind = w.includes('test') ? 'test' : 'build'
    const derivedAt = w.indexOf('-derivedDataPath')
    const derived = derivedAt === -1 ? undefined : w[derivedAt + 1]
    found.push({
      kind,
      scheme,
      ...(w.includes('-quiet') ? { isQuiet: true } : {}),
      ...(derived === undefined ? {} : { derived }),
    })
  }
  return found
}

// `true` or `false` once xcodebuild printed its verdict, else undefined. A
// quiet build prints none: it passed when it exited cleanly with no `error:`.
export function buildVerdict(output: string, isQuiet = false, hasFailed = false): boolean | undefined {
  if (/\*\* BUILD FAILED \*\*/.test(output)) return false
  if (/\*\* BUILD SUCCEEDED \*\*/.test(output)) return true
  if (hasFailed) return false
  if (isQuiet) return !/^.*\berror: /m.test(output)
  return undefined
}

// The distinct warnings of a build, counted only when the output is whole (a
// quiet build's always is): a `| tail` drops them, and an unknown count must
// not read as zero.
export function warningCount(output: string, isQuiet = false): number | undefined {
  if (!isQuiet && !output.includes('Command line invocation:')) return undefined
  const lines = output.match(/^.*\bwarning: .*$/gm) ?? []
  return new Set(lines.map(l => l.trim())).size
}

// The summary of a test result bundle (`xcresulttool get test-results summary`),
// when it finished after `startedAt`: an older bundle is another run's.
export function xcresultOutcome(json: string, startedAt: number): { isOk: boolean; total: number } | undefined {
  try {
    const summary: unknown = JSON.parse(json)
    if (typeof summary !== 'object' || summary === null) return undefined
    const { result, totalTestCount, finishTime } = summary as { result?: unknown; totalTestCount?: unknown; finishTime?: unknown }
    if (typeof finishTime !== 'number' || finishTime * 1000 < startedAt) return undefined
    if (typeof totalTestCount !== 'number' || (result !== 'Passed' && result !== 'Failed')) return undefined
    return { isOk: result === 'Passed', total: totalTestCount }
  } catch {
    return undefined
  }
}

// Swift Testing's own count, the "Test run with N tests" line, and the verdict.
export function testOutcome(output: string): { isOk?: boolean; total?: number } {
  const runs = [...output.matchAll(/Test run with (\d+) tests?(?: in \d+ suites?)? (passed|failed)/g)]
  const last = runs[runs.length - 1]
  if (last) return { isOk: last[2] === 'passed', total: Number(last[1]) }
  if (/\*\* TEST FAILED \*\*/.test(output)) return { isOk: false }
  if (/\*\* TEST SUCCEEDED \*\*/.test(output)) return { isOk: true }
  return {}
}

export function signatureOf(requirement: string): Signature {
  if (/\bcdhash\b/.test(requirement)) return 'adhoc'
  if (/subject\.OU/.test(requirement)) return 'team'
  return 'unknown'
}

const plural = (n: number, word: string) => `${n} ${word}${n > 1 ? 's' : ''}`

// Each item reads `Label ✓` or `Label ✗`, a detail in parentheses when there
// is one; an item nothing is known about yet is left out rather than shown as `?`.
function build(label: string, b: BuildOutcome | undefined): string | undefined {
  if (b === undefined) return undefined
  if (!b.isOk) return `${label} ✗`
  return b.warnings ? `${label} ✓ (${plural(b.warnings, 'warning')})` : `${label} ✓`
}

// The line under the prompt, in the French of the apps' own interface. The
// app's name is the plugin's, which the status line already shows before it.
export function statusLine(record: Record, install: Install, signature: Signature): string {
  const t = record.tests
  const parts = [
    build('Build', record.mac),
    build('iOS', record.ios),
    t === undefined ? undefined : `Tests ${t.isOk ? '✓' : '✗'}${t.total === undefined ? '' : ` (${t.total})`}`,
    install.kind === 'missing'
      ? 'Non installé'
      : install.kind === 'fresh'
        ? 'Installé ✓'
        : `Installé ✗ (${install.newer} ${install.newer > 1 ? 'fichiers modifiés' : 'fichier modifié'} depuis)`,
    signature === 'team' ? 'Signature ✓' : signature === 'adhoc' ? 'Signature ✗ (ad hoc)' : undefined,
  ]
  return parts.filter(p => p !== undefined).join(' · ')
}

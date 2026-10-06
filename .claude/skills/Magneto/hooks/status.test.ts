import { expect, test } from 'claude-code/testing'
import { buildVerdict, jobs, signatureOf, statusLine, testOutcome, warningCount, xcresultOutcome } from './status'

test('the jobs of a command are its builds, test runs and scripts', () => {
  expect(jobs('xcodebuild -project Magneto.xcodeproj -scheme Magneto -configuration Debug build 2>&1 | tail -3', 'Magneto'))
    .toEqual([{ kind: 'build', scheme: 'Magneto' }])
  expect(jobs("xcodebuild test -project Magneto.xcodeproj -scheme Magneto -destination 'platform=macOS'", 'Magneto'))
    .toEqual([{ kind: 'test', scheme: 'Magneto' }])
  expect(jobs('./scripts/install.sh', 'Magneto')).toEqual([{ kind: 'install', scheme: 'Magneto' }])
  expect(jobs('xcodebuild -scheme MagnetoIOS -destination id=X build', 'Magneto'))
    .toEqual([{ kind: 'build', scheme: 'MagnetoIOS' }])
  expect(jobs('echo "xcodebuild -scheme Magneto build"', 'Magneto')).toEqual([])
  expect(jobs('git status', 'Magneto')).toEqual([])
})

test('a build verdict is read only once xcodebuild printed it', () => {
  expect(buildVerdict('...\n** BUILD SUCCEEDED **\n')).toBe(true)
  expect(buildVerdict('...\n** BUILD FAILED **\n')).toBe(false)
  expect(buildVerdict('Compiling...')).toBeUndefined()
  expect(buildVerdict('--- xcodebuild: WARNING: Using the first of multiple matching destinations', true)).toBe(true)
  expect(buildVerdict("/r/A.swift:3:1: error: cannot find 'x' in scope", true)).toBe(false)
  expect(buildVerdict('', true, true)).toBe(false)
})

test('a quiet build reports its options and its whole warnings', () => {
  expect(jobs('xcodebuild -scheme Magneto -quiet build', 'Magneto')).toEqual([{ kind: 'build', scheme: 'Magneto', isQuiet: true }])
  expect(warningCount('--- xcodebuild: WARNING: Using the first of multiple matching destinations', true)).toBe(0)
  expect(warningCount('/r/A.swift:3:1: warning: unused', true)).toBe(1)
})

test('warnings are counted only on a whole output, each once', () => {
  const whole = [
    'Command line invocation:',
    '/r/Magneto/AppState.swift:12:5: warning: variable was never mutated',
    '/r/Magneto/AppState.swift:12:5: warning: variable was never mutated',
    'ld: warning: duplicate library',
    '** BUILD SUCCEEDED **',
  ].join('\n')
  expect(warningCount(whole)).toBe(2)
  expect(warningCount('Command line invocation:\n** BUILD SUCCEEDED **')).toBe(0)
  expect(warningCount('** BUILD SUCCEEDED **')).toBeUndefined()
})

test('Swift Testing gives the count, xcodebuild the fallback verdict', () => {
  expect(testOutcome('✔ Test run with 42 tests in 7 suites passed after 0.3 seconds.')).toEqual({ isOk: true, total: 42 })
  expect(testOutcome('✘ Test run with 42 tests in 7 suites failed after 0.3 seconds with 2 issues.'))
    .toEqual({ isOk: false, total: 42 })
  expect(testOutcome('** TEST SUCCEEDED **')).toEqual({ isOk: true })
  expect(testOutcome('Executed 0 tests')).toEqual({})
})

test('a cdhash requirement is an ad hoc signature', () => {
  expect(signatureOf('designated => anchor apple generic and certificate leaf[subject.OU] = AQ7LZD44WD')).toBe('team')
  expect(signatureOf('designated => cdhash H"3f2a…"')).toBe('adhoc')
  expect(signatureOf('code object is not signed at all')).toBe('unknown')
})

test('the status line shows what is known and leaves out the rest', () => {
  expect(statusLine({}, { kind: 'missing' }, 'unknown')).toBe('Non installé')
  expect(statusLine({}, { kind: 'fresh' }, 'team')).toBe('Installé ✓ · Signature ✓')
  expect(statusLine(
    { mac: { isOk: true, at: 0, warnings: 0 }, ios: { isOk: false, at: 0 }, tests: { isOk: true, at: 0, total: 42 } },
    { kind: 'fresh' },
    'team',
  )).toBe('Build ✓ · iOS ✗ · Tests ✓ (42) · Installé ✓ · Signature ✓')
  expect(statusLine({ mac: { isOk: true, at: 0, warnings: 3 } }, { kind: 'stale', newer: 1 }, 'adhoc'))
    .toBe('Build ✓ (3 warnings) · Installé ✗ (1 fichier modifié depuis) · Signature ✗ (ad hoc)')
  expect(statusLine({ tests: { isOk: false, at: 0 } }, { kind: 'stale', newer: 2 }, 'team'))
    .toBe('Tests ✗ · Installé ✗ (2 fichiers modifiés depuis) · Signature ✓')
})

test('a result bundle gives the verdict and count of the run that wrote it', () => {
  const summary = (result: string, finishTime: number) =>
    JSON.stringify({ result, totalTestCount: 33, passedTests: 33, failedTests: 0, finishTime })
  expect(xcresultOutcome(summary('Passed', 2000), 1_000_000)).toEqual({ isOk: true, total: 33 })
  expect(xcresultOutcome(summary('Failed', 2000), 1_000_000)).toEqual({ isOk: false, total: 33 })
  expect(xcresultOutcome(summary('Passed', 999), 1_000_000)).toBeUndefined()
  expect(xcresultOutcome('not json', 0)).toBeUndefined()
  expect(jobs('xcodebuild test -scheme Magneto -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto -quiet', 'Magneto'))
    .toEqual([{ kind: 'test', scheme: 'Magneto', isQuiet: true, derived: '~/Library/Developer/Xcode/DerivedData/Magneto' }])
})

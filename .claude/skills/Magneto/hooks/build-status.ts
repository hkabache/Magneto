// The status line: last build, tests, install and signature of the app.
import type { EngineInterface, Register } from 'claude-code'
import { cdBefore, words } from './shell'
import {
  buildVerdict,
  jobs,
  type Install,
  type Record,
  type Signature,
  signatureOf,
  statusLine,
  testOutcome,
  warningCount,
  xcresultOutcome,
} from './status'

type Repo = { root: string; app: string }

async function sh($: EngineInterface, script: string, cwd?: string): Promise<string | undefined> {
  const { exitCode, stdout } = await $.process.run(['/bin/zsh', '-c', script], cwd === undefined ? {} : { cwd })
  return exitCode === 0 ? stdout.trim() : undefined
}

const quote = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`

// The repository the session runs in, named after its folder (Magneto, Mystique).
async function sessionRepo($: EngineInterface): Promise<Repo | undefined> {
  const root = await sh($, 'git rev-parse --show-toplevel', await $.session.cwd())
  return root ? { root, app: root.split('/').pop() ?? root } : undefined
}

async function loadRecord($: EngineInterface, repo: Repo): Promise<Record> {
  const stored = await $.store.get(repo.root)
  return typeof stored === 'object' && stored !== null ? (stored as Record) : {}
}

// Installed is fresh when no source of the Mac app changed after the binary
// in /Applications: the app's own folder, Shared/ and project.yml.
async function installState($: EngineInterface, repo: Repo): Promise<Install> {
  const binary = `/Applications/${repo.app}.app/Contents/MacOS/${repo.app}`
  const sources = [repo.app, 'Shared', 'project.yml'].map(quote).join(' ')
  const out = await sh(
    $,
    `[ -f ${quote(binary)} ] || { echo missing; exit 0; }; ` +
      `find ${sources} -newer ${quote(binary)} -type f ! -name .DS_Store 2>/dev/null | wc -l`,
    repo.root,
  )
  if (out === 'missing') return { kind: 'missing' }
  const newer = Number(out ?? '0')
  return newer > 0 ? { kind: 'stale', newer } : { kind: 'fresh' }
}

async function signatureState($: EngineInterface, repo: Repo): Promise<Signature> {
  const out = await sh($, `codesign -d -r- ${quote(`/Applications/${repo.app}.app`)} 2>&1`)
  return out === undefined ? 'unknown' : signatureOf(out)
}

// Redraws the status line from the stored record and the installed app.
async function refresh($: EngineInterface, repo: Repo | undefined, isAfterInstall = false): Promise<void> {
  if (repo === undefined) return
  const [record, install, signature] = await Promise.all([
    loadRecord($, repo),
    installState($, repo),
    signatureState($, repo),
  ])
  if (isAfterInstall && signature === 'adhoc') {
    $.ui.toast(`${repo.app} signée ad hoc : micro et accessibilité sauteront au prochain build`)
  }
  $.ui.status(statusLine(record, install, signature))
}

// The outcome of the test run a command just made, read from the result bundle
// xcodebuild writes under its -derivedDataPath: whole whatever the output
// showed, -quiet and `| tail` included.
async function resultBundle(
  $: EngineInterface,
  repo: Repo,
  derived: string | undefined,
  startedAt: number,
): Promise<{ isOk: boolean; total: number } | undefined> {
  if (derived === undefined) return undefined
  const path = await sh($, `ls -td ${derived}/Logs/Test/*.xcresult 2>/dev/null | head -1`, repo.root)
  if (!path) return undefined
  const json = await sh($, `xcrun xcresulttool get test-results summary --path ${quote(path)} --compact`)
  return json === undefined ? undefined : xcresultOutcome(json, startedAt)
}

export const buildStatus: Register = on => {
  let repo: Repo | undefined

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    repo = await sessionRepo($)
    await refresh($, repo)
    return started
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const startedAt = Date.now()
    const ran = await next(e)
    if (repo === undefined || e.run_in_background === true || ran.deny !== undefined) return ran
    const current = repo
    const found = jobs(e.command, current.app)
    if (found.length === 0) return ran

    // A command that cds into another repository builds that one, not this one.
    const isBuildCall = (simple: string) => {
      const w = words(simple)
      return w[0] === 'xcodebuild' || /(^|\/)scripts\/(install|dev)\.sh$/.test(w[0] ?? '')
    }
    const dir = cdBefore(e.command, isBuildCall)
    if (dir !== undefined) {
      const root = await sh($, `cd ${dir} && git rev-parse --show-toplevel`, current.root)
      if (root !== current.root) return ran
    }

    const output = ran.text ?? ''
    const record = await loadRecord($, current)
    const at = Date.now()
    for (const job of found) {
      const isIos = job.scheme !== current.app && job.scheme.startsWith(current.app) && /ios/i.test(job.scheme)
      if (job.kind === 'test') {
        const { isOk, total } = (await resultBundle($, current, job.derived, startedAt)) ?? testOutcome(output)
        if (isOk !== undefined) record.tests = { isOk, at, ...(total === undefined ? {} : { total }) }
      } else if (job.scheme === current.app || isIos) {
        const verdict = buildVerdict(output, job.isQuiet, ran.isError === true)
        if (verdict === undefined) continue
        const warnings = warningCount(output, job.isQuiet)
        const outcome = { isOk: verdict, at, ...(warnings === undefined ? {} : { warnings }) }
        if (isIos) record.ios = outcome
        else record.mac = outcome
      }
    }
    await $.store.set(current.root, record)
    await refresh($, current, found.some(j => j.kind === 'install'))
    return ran
  })

  // An edited source makes the installed app stale until the next install.
  on('tool.call', { tool: ['Edit', 'Write'] }, async ($, e, next) => {
    const ran = await next(e)
    const path = e.tool === 'Edit' || e.tool === 'Write' ? e.file_path : ''
    if (repo !== undefined && path.startsWith(`${repo.root}/`)) await refresh($, repo)
    return ran
  })
}

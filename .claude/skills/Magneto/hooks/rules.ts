// Pure rules, no `$`: the hooks module feeds them what it read.

import { commandDir, gitCall, simpleCommands, words } from './shell'

export { commandDir }

// A derived data path that is neither absolute nor under ~ lands inside the
// repository, where Spotlight indexes the built .app copies as applications.
export function derivedDataInsideRepo(command: string): string | undefined {
  for (const simple of simpleCommands(command)) {
    const w = words(simple)
    if (w[0] !== 'xcodebuild') continue
    const at = w.indexOf('-derivedDataPath')
    const path = (at === -1 ? undefined : w[at + 1])?.replace(/^["']|["']$/g, '')
    if (path === undefined) continue
    const isOutside = /^(\/|~|\$HOME|\$\{HOME\})/.test(path)
    if (!isOutside) return path
  }
  return undefined
}

// The version a command tags or pushes as a release, `v1.2.3` -> `1.2.3`.
// Listing or deleting tags is no release.
export function releaseTag(command: string): string | undefined {
  for (const simple of simpleCommands(command)) {
    const git = gitCall(simple)
    if (git === undefined || (git.sub !== 'tag' && git.sub !== 'push')) continue
    if (git.args.some(a => ['-l', '--list', '-d', '--delete'].includes(a))) continue
    const version = git.args.map(a => a.match(/^v(\d+\.\d+\.\d+)$/)?.[1]).find(v => v !== undefined)
    if (version !== undefined) return version
  }
  return undefined
}

export function isCommitOrPush(command: string): boolean {
  return simpleCommands(command).some(simple => {
    const sub = gitCall(simple)?.sub
    return sub === 'commit' || sub === 'push'
  })
}

// The words of a request that allow a commit or a push, dictated or typed.
export function asksForCommit(prompt: string): boolean {
  return /\b(commit\w*|committ\w*|push\w*|pousse[rsz]?|publie[rsz]?|tag\w*)\b/i.test(prompt)
}

// An answer that offers a commit, a push or a tag and ends on a question,
// unlike one that only reports that nothing was committed.
export function proposesCommit(answer: string): boolean {
  return asksForCommit(answer) && /\?[\s*_»"')]*$/.test(answer.trim())
}

// A short agreement with no reservation: « oui va y », « ok », « go ». It
// allows a commit when Claude's previous answer proposed one.
export function isAgreement(prompt: string): boolean {
  const text = prompt.trim()
  if (text.length > 80 || /\b(non|pas|attends?|stop|sauf)\b/i.test(text)) return false
  return /^(oui|ouais|ok|okay|d'accord|dac|vas?[- ]?y|go|yes|yep|parfait|c'est bon|valid[eé]|je valide|fais[- ]le|lance)\b/i.test(text)
}

export type ReleaseFiles = { projectYml: string; changelog: string; recette?: string }

// What is missing before tagging `version`, empty when the tag may go.
export function releaseGaps(version: string, files: ReleaseFiles): string[] {
  const gaps: string[] = []
  const marketing = files.projectYml.match(/MARKETING_VERSION:\s*"?([\d.]+)"?/)?.[1]
  if (marketing !== version) {
    gaps.push(`project.yml has MARKETING_VERSION ${marketing ?? '(missing)'}, not ${version}`)
  }
  const escaped = version.replace(/\./g, '\\.')
  if (!new RegExp(`^## ${escaped}\\s*$`, 'm').test(files.changelog)) {
    gaps.push(`CHANGELOG.md has no "## ${version}" section`)
  }
  if (files.recette !== undefined) {
    const passages = files.recette.split(/^## Passages\s*$/m)[1] ?? ''
    const rows = passages.split('\n').filter(l => /^\|\s*\d{4}-\d{2}-\d{2}/.test(l))
    const isRun = rows.some(l => (l.split('|')[2] ?? '').includes(version))
    if (!isRun) gaps.push(`docs/RECETTE.md has no run of ${version} in its "Passages" table`)
  }
  return gaps
}

// Lines of `added` that break a Swift convention and were not already in
// `before`, so a file's existing lines are never reported again.
export function swiftWarnings(path: string, before: string, added: string): string[] {
  if (!path.endsWith('.swift') || /Tests\//.test(path)) return []
  const old = new Set(before.split('\n').map(l => l.trim()))
  const found = new Set<string>()
  for (const raw of added.split('\n')) {
    const line = raw.trim()
    if (line === '' || line.startsWith('//') || old.has(line)) continue
    const code = line.replace(/"(\\.|[^"\\])*"/g, '""')
    if (/\btry!/.test(code)) found.add('`try!`')
    if (/[\w)\]]!(?=[.)\],\s]|$)/.test(code.replace(/\btry!/g, 'try'))) found.add('force-unwrap `!`')
    if (/\bAVAudioEngine\b/.test(code)) found.add('`AVAudioEngine` (3146 ms on AirPods: capture goes through AVCaptureSession)')
  }
  return [...found]
}

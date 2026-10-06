// Shell parsing shared by the guardrails and the build status.

// What a shell line runs, never the text it carries: a script, a heredoc or a commit message that mentions
// `xcodebuild` or `git push` must not be mistaken for running them.

// The command with quoted text and heredoc bodies blanked out, same length,
// so separators and command names are only found where the shell sees them.
export function maskData(command: string): string {
  let out = ''
  let quote: '"' | "'" | undefined
  const heredocs: { tag: string; isIndented: boolean }[] = []
  let i = 0
  while (i < command.length) {
    const c = command[i] ?? ''
    if (quote !== undefined) {
      if (quote === '"' && c === '\\' && i + 1 < command.length) {
        out += '__'
        i += 2
        continue
      }
      out += c === quote ? c : '_'
      if (c === quote) quote = undefined
      i++
      continue
    }
    const marker = command.slice(i).match(/^<<(-?)\s*(['"]?)(\w+)\2/)
    if (marker) {
      heredocs.push({ tag: marker[3] ?? '', isIndented: marker[1] === '-' })
      out += marker[0]
      i += marker[0].length
      continue
    }
    if (c === '\n' && heredocs.length > 0) {
      // The body belongs to the command that opened it, so this newline separates nothing.
      out += '_'
      i++
      for (const { tag, isIndented } of heredocs.splice(0)) {
        while (i < command.length) {
          const end = command.indexOf('\n', i)
          const lineEnd = end === -1 ? command.length : end
          const line = command.slice(i, lineEnd)
          const isLast = (isIndented ? line.replace(/^\t+/, '') : line) === tag
          out += '_'.repeat(line.length)
          i = lineEnd
          if (end !== -1 && !isLast) {
            out += '_'
            i++
          }
          if (isLast) break
        }
      }
      continue
    }
    if (c === '"' || c === "'") quote = c
    out += c
    i++
  }
  return out
}

// The simple commands a shell line runs, each as written in the original.
export function simpleCommands(command: string): string[] {
  const masked = maskData(command)
  const parts: string[] = []
  let start = 0
  for (const m of masked.matchAll(/&&|\|\||[;|\n]/g)) {
    parts.push(command.slice(start, m.index))
    start = m.index + m[0].length
  }
  parts.push(command.slice(start))
  return parts.map(p => p.trim()).filter(p => p !== '')
}

// A simple command's words, leading `(` and `VAR=value` assignments dropped.
// Quoted words stay whole, quotes kept, for a shell to resolve.
export function words(simple: string): string[] {
  const all = simple.replace(/^\(+/, '').match(/"(\\.|[^"\\])*"|'[^']*'|\S+/g) ?? []
  const first = all.findIndex(w => !/^\w+=/.test(w))
  return first === -1 ? [] : all.slice(first)
}

export type GitCall = { sub: string; args: string[]; dir?: string }

// `git [-C dir] [-c k=v] [--flag] <sub> args…`, or undefined for anything else.
export function gitCall(simple: string): GitCall | undefined {
  const w = words(simple)
  if (w[0] !== 'git') return undefined
  let dir: string | undefined
  let i = 1
  while (i < w.length && (w[i] ?? '').startsWith('-')) {
    if (w[i] === '-C') dir = w[i + 1]
    i += w[i] === '-C' || w[i] === '-c' ? 2 : 1
  }
  const sub = w[i]
  return sub === undefined ? undefined : { sub, args: w.slice(i + 1), dir }
}

// The directory the first simple command `isTarget` accepts runs in, as
// written (quotes and ~ kept, for a shell to resolve): the last `cd` before it.
export function cdBefore(command: string, isTarget: (simple: string) => boolean): string | undefined {
  let dir: string | undefined
  for (const simple of simpleCommands(command)) {
    if (isTarget(simple)) return dir
    const w = words(simple)
    if (w[0] === 'cd' && w[1] !== undefined) dir = w[1]
  }
  return undefined
}

// The directory a command runs git in: the first git call's `-C`, else the
// last `cd` before it.
export function commandDir(command: string): string | undefined {
  const first = simpleCommands(command).map(gitCall).find(g => g !== undefined)
  return first?.dir ?? cdBefore(command, simple => gitCall(simple) !== undefined)
}

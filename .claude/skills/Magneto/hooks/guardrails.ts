// Refuses or flags what the CLAUDE.md rules out, when a tool is called.
import type { EngineInterface, Register } from 'claude-code'
import {
  asksForCommit,
  isAgreement,
  proposesCommit,
  commandDir,
  derivedDataInsideRepo,
  isCommitOrPush,
  releaseGaps,
  releaseTag,
  swiftWarnings,
} from './rules'

async function readOrUndefined($: EngineInterface, path: string): Promise<string | undefined> {
  try {
    const text = await $.fs.read(path)
    return typeof text === 'string' ? text : undefined
  } catch {
    return undefined
  }
}

// The repository root a command runs in, resolved by the shell the way the
// command itself would resolve its `cd` or `git -C`.
async function repoRoot($: EngineInterface, command: string): Promise<string | undefined> {
  const dir = commandDir(command)
  const script = dir === undefined ? 'git rev-parse --show-toplevel' : `cd ${dir} && git rev-parse --show-toplevel`
  const { exitCode, stdout } = await $.process.run(['/bin/zsh', '-c', script])
  return exitCode === 0 ? stdout.trim() : undefined
}

export const guardrails: Register = on => {
  // Whether the person's latest message asked for a commit, a push or a tag.
  let isCommitAsked = false

  // Claude's last answer proposed a commit, a push or a tag: kept in the store,
  // so that the reload a turn's edits cause between the answer and the reply
  // does not forget it.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) await $.store.set('isCommitProposed', proposesCommit(e.answer))
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const isCommitProposed = (await $.store.get('isCommitProposed')) === true
    isCommitAsked = asksForCommit(e.text) || (isCommitProposed && isAgreement(e.text))
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const inside = derivedDataInsideRepo(e.command)
    if (inside !== undefined) {
      $.ui.toast(`guardrails : build refusé, -derivedDataPath ${inside}`)
      return {
        deny:
          `guardrails: -derivedDataPath ${inside} builds inside the repository, where Spotlight indexes the built .app copies. ` +
          'Use ~/Library/Developer/Xcode/DerivedData/<App>.',
      }
    }

    if (isCommitOrPush(e.command) && !isCommitAsked) {
      $.ui.toast('guardrails : commit/push refusé, non demandé')
      return {
        deny:
          'guardrails: no commit or push without an explicit request in the latest user message, ' +
          'or its plain agreement to a commit the previous answer proposed. ' +
          'Offer it and wait for the user to ask.',
      }
    }

    const version = releaseTag(e.command)
    if (version !== undefined) {
      const root = await repoRoot($, e.command)
      const projectYml = root && (await readOrUndefined($, `${root}/project.yml`))
      const changelog = root && (await readOrUndefined($, `${root}/CHANGELOG.md`))
      if (root && projectYml && changelog !== undefined) {
        const recette = await readOrUndefined($, `${root}/docs/RECETTE.md`)
        const gaps = releaseGaps(version, { projectYml, changelog, recette })
        if (gaps.length > 0) {
          $.ui.toast(`guardrails : tag v${version} refusé`)
          return { deny: `guardrails: v${version} cannot be released yet:\n- ${gaps.join('\n- ')}` }
        }
      }
    }

    return next(e)
  })

  on('tool.call', { tool: ['Edit', 'Write'] }, async ($, e, next) => {
    const warnings =
      e.tool === 'Edit'
        ? swiftWarnings(e.file_path, e.old_string, e.new_string)
        : e.tool === 'Write'
          ? swiftWarnings(e.file_path, (await readOrUndefined($, e.file_path)) ?? '', e.content)
          : []
    const ran = await next(e)
    if (warnings.length === 0 || ran.deny !== undefined || ran.isError === true) return ran

    const name = e.file_path.split('/').pop() ?? e.file_path
    $.ui.toast(`guardrails : ${name} : ${warnings.join(', ')}`)
    const note =
      `guardrails: ${name} now contains ${warnings.join(', ')}, which the project rules out of production paths. ` +
      'Fix it, or tell the user why it is justified here.'
    return { ...ran, context: [...(ran.context ?? []), note] }
  })
}

import { expect, test } from 'claude-code/testing'
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

test('derived data inside the repository is caught, outside it is not', () => {
  expect(derivedDataInsideRepo('xcodebuild -scheme Magneto -derivedDataPath build build')).toBe('build')
  expect(derivedDataInsideRepo('xcodebuild -derivedDataPath ./dd build')).toBe('./dd')
  expect(derivedDataInsideRepo('xcodebuild -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto build')).toBeUndefined()
  expect(derivedDataInsideRepo('xcodebuild -derivedDataPath "$HOME/Library/x" build')).toBeUndefined()
  expect(derivedDataInsideRepo('xcodebuild -scheme Magneto build')).toBeUndefined()
})

test('text a command carries is not something it runs', () => {
  // The false positive met while editing this mod: a script quoting the rule's own message.
  expect(derivedDataInsideRepo("python3 - <<'EOF'\nmsg = '-derivedDataPath ${inside} builds'\nEOF")).toBeUndefined()
  expect(derivedDataInsideRepo('python3 -c "print(\'xcodebuild -derivedDataPath build\')"')).toBeUndefined()
  expect(derivedDataInsideRepo('grep -n "derivedDataPath build" CLAUDE.md')).toBeUndefined()
  expect(isCommitOrPush('echo "git commit -m x"')).toBe(false)
  expect(isCommitOrPush("cat <<EOF > notes.md\ngit push origin main\nEOF")).toBe(false)
  expect(isCommitOrPush('git log --grep commit')).toBe(false)
  expect(releaseTag('echo "then git tag v1.0.0"')).toBeUndefined()
})

test('what a command does run is still caught around the data it carries', () => {
  expect(derivedDataInsideRepo("echo 'x; y' && xcodebuild -derivedDataPath build build")).toBe('build')
  expect(derivedDataInsideRepo("cat <<EOF\nx\nEOF\nxcodebuild -derivedDataPath dd")).toBe('dd')
  expect(isCommitOrPush('git commit -m "fix: a; b && c"')).toBe(true)
  expect(isCommitOrPush('GIT_EDITOR=true git -c user.name=x commit')).toBe(true)
  expect(releaseTag('git tag -l v0.4.2')).toBeUndefined()
})

test('a release tag or its push names the version', () => {
  expect(releaseTag('git tag v0.4.3')).toBe('0.4.3')
  expect(releaseTag('git tag -a v1.0.0 -m "x"')).toBe('1.0.0')
  expect(releaseTag('git push origin v0.4.3')).toBe('0.4.3')
  expect(releaseTag('git push origin main')).toBeUndefined()
  expect(releaseTag('git log v0.4.2..HEAD')).toBeUndefined()
})

test('commit and push are recognised, reading git is not', () => {
  expect(isCommitOrPush('git commit -m "fix: x"')).toBe(true)
  expect(isCommitOrPush('git add -A && git commit -m x')).toBe(true)
  expect(isCommitOrPush('git -C "/a b" push origin main')).toBe(true)
  expect(isCommitOrPush('git status')).toBe(false)
  expect(isCommitOrPush('git log --oneline -5')).toBe(false)
})

test('a dictated request for a commit counts', () => {
  expect(asksForCommit('Tu peux committer et pousser ?')).toBe(true)
  expect(asksForCommit('commit ça')).toBe(true)
  expect(asksForCommit('Regarde le bug du collage')).toBe(false)
})

test('the git directory is read from cd or -C', () => {
  expect(commandDir('cd "../Mystique" && git tag v0.1.0')).toBe('"../Mystique"')
  expect(commandDir('git -C ~/x tag v1.0.0')).toBe('~/x')
  expect(commandDir('git tag v1.0.0')).toBeUndefined()
})

const recette = (version: string) =>
  `# R\n\n## Passages\n\n| Date | Version | macOS |\n|---|---|---|\n| 2026-10-06 | ${version} | 27.2 |\n`

test('a release with everything in place has no gap', () => {
  const gaps = releaseGaps('0.4.3', {
    projectYml: '    MARKETING_VERSION: "0.4.3"\n',
    changelog: '# Notes\n\n## 0.4.3\n\nTexte.\n',
    recette: recette('0.4.3'),
  })
  expect(gaps).toEqual([])
})

test('each missing piece of a release is named', () => {
  const gaps = releaseGaps('0.4.3', {
    projectYml: '    MARKETING_VERSION: "0.4.2"\n',
    changelog: '## 0.4.2\n',
    recette: recette('0.4.2'),
  })
  expect(gaps.length).toBe(3)
})

test('swift warnings only report new lines outside tests and strings', () => {
  const path = '/r/Magneto/AppState.swift'
  expect(swiftWarnings(path, '', 'let x = try! load()')).toEqual(['`try!`'])
  expect(swiftWarnings(path, '', 'let y = value!.count')).toEqual(['force-unwrap `!`'])
  expect(swiftWarnings(path, '', 'if a != b, !isOn { print("Merci !") }')).toEqual([])
  expect(swiftWarnings(path, 'let x = try! load()', 'let x = try! load()')).toEqual([])
  expect(swiftWarnings('/r/MagnetoTests/A.swift', '', 'try! x()')).toEqual([])
  expect(swiftWarnings('/r/README.md', '', 'try! x()')).toEqual([])
})

test('a plain agreement counts, a reserved one does not', () => {
  // The false refusal met on the 0.4.3 release: « oui va y » to a plan that listed the commits.
  expect(isAgreement('oui va y')).toBe(true)
  expect(isAgreement('Vas-y')).toBe(true)
  expect(isAgreement('ok go')).toBe(true)
  expect(isAgreement("d'accord")).toBe(true)
  expect(isAgreement('oui mais attends, pas tout de suite')).toBe(false)
  expect(isAgreement('non')).toBe(false)
  expect(isAgreement('Regarde plutôt le bug du collage')).toBe(false)
})

test('only an answer asking about a commit proposes one', () => {
  expect(proposesCommit('Ensuite : commits, recette, tag v0.4.3.\n\nJe pars sur 0.4.3 et je lance la recette ?')).toBe(true)
  expect(proposesCommit("Rien n'est commité ; dis-moi quand tu veux.")).toBe(false)
  expect(proposesCommit('Tu préfères fusionner ou garder deux plugins ?')).toBe(false)
})

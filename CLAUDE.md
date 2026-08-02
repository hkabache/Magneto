# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

Magneto is a minimal macOS menu bar dictation app, native Swift/SwiftUI, single target, one SPM dependency (KeyboardShortcuts). It replaces the Tauri-based Handy fork which lives untouched in `legacy/` (its own git repo, excluded from this one). Use `legacy/` as reference only, never modify it.

Pipeline: global hotkey toggle → AVAudioRecorder (wav 16kHz mono) → transcription chain (ElevenLabs Scribe v2 → Voxtral → Apple SpeechAnalyzer) → rule-based cleanup → optional LLM cleanup (Mistral Small / Claude Haiku) → paste at cursor via synthesized Cmd+V.

## Build

```bash
xcodegen generate                  # regenerate Magneto.xcodeproj from project.yml (gitignored)
xcodebuild -project Magneto.xcodeproj -scheme Magneto -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto build
./scripts/dev.sh                   # Debug build + launch
./scripts/install.sh               # Release build + install to /Applications + launch
```

Never build with `-derivedDataPath build` (inside the repo): Spotlight indexes the
resulting Debug and Release `Magneto.app` copies as real applications, so searching
"Magneto" in Finder returns three icons instead of one. Always target
`~/Library/Developer/Xcode/DerivedData/Magneto`, which the scripts also mark with
`.metadata_never_index`.

Always verify compilation with xcodebuild before declaring a task done. Fix new warnings immediately.

Never launch or kill the app yourself unless explicitly asked: the app is ad-hoc signed, so every rebuild changes the code signature and macOS re-prompts microphone/accessibility permissions. The user manages launches.

## Layout

```
project.yml                        XcodeGen spec (source of truth for build settings)
Magneto/
  MagnetoApp.swift                 @main, MenuBarExtra (.window style)
  AppState.swift                   state machine idle/recording/transcribing, pipeline orchestration
  Audio/Recorder.swift             AVAudioRecorder wrapper, level metering
  Transcription/                   TranscriptionClient protocol + chain + 3 clients
  PostProcessing/RulePass.swift    deterministic regex cleanup (ellipsis artifacts, FR typography)
  PostProcessing/LLMPass.swift     LLM cleanup pass, strict "correct, never rewrite" prompt
  Output/Paster.swift              transient pasteboard + CGEvent Cmd+V + clipboard restore
  UI/                              MenuBarView (popover with tabs), OverlayPanel (NSPanel pill)
  Support/                         AppSettings, Keychain, Permissions, Hotkeys, HandyMigration
```

## Conventions

- UI strings are French (personal tool). Code and identifiers in English.
- API keys go through `Keychain` only. Never log them, never store them in UserDefaults.
- No `unwrap`-style force operations: no `try!`, no `!` force-unwrap in production paths.
- Settings live in `AppSettings` (@Published + UserDefaults persistence). New settings need a default in `init`.
- Errors surface as `MagnetoError` with French `errorDescription`.
- The paste flow must never block on the LLM pass: on LLM failure/timeout, paste the rule-cleaned text.
- Conventional commits (feat:/fix:/docs:/refactor:/chore:), French commit messages.
- Never commit or push without an explicit request from the user.

## Known deferred items

- Apple SpeechAnalyzer vocabulary biasing (AnalysisContext.contextualStrings) intentionally omitted: unproven on SpeechTranscriber, vocabulary is enforced by keyterms + LLM pass instead.
- App language is system-driven (French strings hardcoded); EN localization via String Catalog is backlog.
- Ad-hoc signing: switching to a free Apple Development certificate keeps TCC grants across rebuilds.
- macOS 27 "Advanced Dictation" (AFM 3 Core Advanced) not yet exposed to third-party Speech API; re-evaluate at GM.

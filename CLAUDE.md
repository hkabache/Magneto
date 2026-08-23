# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

Magneto is a minimal macOS menu bar dictation app, native Swift/SwiftUI, single target, one SPM dependency (KeyboardShortcuts). Distributed outside the App Store: Developer ID signed, notarized, published as a DMG by the release workflow on a `v*` tag.

Pipeline: global hotkey toggle → AVAudioRecorder (wav 16kHz mono) → transcription chain (ElevenLabs Scribe v2 → Voxtral → Apple SpeechAnalyzer) → rule-based cleanup → optional LLM cleanup (Mistral Small / Claude Haiku) → paste at cursor via synthesized Cmd+V.

## Build

```bash
xcodegen generate                  # regenerate Magneto.xcodeproj from project.yml (gitignored)
xcodebuild -project Magneto.xcodeproj -scheme Magneto -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto build
./scripts/dev.sh                   # Debug build + launch
./scripts/install.sh               # Release build + install to /Applications + launch
xcodebuild test -project Magneto.xcodeproj -scheme Magneto -destination 'platform=macOS'
```

Never build with `-derivedDataPath build` (inside the repo): Spotlight indexes the
resulting Debug and Release `Magneto.app` copies as real applications, so searching
"Magneto" in Finder returns three icons instead of one. Always target
`~/Library/Developer/Xcode/DerivedData/Magneto`, which the scripts also mark with
`.metadata_never_index`.

Always verify compilation with xcodebuild before declaring a task done. Fix new warnings immediately.

Never launch or kill the app yourself unless explicitly asked: the user keeps a copy running to dictate with, and killing it costs them the tool they are talking to you through.

## Layout

```
project.yml                        XcodeGen spec (source of truth for build settings)
Magneto/
  MagnetoApp.swift                 @main, MenuBarExtra (.window style)
  AppState.swift                   state machine idle/recording/transcribing, pipeline orchestration
  Audio/Recorder.swift             picks a capture path per dictation, publishes level and status
  Audio/SimpleCapture.swift        AVAudioRecorder, built-in microphone only
  Audio/ResilientCapture.swift     AVCaptureSession, rebuilds a dead or stalled stream
  Audio/InputDevice.swift          CoreAudio transport of the default input
  Transcription/                   TranscriptionClient protocol + chain + 3 clients
  PostProcessing/RulePass.swift    deterministic regex cleanup (ellipsis artifacts, FR typography)
  PostProcessing/LLMPass.swift     LLM cleanup pass, strict "correct, never rewrite" prompt
  Output/Paster.swift              transient pasteboard + CGEvent Cmd+V + clipboard restore
  UI/                              MenuBarView (popover with tabs), OverlayPanel (NSPanel pill)
  Support/                         AppSettings, Keychain, Permissions, Hotkeys, CapsLockDelay, Log, Diagnostics, Updater
MagnetoTests/                      pure-logic tests, no network, no host app
```

The test bundle compiles the app sources into itself rather than being hosted by the
app: the hardened runtime blocks the injection a `TEST_HOST` needs, and relaxing it
for Debug would break the signature TCC pins its grants to.

## Conventions

- UI strings are French (personal tool). Code and identifiers in English.
- API keys go through `Keychain` only. Never log them, never store them in UserDefaults.
- No `unwrap`-style force operations: no `try!`, no `!` force-unwrap in production paths.
- Settings live in `AppSettings` (@Published + UserDefaults persistence). New settings need a default in `init`.
- Errors surface as `MagnetoError` with French `errorDescription`.
- The paste flow must never block on the LLM pass: on LLM failure/timeout, paste the rule-cleaned text.
- Conventional commits (feat:/fix:/docs:/refactor:/chore:), French commit messages.
- Never commit or push without an explicit request from the user.
- Capture never goes through `AVAudioEngine`: reading its `inputNode` was measured at 3146 ms on AirPods
  against 246 ms for `AVCaptureSession`, because macOS publishes a Bluetooth headset as a microphone
  device and a separate output device, and the engine aggregates the two before handing over a node.
- Sparkle only checks when the button is pressed (`SUEnableAutomaticChecks` false). The README states which hosts are contacted and when, so anything that widens that has to be reflected there in the same change.

## Known deferred items

- Apple SpeechAnalyzer vocabulary biasing (AnalysisContext.contextualStrings) intentionally omitted: unproven on SpeechTranscriber, vocabulary is enforced by keyterms + LLM pass instead.
- App language is system-driven (French strings hardcoded); EN localization via String Catalog is backlog.
- macOS 27 "Advanced Dictation" (AFM 3 Core Advanced) not yet exposed to third-party Speech API; re-evaluate at GM.

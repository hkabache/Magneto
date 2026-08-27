# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

Magneto is a minimal macOS menu bar dictation app, native Swift/SwiftUI, single target, one SPM dependency (KeyboardShortcuts). Distributed outside the App Store: Developer ID signed, notarized, published as a DMG by the release workflow on a `v*` tag.

Pipeline: global hotkey toggle → AVAudioRecorder (wav 16kHz mono) → transcription chain (ElevenLabs Scribe v2 → Apple SpeechAnalyzer) → quote straightening → paste at cursor via synthesized Cmd+V.

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
  Transcription/                   TranscriptionClient protocol + chain + 2 clients
  PostProcessing/QuotePass.swift   straightens quotation marks, and nothing else
  Output/Paster.swift              transient pasteboard + CGEvent Cmd+V + clipboard restore
  UI/                              MenuBarView (popover with tabs), OverlayPanel (NSPanel pill)
  Support/                         AppSettings, Keychain, Permissions, Hotkeys, CapsLockDelay, Log, Updater, DictationJournal
MagnetoTests/                      pure-logic tests, no network, no host app
```

The test bundle compiles the app sources into itself rather than being hosted by the
app: the hardened runtime blocks the injection a `TEST_HOST` needs, and relaxing it
for Debug would break the signature TCC pins its grants to.

## Conventions

- UI strings are French (personal tool). Code and identifiers in English.
- API keys go through `Keychain` only. Never log them, never store them in UserDefaults.
- The system journal never carries the dictated text, and is read with the `log show` command the README
  prints. `DictationJournal` is the only place that text lands, in clear and with the audio, and only while
  its setting is on. It is the instrument every measured decision in this file came from, so keep it usable.
- No `unwrap`-style force operations: no `try!`, no `!` force-unwrap in production paths.
- Settings live in `AppSettings` (@Published + UserDefaults persistence). New settings need a default in `init`.
- Errors surface as `MagnetoError` with French `errorDescription`.
- There is no LLM cleanup pass, and adding one back needs evidence. The one that existed changed 10 words
  out of 1053 over a full day of real dictation, nine of them a trailing full stop, for a second of latency
  every time: Scribe's `no_verbatim` already does that work inside the transcription call. Removed in
  c4c047e's successor; the code is in history if a measurement ever justifies it.
- Nothing rewrites the engine's text except `QuotePass`, and adding a rule back needs a count first. Nine
  once existed for Voxtral's verbatim output; measured on 1981 words from Scribe and 1512 from the local
  model they fired zero times, and two damaged a correct text: one stripped the space French wants before
  `?` `!` `;` `:`, which Scribe writes 15 times in 45 dictations, the other forced casing on the fragments
  Scribe deliberately leaves lowercase for someone patching the middle of a sentence.
- Conventional commits (feat:/fix:/docs:/refactor:/chore:), French commit messages. Subjects ship to
  users: the release workflow turns them into the release notes, which Sparkle displays in its update
  window, prefix and version bump stripped.
- Never commit or push without an explicit request from the user.
- Capture never goes through `AVAudioEngine`: reading its `inputNode` was measured at 3146 ms on AirPods
  against 246 ms for `AVCaptureSession`, because macOS publishes a Bluetooth headset as a microphone
  device and a separate output device, and the engine aggregates the two before handing over a node.
- Sparkle only checks when the button is pressed (`SUEnableAutomaticChecks` false). The README states which hosts are contacted and when, so anything that widens that has to be reflected there in the same change.

## Known deferred items

- Apple SpeechAnalyzer vocabulary biasing: measured inert, not merely unproven. `AnalysisContext.contextualStrings`
  fed through `setContext` left all 34 test dictations identical byte for byte. Only the
  `init(inputSequence:…analysisContext:)` path remains untested. Vocabulary is enforced by keyterms instead.
- `DictationTranscriber`, Apple's dictation-oriented module, measured worse than `SpeechTranscriber` on French
  dictation (SKU heard as "SAU", contexte as "contacts"), and its explicit `.punctuation` option changed nothing.
  Both share one asset, `com.apple.speech.asr.transcription.fr`, so there is no second French model to reach for.
- App language is system-driven (French strings hardcoded); EN localization via String Catalog is backlog.
- macOS 27 advanced dictation exists and this Mac qualifies for it (M3, 16 GB, against a bar of M3 and 12 GB),
  but it runs on the Apple Intelligence assets that the system dictation uses, not on the Speech framework's ASR
  family, whose only French entry is the classic model. Out of reach for a third-party app; re-evaluate when a
  macOS 27 SDK ships, since Xcode 26.6 still builds against 26.5.

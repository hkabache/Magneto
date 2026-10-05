# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project

Magneto is a minimal macOS menu bar dictation app, native Swift/SwiftUI, two SPM dependencies on the Mac (KeyboardShortcuts, Sparkle), none on the iPhone. Distributed outside the App Store: Developer ID signed, notarized, published as a DMG by the release workflow on a `v*` tag. An iPhone target shares the transcription chain and is installed from Xcode, never released.

Pipeline: global hotkey toggle → AVAudioRecorder (wav 16kHz mono) → transcription chain (Scribe v2 raced against MAI-Transcribe-2: Scribe if back within 1.5 s, MAI at once past 45 s of audio → Apple SpeechAnalyzer) → quote straightening → paste at cursor via synthesized Cmd+V. On the iPhone the toggle is an App Intent run by a shortcut, the pill is a Live Activity, and the shortcut copies the text the intent returns.

## Build

```bash
xcodegen generate                  # regenerate Magneto.xcodeproj from project.yml (gitignored)
xcodebuild -project Magneto.xcodeproj -scheme Magneto -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto build
./scripts/dev.sh                   # Debug build + launch
./scripts/install.sh               # Release build + install to /Applications + launch
xcodebuild test -project Magneto.xcodeproj -scheme Magneto -destination 'platform=macOS'
xcodebuild -project Magneto.xcodeproj -scheme MagnetoIOS -destination 'id=<UDID>' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Magneto -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/Magneto/Build/Products/Debug-iphoneos/Magneto.app
```

The iPhone build needs the phone plugged in and unlocked, and `-allowProvisioningUpdates`
fails on every freshly created profile with "Build input file cannot be found"; the second run passes.

Tests use Swift Testing: xcodebuild's "Executed 0 tests" line is the XCTest counter, the real
count is the "Test run with N tests" line.

On a new Mac, beyond Xcode and `brew install xcodegen`: `sudo xcodebuild -runFirstLaunch` before
the first build, an Apple Account in Xcode's settings for the iPhone profiles, and the Developer ID
identity imported as a .p12 with its private key. That identity only turns valid once Apple's
intermediate is in the login keychain, which a fresh Xcode does not install:
`https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer`.

Never build with `-derivedDataPath build` (inside the repo): Spotlight indexes the
resulting Debug and Release `Magneto.app` copies as real applications, so searching
"Magneto" in Finder returns three icons instead of one. Always target
`~/Library/Developer/Xcode/DerivedData/Magneto`, which the scripts also mark with
`.metadata_never_index`.

Always verify compilation with xcodebuild before declaring a task done. Fix new warnings immediately.

## Release, update keys and signing

A `v*` tag runs the release: tests, signed DMG, notarization, stapling, signature of the Sparkle feed,
then publication of the DMG and of the `appcast.xml` the app reads. The DMG is published without a
version in its name, `Magneto.dmg`, so the README's download button points at a permanent URL.
Notarization needs every agreement of the Apple developer account in effect: an expired one fails the
"Notariser et agrafer" step with HTTP 403 "A required agreement is missing or has expired", and only the
user can sign it, on developer.apple.com.

The DMG's window (background, arrow, icon positions) comes from `scripts/dmg/`: `background.swift` draws the
picture, `settings.py` places the icons for dmgbuild, and the two share coordinates. To preview it, install
`dmgbuild==1.6.7` in a venv and run `scripts/dmg/build.sh <Magneto.app> <out.dmg>`. The Finder writes icon names
in a dark colour on any background picture, whatever the system appearance, so the background stays light.

Sparkle's EdDSA pair is independent of the Apple certificate: the public key is in `project.yml`, so
compiled into every copy of the app, and the private key appears nowhere in the repository. Losing it is
not fatal while the Developer ID certificate is intact: Sparkle rotates keys through a version that changes
either the Apple certificate or the EdDSA pair, never both at once. Losing both would make everyone
reinstall by hand.

TCC does not remember "this app is allowed" but a signing requirement, checked again on every call.
Ad-hoc, that requirement is the binary's `cdhash`, invalidated by every build, so the app is refused
while its box stays ticked in System Settings. The Developer ID certificate moves the requirement onto the
team identifier, which survives rebuilds and the certificate's renewal. Building without the certificate
means setting `CODE_SIGN_IDENTITY` to `-` in `project.yml`: the app works, but microphone and
accessibility have to be ticked again after every build. `install.sh` prints the requirement it got: a
`cdhash` in it means the certificate is missing and the grants will drop at the next build.

Once a change is finished and compiles, install it without asking, on the Mac (`./scripts/install.sh`) and on
the iPhone when the change touches it, then check it. The relaunch takes the user's dictation away for a few
seconds, so never install mid-change, and never quit or launch the app for any other reason.

To check the popover on screen, install the Debug build with `./scripts/dev.sh`: computer use only offers
running apps that have a Dock icon, and the Release build has none, so it is missing from `list_apps`, cannot
be granted, and its popover is blacked out of every screenshot. The Debug build sets `.regular` at launch
(`MagnetoApp.init`), shows in the Dock, and is granted as `com.hkabache.magneto`. Removing `LSUIElement` for a
runtime `.accessory` was tried and changed nothing: the Release build keeps the key. Once the check is done,
`./scripts/install.sh` puts the Release build back.

## Layout

```
project.yml                        XcodeGen spec (source of truth for build settings)
CHANGELOG.md                       release notes, one section per version, shown by Sparkle
Shared/                            compiled into every target, no AppKit or UIKit inside
  Transcription/                   TranscriptionClient protocol + chain and race + 3 clients
  PostProcessing/QuotePass.swift   straightens quotation marks, and nothing else
  Support/                         AppSettings (two macOS-only settings under #if), Keychain, KeyCheck, KeyStatus, Log, MagnetoError, DictationJournal, AudioFile, UsageLedger
Magneto/                           macOS app
  MagnetoApp.swift                 @main, MenuBarExtra (.window style)
  AppIcon.icon                     Icon Composer file, for now the menu bar's waveform symbol in white on blue
  AppState.swift                   state machine idle/recording/transcribing, pipeline orchestration
  Audio/Recorder.swift             picks a capture path per dictation, publishes level and status
  Audio/SimpleCapture.swift        AVAudioRecorder, built-in microphone only
  Audio/ResilientCapture.swift     AVCaptureSession, rebuilds a dead or stalled stream
  Audio/InputDevice.swift          CoreAudio transport of the default input
  Output/Paster.swift              transient pasteboard + CGEvent Cmd+V + clipboard restore
  UI/                              MenuBarView (popover with tabs), OverlayPanel (NSPanel pill)
  Support/                         Permissions, Hotkeys, CapsLockDelay, Updater
MagnetoIOS/                        iPhone app: Dictation (the intent-driven pipeline), ToggleDictationIntent, SettingsView, Dicter.shortcut
  Activity/RecordingAttributes     the Live Activity state, the only file the widget extension shares with the app
MagnetoIOSWidgets/                 DictationLiveActivity, the pill
MagnetoTests/                      pure-logic tests, no network, no host app
```

The test bundle compiles the app sources into itself rather than being hosted by the
app: the hardened runtime blocks the injection a `TEST_HOST` needs, and relaxing it
for Debug would break the signature TCC pins its grants to.

## Conventions

- UI strings are French (personal tool) and address the user as « vous », as does the README. Code and identifiers in English.
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
- Conventional commits (feat:/fix:/docs:/refactor:/chore:), French commit messages. A commit that
  changes nothing on the Mac carries the `(ios)` scope, `feat(ios): …`.
- Release notes are the `## <version>` section of `CHANGELOG.md`, published as is in Sparkle's update
  window and on the GitHub release. Write it in the version bump commit, before the tag: full sentences,
  capitalized and ending with a full stop, « vous », saying what changes for someone who dictates, never
  how it is coded. Mac changes only, since only Mac users read that window. Without a section the workflow
  falls back to the commit subjects, `(ios)` and the bump dropped, which reads as a list of titles: the
  0.4.0 window showed one lowercase fragment, and that is what the section exists to avoid.
- A version adding a feature bumps the minor number (0.4.0), a fix the patch (0.4.1).
- Never commit or push without an explicit request from the user.
- Capture never goes through `AVAudioEngine`: reading its `inputNode` was measured at 3146 ms on AirPods
  against 246 ms for `AVCaptureSession`, because macOS publishes a Bluetooth headset as a microphone
  device and a separate output device, and the engine aggregates the two before handing over a node.
- Sparkle checks weekly on its own and never opens a window to announce it: `GentleReminders` declines the
  scheduled alert and the popover carries the version instead, because a window taking focus takes the
  synthesized Cmd+V of a dictation with it. Its delegate methods are optional and called by selector, so a
  Swift rename disables the feature in silence; `UpdaterTests` pins the four selectors. The README states
  which hosts are contacted and when, so anything that widens that has to be reflected there in the same
  change.

## iPhone

The rules of the phone pipeline, both intent protocols, the mixable session and its retry, the text
returned instead of pasted, sit as comments next to the lines they constrain, each measured on the phone.
What the code cannot say:

- `Dicter.shortcut` is the three-action shortcut that copies the intent's result, signed with
  `shortcuts sign --mode anyone`. To change it, rebuild it in Shortcuts (Dicter, Si Texte a une valeur,
  Copier dans le presse-papiers), export it and re-sign.
- No Control Center control, on purpose: it would run the intent outside the shortcut and the text would
  go nowhere.
- Screen off, the Action button wakes the screen and iOS runs nothing else. Out of scope by choice: the
  dictation only serves inside an open app.

## Known deferred items

- Apple SpeechAnalyzer vocabulary biasing: measured inert, not merely unproven. `AnalysisContext.contextualStrings`
  fed through `setContext` left all 34 test dictations identical byte for byte. Only the
  `init(inputSequence:…analysisContext:)` path remains untested. Vocabulary is enforced by keyterms instead.
- `DictationTranscriber`, Apple's dictation-oriented module, measured worse than `SpeechTranscriber` on French
  dictation (SKU heard as "SAU", contexte as "contacts"), and its explicit `.punctuation` option changed nothing.
  Both share one asset, `com.apple.speech.asr.transcription.fr`, so there is no second French model to reach for.
- App language is system-driven (French strings hardcoded); EN localization via String Catalog is backlog.
- The iPhone app has no icon, and the keychain item keeps the default accessibility: a dictation started
  while the phone is locked would not read the key and would fall back to the Apple engine.
- macOS 27 advanced dictation runs on the Apple Intelligence assets that the system dictation uses, not on the
  Speech framework's ASR family, whose only French entry is the classic model: out of reach for a third-party app
  as of the 26.5 SDK. Worth re-checking against the macOS 27 SDK.

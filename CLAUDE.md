# Nihongo Pro — context for Claude

Personal Japanese-study iPadOS app. SwiftUI, iPadOS 26+ only, single target, zero third-party dependencies.

## Architecture (locked-in decisions)

- **Two-pass translation:** the Translate button kicks off two sequential Anthropic Messages calls (`claude-sonnet-4-6`, plain `URLSession`).
  - **Pass 1 — `TranslationService.translate(_:)`:** returns `{words: [{text, reading, furigana}], translation}`. No definitions. Displayed and spoken as soon as it lands so the user can read/hear the sentence quickly.
  - **Pass 2 — `TranslationService.fetchDefinitions(sentence:words:)`:** sends `{sentence, words: [...]}` and gets back `{definitions: [String?]}` aligned to the words by index. `ContentView` merges the array into the existing `words` state (`Word.definition` is `var`). A subtle "Loading word definitions…" indicator appears below the English translation while pass 2 runs; on failure it becomes a "Couldn't load definitions" message with a Retry button.
  - Both prompts and the example JSON for each shape are pinned in `TranslationService.swift`.
- **Tap-to-define:** every word in the Japanese display is a `Button` in `FuriganaText`, disabled while `definition == nil`. The 1.5pt accent underline that marks a word as tappable is also gated on `definition != nil`, so it only appears after pass 2 lands. Tapping a tappable word opens `WordDefinitionView` as a medium-detent sheet showing the word, kana reading, English definition, and a speaker/stop button that plays just that word using the shared `SpeechService`.
- **Spoken Japanese (TTS):** `SpeechService` wraps `AVSpeechSynthesizer` for on-device Japanese TTS (ja-JP). Voice selection respects a user-chosen `AVSpeechSynthesisVoice.identifier` stored in `UserDefaults` under `speechVoiceIdentifier`; empty/unset falls back to the highest-quality installed ja-JP voice (premium > enhanced > default). Playback fires automatically **after** the Claude response lands (so the audio is synchronized with the visual reveal of the furigana + translation) and on demand via a speaker/stop button in the Japanese display area. Failed requests do not play audio. Rate is configurable in Settings (Natural / 85% / 65%) under key `speechRate`. The Settings sheet lists every installed ja-JP voice with a Play Sample button.
- **API key storage:** iOS Keychain (`kSecClassGenericPassword`, service `com.terrydonaghe.NihongoPro`, account `anthropic-api-key`). Entered in-app on first launch via `SettingsView`; re-openable via gear icon. No xcconfig/Secrets file.
- **Dependencies:** none third-party. System frameworks only: Foundation, SwiftUI, Security (Keychain), AVFoundation (TTS). No SPM, no CocoaPods.
- **Trigger:** Translate button (not auto-on-paste).
- **Device target:** iPad only (`TARGETED_DEVICE_FAMILY = 2`), iPadOS 26+ (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`).
- **Bundle ID:** `com.terrydonaghe.NihongoPro`.

## File map

```
NihongoPro/
  NihongoProApp.swift       @main App entry
  ContentView.swift         Paste area, Translate button, FuriganaText display, English translation
  SettingsView.swift        API-key sheet (first-launch + gear icon)
  TranslationService.swift  Anthropic client (translate + fetchDefinitions, shared sendMessage helper) + Word/FuriganaSegment/TranslationResult/TranslationError types + two system prompts
  FuriganaText.swift        SwiftUI view + WordView + FuriganaFlowLayout (custom Layout). Each word is a tappable Button.
  WordDefinitionView.swift  Sheet content showing word / kana reading / definition
  SpeechService.swift       AVSpeechSynthesizer wrapper + SpeechRate enum; ObservableObject exposing isSpeaking
  KeychainStore.swift       Wrapper around SecItem* APIs
  Info.plist                Bundle metadata, iPad orientations
  Assets.xcassets/          AppIcon + AccentColor placeholders
NihongoPro.xcodeproj/       project.pbxproj + workspace
```

## Build & run

Open `NihongoPro.xcodeproj` in Xcode and Run on an iPad simulator. Headless build for verification:

```bash
xcodebuild -project NihongoPro.xcodeproj -scheme NihongoPro \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Always run this after editing Swift files or pbxproj — SourceKit diagnostics shown during edits are noisy and unreliable; the actual build is the source of truth.

## Adding a new Swift source file

The pbxproj uses readable sequential IDs of the form `FA00000000000000000000{XY}`. When adding `NewFile.swift`:

1. Pick the next unused suffix (e.g. `A9` for the file ref, `B9` for the build file).
2. Add a `PBXFileReference` line in the PBXFileReference section.
3. Add a `PBXBuildFile` line in the PBXBuildFile section.
4. Add the file ref `A9` to the `FA00000000000000000000D1 /* NihongoPro */` group's `children`.
5. Add the build file `B9` to the `FA00000000000000000000E1 /* Sources */` build phase's `files`.
6. Rebuild with the xcodebuild command above.

Existing IDs in use:
- `A1`–`A5`: original Swift source files; `A6`: Info.plist; `A7`: Assets.xcassets; `A8`: FuriganaText.swift; `A9`: WordDefinitionView.swift; `AA`: SpeechService.swift
- `B1`–`B5`, `B7`–`B9`, `BA`: matching PBXBuildFile entries
- `C1`: app product; `D0`–`D2`: groups; `E1`–`E3`: build phases; `F00`/`F1`: project/target; `101`–`104`, `111`–`112`: configs

## Tuning behavior

- **Translation/furigana quality:** edit `translationSystemPrompt` in `TranslationService.swift` (pass 1). Definition quality lives in `definitionsSystemPrompt` (pass 2). Keep the example JSON in each prompt — both reliably anchor Claude's output shape.
- **Furigana display:** `FuriganaText` view exposes `baseFont`, `rubyFont`, `rubyColor`, `wordSpacing`, `lineSpacing`, and `onWordTap` parameters. Each word is wrapped in a `Button` and disabled when `definition == nil` (punctuation). Tappable words get a 1.5pt `.tint`-colored underline via a bottom overlay inside `WordView`; punctuation gets no underline. The flow-wrap logic is `FuriganaFlowLayout` in the same file. Note: wrapping words in `Button` removes per-character text selection on the Japanese display in exchange for tap-to-define; the English translation below remains selectable.
- **Definition sheet:** `WordDefinitionView` is a small SwiftUI view shown via `.sheet(item:)` with `.presentationDetents([.medium, .large])`. The selection state lives in `ContentView.selectedWord: WordSelection?` (a UUID-id wrapper around `Word` so `.sheet(item:)` works even when the same word appears twice). The sheet receives the shared `SpeechService` via init (`@ObservedObject`) so its play/stop button reflects the same `isSpeaking` state as the main display — closing the sheet while audio is still playing does not stop it.
- **TTS tuning:** voice selection priority is in `SpeechService.selectedVoice()` (UserDefaults override → `bestJapaneseVoice()` fallback). Quality-tier fallback is in `bestJapaneseVoice()` / `availableJapaneseVoices()` — change the sort order to change auto-pick behavior. Rate multipliers are in `SpeechRate.multiplier`. Audio session uses default `.ambient` so the device silent switch silences playback; to force playback regardless, set `AVAudioSession.sharedInstance().setCategory(.playback)` in `init()`. `SettingsView` reads `SpeechService.availableJapaneseVoices()` to populate its Voice picker — `SettingsView` takes the live `SpeechService` instance via init so the Play Sample button shares state with the main display.
- **Model:** `TranslationService.model` constant. Sonnet 4.6 is the chosen balance; Haiku is cheaper but weaker on idiomatic readings, Opus is overkill for sentence-level.

## Maintenance rule

**Whenever you add or change a feature, update both `CLAUDE.md` (this file) and `README.md` in the same change.** Terry asked for this explicitly so both files always reflect current state. Don't ask first — bundle it with the feature work.

## Git / GitHub

Private repo: `https://github.com/tad/nihongo-pro`. `main` tracks `origin/main`. Don't push unless Terry asks. Don't amend existing commits.

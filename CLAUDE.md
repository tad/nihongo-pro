# Nihongo Pro — context for Claude

Personal Japanese-study iPadOS app. SwiftUI, iPadOS 26+ only, single target, zero third-party dependencies.

## Architecture (locked-in decisions)

- **Translation + furigana + per-word definitions:** one round-trip to the Anthropic Messages API (`claude-sonnet-4-6`) via plain `URLSession`. The system prompt in `TranslationService.swift` instructs Claude to return strict JSON: `{ words: [{text, reading, furigana: [{text, reading?}], definition?}], translation }`. Each word carries its full hiragana reading, the per-segment furigana for display, and a contextual English definition. Punctuation has `definition: null`. Segmentation rules (kanji-only furigana segments, okurigana split off, hiragana readings only) are pinned in the prompt with a worked example.
- **Tap-to-define:** every word in the Japanese display is a `Button` in `FuriganaText`. Tapping opens `WordDefinitionView` as a medium-detent sheet showing the word, kana reading, and English definition. Definitions are pre-fetched in the translation call, so the sheet opens instantly.
- **API key storage:** iOS Keychain (`kSecClassGenericPassword`, service `com.terrydonaghe.NihongoPro`, account `anthropic-api-key`). Entered in-app on first launch via `SettingsView`; re-openable via gear icon. No xcconfig/Secrets file.
- **Dependencies:** none. Foundation + SwiftUI + Security only. No SPM, no CocoaPods.
- **Trigger:** Translate button (not auto-on-paste).
- **Device target:** iPad only (`TARGETED_DEVICE_FAMILY = 2`), iPadOS 26+ (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`).
- **Bundle ID:** `com.terrydonaghe.NihongoPro`.

## File map

```
NihongoPro/
  NihongoProApp.swift       @main App entry
  ContentView.swift         Paste area, Translate button, FuriganaText display, English translation
  SettingsView.swift        API-key sheet (first-launch + gear icon)
  TranslationService.swift  Anthropic client + Word/FuriganaSegment/TranslationResult/TranslationError types + system prompt
  FuriganaText.swift        SwiftUI view + WordView + FuriganaFlowLayout (custom Layout). Each word is a tappable Button.
  WordDefinitionView.swift  Sheet content showing word / kana reading / definition
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
- `A1`–`A5`: Swift source files; `A6`: Info.plist; `A7`: Assets.xcassets; `A8`: FuriganaText.swift; `A9`: WordDefinitionView.swift
- `B1`–`B5`, `B7`–`B9`: matching PBXBuildFile entries
- `C1`: app product; `D0`–`D2`: groups; `E1`–`E3`: build phases; `F00`/`F1`: project/target; `101`–`104`, `111`–`112`: configs

## Tuning behavior

- **Translation/furigana quality:** edit the `systemPrompt` constant in `TranslationService.swift`. Keep the example sentence — it reliably anchors the segmentation behavior.
- **Furigana display:** `FuriganaText` view exposes `baseFont`, `rubyFont`, `rubyColor`, `wordSpacing`, `lineSpacing`, and `onWordTap` parameters. Each word is wrapped in a `Button` and disabled when `definition == nil` (punctuation). The flow-wrap logic is `FuriganaFlowLayout` in the same file. Note: wrapping words in `Button` removes per-character text selection on the Japanese display in exchange for tap-to-define; the English translation below remains selectable.
- **Definition sheet:** `WordDefinitionView` is a small SwiftUI view shown via `.sheet(item:)` with `.presentationDetents([.medium, .large])`. The selection state lives in `ContentView.selectedWord: WordSelection?` (a UUID-id wrapper around `Word` so `.sheet(item:)` works even when the same word appears twice).
- **Model:** `TranslationService.model` constant. Sonnet 4.6 is the chosen balance; Haiku is cheaper but weaker on idiomatic readings, Opus is overkill for sentence-level.

## Maintenance rule

**Whenever you add or change a feature, update both `CLAUDE.md` (this file) and `README.md` in the same change.** Terry asked for this explicitly so both files always reflect current state. Don't ask first — bundle it with the feature work.

## Git / GitHub

Private repo: `https://github.com/tad/nihongo-pro`. `main` tracks `origin/main`. Don't push unless Terry asks. Don't amend existing commits.

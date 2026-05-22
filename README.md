# Nihongo Pro

A personal Japanese-study iPad app. Paste a Japanese sentence and get it back instantly with **furigana** above the kanji and a natural English translation below.

Translation and furigana are powered by Claude (Anthropic's Messages API). Your API key is stored in the iOS Keychain on-device — it never leaves the iPad except to call `api.anthropic.com`.

## Requirements

- Xcode 26 or newer
- An iPad (or iPad simulator) running iPadOS 26 or newer
- An [Anthropic API key](https://console.anthropic.com/) (pay-as-you-go; sentence translations cost a fraction of a cent)
- An Apple ID for code signing (free personal team is fine)

## Build & run

1. Clone the repo and open it in Xcode:
   ```bash
   git clone https://github.com/tad/nihongo-pro.git
   cd nihongo-pro
   open NihongoPro.xcodeproj
   ```
2. Select the **NihongoPro** target → **Signing & Capabilities** → pick your **Team**.
3. Choose an iPad destination (e.g. iPad Pro 13" running iPadOS 26) and press **Run** (⌘R).

## First launch

The Settings sheet appears automatically. Paste your Anthropic API key (starts with `sk-ant-…`) and tap **Save**. The key is written to the iOS Keychain. You can change or remove it any time via the gear icon in the top-right.

## Using it

1. Paste a Japanese sentence into the text box at the bottom.
2. Tap **Translate**. A *Waiting on Claude…* indicator appears while the request is in flight (usually a second or two).
3. The sentence appears at the top with small hiragana **furigana** above each kanji segment, alongside a speaker button to replay the audio. A natural English translation sits below. Japanese audio plays automatically as soon as the result appears; tap the speaker button any time to replay. A brief *Loading word definitions…* indicator appears below the translation while per-word definitions load in the background; once they arrive, tappable words become underlined.
4. **Tap any underlined word** in the Japanese sentence to open a definition sheet with its kana reading and an English meaning. (Punctuation is unmarked and not tappable.) Tap the speaker icon inside the sheet to hear just that word pronounced. Drag the sheet down or tap *Done* to dismiss.
5. To change voice or playback speed, tap the gear icon and use the **Speech** section. Tap *Play Sample* to preview your current selection. For better-quality voices, download enhanced/premium variants in iPadOS *Settings → Accessibility → Spoken Content → Voices → Japanese*, then **fully quit Nihongo Pro and reopen it** — new voices won't show up in the picker until the app process restarts.

Example input:
```
今日は良い天気ですね。
```

Example output:
```
   きょう      よ        てんき
   今日 は 良 い 天気 ですね。
   ─────────────────────────────
   It's nice weather today, isn't it?
```

## Features

- **Paste-and-translate** Japanese → English with one tap
- **Furigana** rendered above kanji segments, with kanji compounds kept together
- **Tap any underlined word** in the Japanese display to see its kana reading and a contextual English definition in a bottom sheet, with a speaker button to hear just that word. (Definitions are fetched in a second background pass — words become underlined and tappable a moment after the translation appears.)
- **Spoken Japanese** — the sentence is read aloud automatically after the translation appears, and a speaker button lets you replay it any time. Pick your voice and playback rate (Natural / 85% / 65%) in Settings, with a Play Sample button to preview.
- **Selectable** English translation (long-press to copy)
- **In-app API-key management** via the gear icon, with Keychain storage

## Tech stack

- SwiftUI (iPadOS 26+), no third-party dependencies
- Anthropic Messages API (`claude-sonnet-4-6`) via `URLSession`
- iOS Keychain (`Security` framework) for API key storage
- `AVSpeechSynthesizer` (`AVFoundation`) for on-device Japanese TTS
- Custom SwiftUI `Layout` for furigana flow-wrapping

## Privacy

Japanese sentences you translate are sent to Anthropic's API for processing (subject to [Anthropic's data-handling policies](https://www.anthropic.com/legal/privacy)). Nothing is stored on a server controlled by this app, and nothing is sent anywhere else.

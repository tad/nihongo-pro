# Nihongo Pro

A personal Japanese-study iPad app. Paste a Japanese sentence and see it back instantly with **furigana** above the kanji — tap any word for its meaning, try to understand the sentence yourself, then tap **Show translation** to reveal the natural English when you're ready.

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

1. Paste a Japanese sentence into the text box at the bottom. Input is limited to a single sentence — long sentences are welcome, but multi-sentence text will block the auto-parse and show a warning.
2. About a second after you stop typing/pasting, the sentence renders at the top with small hiragana **furigana** above each kanji segment, alongside a speaker button. Japanese audio plays automatically as soon as the result appears; tap the speaker any time to replay. A brief *Loading word definitions…* indicator runs while per-word definitions load in the background; once they arrive, tappable words become underlined.
3. **Tap any underlined word** in the Japanese sentence to open a definition sheet with its kana reading and an English meaning. (Punctuation is unmarked and not tappable.) Tap the speaker icon inside the sheet to hear just that word pronounced. Inside that sheet, the word's kanji characters appear underlined in the accent color — tap any kanji to drill into a new sheet showing its meaning, on'yomi/kun'yomi readings, a short note, and an animated stroke order diagram. Drag the sheet down or tap *Done* to dismiss.
4. Try to understand the sentence on your own. Once the Japanese has rendered, a **Show translation** button appears at the bottom — tap it when you're ready to reveal the natural English below.
5. Tap **Breakdown** (appears after you reveal the translation) to expand into a full study view: the English translation, then Vocabulary, Grammar, Sentence structure, and a Notes paragraph at the bottom. The button disappears once you're in the breakdown — paste a new sentence to start over.
6. Tap **Clear** (bottom left) to wipe the input, translation, and breakdown so you can paste a fresh sentence. Audio playback is stopped if it's still running.
7. To change voice or playback speed, tap the gear icon and use the **Speech** section. Tap *Play Sample* to preview your current selection. For better-quality voices, download enhanced/premium variants in iPadOS *Settings → Accessibility → Spoken Content → Voices → Japanese*, then **fully quit Nihongo Pro and reopen it** — new voices won't show up in the picker until the app process restarts.

Example input:
```
今日は良い天気ですね。
```

Example output:
```
   きょう      よ        てんき
   今日 は 良 い 天気 ですね。
```

…and then, after you tap **Show translation**:

```
   ─────────────────────────────
   It's nice weather today, isn't it?
```

## Features

- **Study-first flow** — paste a sentence and the Japanese (with furigana) appears automatically after a short pause. The English translation stays hidden behind a **Show translation** button so you can attempt the sentence yourself first.
- **Furigana** rendered above kanji segments, with kanji compounds kept together
- **Tap any underlined word** in the Japanese display to see its kana reading and a contextual English definition in a bottom sheet, with a speaker button to hear just that word. (Definitions are fetched in a second background pass — words become underlined and tappable a moment after the sentence appears.)
- **Tap a kanji** inside the word panel to drill into a per-character view: meaning, on'yomi/kun'yomi readings, a memorable note, and an animated stroke order diagram (stroke data from [KanjiVG](https://kanjivg.tagaini.net), CC BY-SA 3.0, fetched on demand and cached locally).
- **Persistent caching** of word definitions and per-kanji info on-device — once Claude has explained a word or kanji once, future appearances are instant (and free). Polysemous words (走る "to run" vs "to rush", 開く "to open" vs "to bloom") are detected by Claude on each fetch and deliberately *not* cached, so you always get a context-appropriate definition for them. Cache lives in the app's Application Support directory so it survives restarts.
- **Exposure counters** — every time you translate a sentence, each word's and each kanji's appearance is recorded on-device. Tapping a word or kanji shows "Seen N times" in the top-left of its modal, so you can gauge familiarity at a glance. Counts persist across app restarts.
- **Study session (early access)** — tap **Start study** after translating a sentence to enter a focused, full-screen study mode with a 25/5-minute pomodoro timer in the top-right. The session begins with a pre-quiz: type the definition and pronunciation of each word (Claude evaluates the definitions; pronunciation is an exact kana match), then the definition of each individual kanji. Items you answer correctly are skipped; the rest are queued for the upcoming study phases (shipping next).
- **Breakdown view** — once the translation is revealed, tap Breakdown to swap to a full study breakdown of the sentence: the English translation at top, then Vocabulary, Grammar, Sentence structure, and a Notes paragraph. The button disappears once you're in the breakdown — paste a new sentence to start over.
- **Spoken Japanese** — the sentence is read aloud automatically after the translation appears, and a speaker button lets you replay it any time. Pick your voice and playback rate (Natural / 85% / 65%) in Settings, with a Play Sample button to preview.
- **Selectable** English translation (long-press to copy)
- **In-app API-key management** via the gear icon, with Keychain storage

## Tech stack

- SwiftUI (iPadOS 26+), no third-party dependencies
- Anthropic Messages API (`claude-sonnet-4-6`) via `URLSession`
- iOS Keychain (`Security` framework) for API key storage
- `AVSpeechSynthesizer` (`AVFoundation`) for on-device Japanese TTS
- Native SwiftUI stroke renderer (`Path` trim animation on a 109-unit canvas with grid + numbered badges)
- Stroke order SVGs from [KanjiVG](https://kanjivg.tagaini.net) (CC BY-SA 3.0), fetched on demand and cached locally
- Custom SwiftUI `Layout` for furigana flow-wrapping

## Credits

Stroke order data is provided by the [KanjiVG project](https://kanjivg.tagaini.net) by Ulrich Apel and contributors, released under [Creative Commons BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). This app fetches individual SVG files on demand and does not redistribute the dataset.

## Privacy

Japanese sentences you translate are sent to Anthropic's API for processing (subject to [Anthropic's data-handling policies](https://www.anthropic.com/legal/privacy)). Nothing is stored on a server controlled by this app, and nothing is sent anywhere else.

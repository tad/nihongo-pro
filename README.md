# Nihongo Pro

A personal Japanese-study iPad app. Paste a Japanese sentence and see it back instantly — tap any word for its meaning, try to understand the sentence yourself, then tap **Show translation** to reveal the natural English when you're ready. Toggle **furigana** on top of the kanji whenever you need a reading hint.

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
2. About a second after you stop typing/pasting, the sentence renders at the top alongside a speaker button. Japanese audio plays automatically as soon as the result appears; tap the speaker any time to replay. A brief *Loading word definitions…* indicator runs while per-word definitions load in the background; once they arrive, tappable words become underlined. Furigana is off by default — tap the **book icon** in the top-right toolbar to flip on hiragana readings above the kanji (the setting is remembered across launches; Known words you've graduated will still hide their furigana).
3. **Tap any underlined word** in the Japanese sentence to open a definition sheet with its kana reading and an English meaning. (Punctuation is unmarked and not tappable.) Tap the speaker icon inside the sheet to hear just that word pronounced. Inside that sheet, the word's kanji characters appear underlined in the accent color — tap any kanji to drill into a new sheet showing its meaning, on'yomi/kun'yomi readings, a short note, and an animated stroke order diagram. Drag the sheet down or tap *Done* to dismiss.
4. Try to understand the sentence on your own. Once the Japanese has rendered, a **Show translation** button appears at the bottom — tap it when you're ready to reveal the natural English below.
5. Tap **Breakdown** (appears after you reveal the translation) to expand into a full study view: the English translation, then Vocabulary, Grammar, Sentence structure, and a Notes paragraph at the bottom. The button disappears once you're in the breakdown — paste a new sentence to start over.
6. Tap **Clear** (bottom left) to wipe the input, translation, and breakdown so you can paste a fresh sentence. Audio playback is stopped if it's still running.
7. Tap the **bookmark** next to the speaker on a parsed sentence to save it. Saved sentences are kept on-device with their full parse (furigana + definitions), so they reopen instantly and offline. Tap the **books icon** in the toolbar to browse your **Saved sentences** — tap one to reload it into the main screen, or swipe to delete.
8. Tap the **graduation-cap icon** in the toolbar to enter **reading drill** mode: all furigana is hidden, and tapping a word reveals just its reading inline (tap again to hide). It's a fast self-quiz on readings without opening the full definition modal. Tap the icon again to leave drill mode and return to normal tap-to-define.
9. Tap the **chart-bar icon** in the top-right to open the **Progress** sheet — at-a-glance counts of unique words and kanji you've encountered, how many you've marked Known, a familiarity distribution bar for each, an **Activity** card with your current day streak / completed study sessions / days studied / today's count plus two last-14-days bar charts (sentences parsed and study sessions), and your top 25 most-seen words and kanji. Every row is tappable to open the same word/kanji modal you'd get from a sentence. The **share icon** (top-left of the sheet) exports all your progress — frequencies, familiarity levels, daily activity, study sessions, and saved sentences — as a single JSON file you can AirDrop or save to Files as a backup.
10. To change voice or playback speed, tap the gear icon and use the **Speech** section. Tap *Play Sample* to preview your current selection. For better-quality on-device voices, download enhanced/premium variants in iPadOS *Settings → Accessibility → Spoken Content → Voices → Japanese*, then **fully quit Nihongo Pro and reopen it** — new voices won't show up in the picker until the app process restarts.
11. For a much more natural voice, use the **Premium Voice (ElevenLabs)** section: flip on *Use premium voice*, paste your [ElevenLabs API key](https://elevenlabs.io), then browse the list of **native Japanese voices** pulled from ElevenLabs' Voice Library. Tap the speaker next to any voice to hear a **free sample** (no quota used), and tap a voice to select it — this adds it to your ElevenLabs account and uses it for synthesis. Premium audio is fetched over the network and cached on-device, so replays and previously-heard saved sentences work offline. When the toggle is off, you're offline, or anything fails, the app falls back to the on-device voice automatically. Synthesis uses your ElevenLabs quota and costs a small amount per play.

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

- **Study-first flow** — paste a sentence and the Japanese appears automatically after a short pause. The English translation stays hidden behind a **Show translation** button so you can attempt the sentence yourself first.
- **Toggleable furigana** — off by default so you can practice reading the kanji unaided. Tap the book icon in the toolbar to flip hiragana readings on above each kanji segment, with kanji compounds kept together. The setting persists across launches. Words and kanji you've marked Known stay un-furigana'd even when the toggle is on, so graduated items don't clutter the reading.
- **Tap any underlined word** in the Japanese display to see its kana reading and a contextual English definition in a bottom sheet, with a speaker button to hear just that word. (Definitions are fetched in a second background pass — words become underlined and tappable a moment after the sentence appears.)
- **Tap a kanji** inside the word panel to drill into a per-character view: meaning, on'yomi/kun'yomi readings, a memorable note, and an animated stroke order diagram (stroke data from [KanjiVG](https://kanjivg.tagaini.net), CC BY-SA 3.0, fetched on demand and cached locally).
- **Persistent caching** of word definitions and per-kanji info on-device — once Claude has explained a word or kanji once, future appearances are instant (and free). Polysemous words (走る "to run" vs "to rush", 開く "to open" vs "to bloom") are detected by Claude on each fetch and deliberately *not* cached, so you always get a context-appropriate definition for them. Cache lives in the app's Application Support directory so it survives restarts.
- **Exposure counters** — every time you translate a sentence, each word's and each kanji's appearance is recorded on-device. Tapping a word or kanji shows "Seen N times" in the top-left of its modal, so you can gauge familiarity at a glance. Counts persist across app restarts.
- **Progress page** — a chart-bar icon in the toolbar opens a stats sheet summarising your study so far: total unique words and kanji you've been exposed to, how many you've marked Known, a stacked familiarity bar (Unknown / Familiar / Known) for each, and your top 25 most-seen words and kanji ranked by exposure count. Each row in the top-seen lists is tappable to reopen the standard word or kanji modal, so the Progress page is also a fast jump-to-anything browser.
- **External dictionary handoff** — every word and kanji modal includes two small lookup buttons:
  - *Look up in Nihongo* — opens the word or kanji directly in [Nihongo - Japanese Dictionary](https://apps.apple.com/us/app/nihongo-japanese-dictionary/id881697245) (if installed) via universal link, or falls back to the web dictionary page otherwise. Useful for richer definitions, example sentences, and flashcard export.
  - *Look up in Jisho* — opens the word or kanji in [Jisho.org](https://jisho.org) in Safari. Kanji links jump straight to the kanji detail page (readings, components, stroke order) via Jisho's `#kanji` filter.
- **Saved sentences & library** — bookmark any parsed sentence with the bookmark button on the sentence card; a books icon in the toolbar opens your library. Each saved sentence keeps its full parse (furigana + per-word definitions), so reopening one is instant and works offline — tap to reload it into the main screen, swipe to delete. Saved sentences persist across app restarts.
- **Reading drill** — a graduation-cap toggle in the toolbar hides all furigana and turns each word into a tap-to-reveal reading quiz: tap to show just the reading above a word, tap again to hide. A quick way to test yourself on readings without opening the definition modal.
- **Activity & streaks** — the Progress page tracks how many sentences you parse each day, surfacing your current day streak, total study sessions completed, total days studied, today's count, and two last-14-days bar charts (sentences parsed and study sessions, today highlighted in vermillion). A study session counts when a 25-minute pomodoro work block finishes, so you get credit for the focused work even if you cut the break short. Your streak survives a day where you haven't studied *yet*.
- **Export / backup** — a share button on the Progress sheet bundles everything stored on-device (word/kanji frequencies, familiarity levels, daily activity, and saved sentences) into one JSON file you can AirDrop, email, or save to Files — cheap insurance for the progress you've accumulated.
- **Familiarity levels** — set each word and each kanji to **Unknown** (default), **Familiar** (stepping stone, no behavior change), or **Known** via a segmented control in the word and kanji modals. Words you mark Known stop showing furigana — and a word whose every kanji you've marked Known also loses its furigana, even if the word itself isn't Known. Marking a word Known does **not** mark its kanji Known (and vice versa) — the two levels are independent until you set them. Known words remain tappable in the sentence so you can demote them back if you forget. Levels persist across app restarts.
- **Pomodoro study timer** — tap **Start study** after translating a sentence to start a single 25-minute work / 5-minute break pomodoro. A pill in the top-right toolbar ticks down the time; when the 25-minute work interval ends, an alarm chime plays (repeated so it's hard to miss) and an orange break overlay locks the screen for the 5-minute break. When the break finishes the session ends automatically — it does **not** roll into another work block. Tap the close icon next to the pill to end the session early (with confirmation). The pomodoro runs alongside the main screen — the sentence, modals, and Breakdown stay fully interactive while you study.
- **Breakdown view** — once the translation is revealed, tap Breakdown to swap to a full study breakdown of the sentence: the English translation at top, then Vocabulary, Grammar, Sentence structure, and a Notes paragraph. The button disappears once you're in the breakdown — paste a new sentence to start over.
- **Spoken Japanese** — the sentence is read aloud automatically after the translation appears, and a speaker button lets you replay it any time. To sound natural *and* read correctly, the sentence is spoken mostly as natural kanji, with only the genuinely tricky words (rare or technical compounds like 精米歩合 → *seimaibuai*) swapped to their exact analyzed reading — so prosody stays natural while uncommon vocabulary is still pronounced right. Tapping a single word always plays its exact kana reading. Pick your voice and playback rate (Natural / 85% / 65%) in Settings, with a Play Sample button to preview.
- **Premium neural voice (optional)** — bring your own [ElevenLabs](https://elevenlabs.io) API key for a dramatically more natural Japanese voice. Toggle it on in Settings, paste your key, and pick from a list of **native Japanese voices** sourced from ElevenLabs' Voice Library — each with a free in-app sample so you can audition before choosing. Fetched audio is cached on-device so replays and previously-heard saved sentences play offline, and the app silently falls back to the on-device voice when premium is off, offline, or unavailable. Playback speed still honors the Natural / 85% / 65% rate setting. Word playback speaks the **kanji** form (which the premium voice reads accurately) rather than bare kana, so a word-final っ/つ isn't swallowed into a glottal stop; only rare compounds whose kanji genuinely mis-reads fall back to kana.
- **Selectable** English translation (long-press to copy)
- **In-app API-key management** via the gear icon, with Keychain storage

## Visual identity

A calm Japanese-inspired palette: deep indigo (kon-iro) for the primary accent, warm paper-cream for the background, vermillion (shu-iro) reserved for celebratory accents. Content sits on translucent material cards with soft shadows. Subtle motion: the pomodoro pill ticks its digits, the break overlay scale-fades in. Auto-adapts to dark mode.

## Tech stack

- SwiftUI (iPadOS 26+), no third-party dependencies
- Anthropic Messages API (`claude-sonnet-4-6`) via `URLSession`
- iOS Keychain (`Security` framework) for API key storage (Anthropic + optional ElevenLabs)
- `AVSpeechSynthesizer` (`AVFoundation`) for on-device Japanese TTS, with an optional [ElevenLabs](https://elevenlabs.io) neural-voice path (`AVAudioPlayer` + on-device MP3 cache)
- Native SwiftUI stroke renderer (`Path` trim animation on a 109-unit canvas with grid + numbered badges)
- Stroke order SVGs from [KanjiVG](https://kanjivg.tagaini.net) (CC BY-SA 3.0), fetched on demand and cached locally
- Custom SwiftUI `Layout` for furigana flow-wrapping

## Credits

Stroke order data is provided by the [KanjiVG project](https://kanjivg.tagaini.net) by Ulrich Apel and contributors, released under [Creative Commons BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). This app fetches individual SVG files on demand and does not redistribute the dataset.

## Privacy

Japanese sentences you translate are sent to Anthropic's API for processing (subject to [Anthropic's data-handling policies](https://www.anthropic.com/legal/privacy)). Nothing is stored on a server controlled by this app, and nothing is sent anywhere else.

import Foundation
import Observation
import os

/// Counts in-flight AI requests — all four call types, both providers, background
/// prefetch batches included — so the toolbar can show a "talking to the AI"
/// indicator. Incremented/decremented at the two send choke points
/// (`sendMessage`, `sendKanjiInfoMessage`).
@MainActor
@Observable
final class AIActivity {
    static let shared = AIActivity()
    private init() {}

    private(set) var activeRequests = 0
    var isActive: Bool { activeRequests > 0 }

    func begin() { activeRequests += 1 }
    func end() { activeRequests = max(0, activeRequests - 1) }
}

/// Which AI service powers the four Claude/ChatGPT calls (translate, definitions, kanji info,
/// breakdown). Chosen in Settings; stored in UserDefaults under `aiProvider`. The whole app
/// uses a single provider at a time — there is no per-call-type selection.
nonisolated enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        }
    }
}

nonisolated struct FuriganaSegment: Codable {
    let text: String
    let reading: String?
}

nonisolated struct Word: Codable {
    let text: String
    let reading: String
    let furigana: [FuriganaSegment]
    var definition: String?

    /// Set by pass 1: `true` when the word's kanji reading is uncommon/non-obvious enough that
    /// a TTS engine would likely mispronounce it (rare or technical compounds, unusual name
    /// readings, ateji/gikun — e.g. 精米歩合 → せいまいぶあい). Sentence speech swaps just these
    /// words to their kana reading while leaving common words as kanji, so the bulk of the
    /// sentence keeps natural prosody. `nil`/`false` → speak the surface form. Optional so old
    /// saved sentences and responses missing the field decode fine (treated as `false`).
    let ttsKana: Bool?

    enum CodingKeys: String, CodingKey {
        case text, reading, furigana, definition
        case ttsKana = "tts_kana"
    }

    init(text: String, reading: String, furigana: [FuriganaSegment], definition: String? = nil, ttsKana: Bool? = nil) {
        self.text = text
        self.reading = reading
        self.furigana = furigana
        self.definition = definition
        self.ttsKana = ttsKana
    }

    /// Kana to speak when pronouncing this word *in isolation* (the per-word definition
    /// button). A lone uncommon kanji compound (e.g. 精米歩合) has no surrounding context for
    /// a TTS engine to lean on, so the guaranteed-correct pass-1 `reading` is used; falls back
    /// to the surface form for pure-kana/punctuation words.
    func spokenText() -> String {
        let kana = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        return kana.isEmpty ? text : kana
    }
}

nonisolated extension Array where Element == Word {
    /// The sentence prepared for TTS: natural kanji surface forms throughout, except words
    /// pass 1 flagged (`ttsKana == true`) as having tricky readings, which are swapped to their
    /// kana so they're pronounced correctly without flattening the whole sentence to kana.
    ///
    /// Arabic digits are deliberately left as-is (not converted to kana). Substituting a kana
    /// number-reading into the kanji text fixes the reading but makes the engine phrase the kana
    /// as its own chunk, audibly breaking sentence prosody (pauses in the wrong places). Feeding
    /// raw digits keeps the natural phrasing at the cost of an occasional mis-read number — a
    /// tradeoff chosen in favor of naturalness (see the speech-input note in CLAUDE.md).
    func sentenceSpeechText() -> String {
        map { $0.ttsKana == true ? $0.spokenText() : $0.text }.joined()
    }
}

nonisolated struct KanjiInfo: Codable {
    /// A short vocabulary word that uses the kanji, for context.
    struct Example: Codable {
        let word: String
        let reading: String
        let meaning: String
    }

    let character: String
    let meanings: [String]
    let onyomi: [String]
    let kunyomi: [String]
    /// No longer requested — superseded by `mnemonic`. Kept so any entry that
    /// still carries one decodes.
    let note: String?
    /// JLPT level 5 (N5, easiest) through 1 (N1); nil when the kanji is not on
    /// any list. Per the widely-used community lists — the JLPT stopped
    /// publishing official kanji lists in 2010.
    let jlpt: Int?
    /// Visible parts of the kanji with a learner keyword each, e.g. "尸 flag".
    /// Filled in before `mnemonic` so the story can only use real components.
    /// `var` so the mnemonic editor can record the parts the user hand-picked.
    var components: [String]?
    /// Component-based story linking the kanji's shape to its meaning.
    /// `var` so the mnemonic editor can save a story the user wrote themselves.
    var mnemonic: String?
    let example: Example?
    /// When this entry was fetched from the model. Drives the newest-wins merge of
    /// the CloudKit-shared kanji-info cache (shared with the kanji-study app) so a
    /// regenerated mnemonic replaces older entries everywhere. Nil = legacy entry,
    /// which loses to any timestamped one.
    var fetchedAt: Date?
    /// True when the mnemonic was written by the user or generated from components
    /// they hand-picked in the mnemonic editor. Pinned entries are never replaced by
    /// automatic batch fetches, and `DefinitionCache.shouldAdopt` only lets a *pinned*
    /// newer entry replace them — so model output never silently overwrites the
    /// user's own words, here or on any other device.
    ///
    /// Optional on purpose: absent on the wire means "an ordinary fetched entry", so
    /// the JSON shape is unchanged for everything else and older installs (and older
    /// builds of the kanji-study app) decode it fine. The kanji-study app has the
    /// identical field and honours it on its own merge, which is what makes pinning
    /// survive a round-trip through either app.
    var pinned: Bool?
}

nonisolated struct TranslationResult {
    let words: [Word]
    let englishTranslation: String
    /// A more literal, grammar-following rendering shown above the natural translation.
    /// May be empty if the model omitted it (defensive — the UI just hides the literal block).
    let literalTranslation: String
}

nonisolated enum TranslationError: LocalizedError {
    case missingAPIKey
    case network(Error)
    case apiError(status: Int, message: String)
    case decodingFailed
    case invalidResponseFormat(String)
    /// HTTP 200 with no `text` block. Thinking is billed against `max_tokens`, so a
    /// long deliberation can consume the whole budget and the response is truncated
    /// before any text is emitted; a `refusal` looks identical from the outside.
    /// Carries `stop_reason` so the two are told apart instead of surfacing as
    /// "couldn't parse the JSON", which is what an empty string decodes to, plus a
    /// rendering of `stop_details` (the refusal category and explanation) so a
    /// declined request says *why* instead of just "declined".
    case emptyResponse(stopReason: String?, detail: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Tap the gear icon to add one."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let status, let message):
            return "API error (\(status)): \(message)"
        case .decodingFailed:
            return "Couldn't read the response from the AI service."
        case .invalidResponseFormat(let detail):
            return "Couldn't parse the model's JSON response: \(detail)"
        case .emptyResponse(let stopReason, let detail):
            let suffix = detail.map { " (\($0))" } ?? ""
            switch stopReason {
            case "max_tokens":
                return "The model used its whole budget thinking and ran out of room to answer. Try again."
            case "refusal":
                return "The model declined to answer this one\(suffix). Try again, or reword the mnemonic request."
            default:
                return "The model returned an empty response\(stopReason.map { " (\($0))" } ?? "")\(suffix). Try again."
            }
        }
    }
}

/// Stateless; `nonisolated` so its prompts/constants are usable from the `@concurrent`
/// network helpers, and its async methods run on whichever actor calls them.
nonisolated struct TranslationService {
    private static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "claude-sonnet-4-6"
    private static let openAIModel = "gpt-4.1"
    /// Kanji info (mnemonics) always uses Opus 5 with high-effort thinking, regardless
    /// of the AI-provider switch — Terry chose mnemonic quality over latency, matching
    /// the kanji-study app. Requires the Anthropic key even when the provider is OpenAI.
    private static let kanjiInfoModel = "claude-opus-5"
    /// "New mnemonic" rerolls go one tier higher — Fable (Mythos-class, above Opus).
    /// Some Opus mnemonics are still weak, and a reroll is the user explicitly
    /// saying "do better", so the single-kanji retry is worth the top model.
    private static let mnemonicRerollModel = "claude-fable-5"
    /// Opus 5 with thinking can take a couple of minutes; the default URLRequest
    /// timeout is 60 s, which is not enough.
    private static let kanjiInfoTimeout: TimeInterval = 300
    /// `max_tokens` covers thinking AND the answer. The answer here is tiny (a few
    /// hundred tokens per kanji); the budget exists for the thinking. At 16000 a
    /// constrained reroll could spend the lot deliberating and get truncated before
    /// writing anything, which surfaced as a bogus "couldn't parse the JSON". This is
    /// a ceiling, not a charge — unused headroom costs nothing, while a truncated
    /// request bills for the thinking and returns nothing at all.
    private static let kanjiInfoMaxTokens = 32_000
    private static let anthropicVersion = "2023-06-01"
    private static let log = Logger(subsystem: "com.terrydonaghe.NihongoPro", category: "ai")

    /// The currently-selected AI provider, read live from UserDefaults so a change in Settings
    /// takes effect on the next call without re-instantiating the service. Defaults to Claude.
    static var provider: AIProvider { AppSettings.aiProvider }

    private static let translationSystemPrompt = """
    You are a Japanese language assistant. For each Japanese passage the user sends — one sentence, or a few short ones such as a manga speech bubble — respond with exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary).

    The JSON has three fields:

    "words": an array of word objects covering the entire input in order. Concatenating each word's "text" must reproduce the input exactly (including punctuation and whitespace). Each word object has:
      - "text": the surface form of the word as written (e.g., "今日", "良い", "は", "。")
      - "reading": the full hiragana reading of the word (always provided; for words with no kanji, this equals "text")
      - "furigana": an array of {text, reading} display segments for the word. "reading" is the hiragana reading for kanji-only segments and null for kana/punctuation segments. Concatenating the segments' "text" must equal the word's "text".
      - "tts_kana": a boolean for text-to-speech. Set true ONLY when the word's kanji reading is uncommon or non-obvious enough that a Japanese TTS engine would likely mispronounce it — e.g. rare or technical/specialist compounds (精米歩合 → せいまいぶあい), unusual proper-noun/name readings, ateji, or gikun. Set false for ordinary everyday vocabulary whose reading a TTS engine handles reliably (今日, 良い, 天気, 食べる, particles, copulas) and for any word with no kanji. When unsure, prefer false. This flag controls whether the sentence is spoken using the kanji (false) or the kana reading (true) for that word; over-flagging makes speech sound flat, so be conservative.

    Do NOT include definitions in this response — definitions are fetched separately.

    Segmentation rules:
      - Treat each grammatical word as one entry: nouns, verbs (including fully conjugated forms), adjectives, particles (は, が, を, に, etc.), copulas (です, だ), auxiliary verbs, etc.
      - Within a word, split furigana segments so kanji-only and kana-only portions are separate (e.g., 良い -> [{text:"良", reading:"よ"}, {text:"い", reading:null}])
      - Whitespace and punctuation each get their own word entry
      - Readings must be hiragana only (no katakana, no romaji)

    "translation": a natural, fluent English translation of the full input. When the input has multiple sentences, translate them all, in order.

    "literal_translation": a more literal, grammar-following English rendering of the input (each sentence in order). It must:
      - Preserve the Japanese word/phrase order (topic and other elements first, verb or copula LAST, just as in the Japanese).
      - Convey the function of particles through natural English phrasing rather than bracketed labels: は as "as for X" or "X (topic)" only when it reads naturally, を by placing the object in its Japanese position, に as "to"/"at"/"for", と as "with"/"and", へ as "toward", から as "from", まで as "until/to", の as "'s"/"of", で as "by"/"with"/"at", も as "also/even".
      - Supply subjects or objects that Japanese omits in parentheses, e.g. "(I)", "(it)".
      - Stay readable as English — do NOT use brackets, slashes, glosses, interlinear notation, or romaji. It is a readable sentence that simply follows the Japanese structure, not a word-by-word code.
      - Keep tense/politeness from the verb but you need not reproduce honorific nuance.

    JSON escaping: every string value must be valid JSON. If the input contains an ASCII double-quote character ("), it must appear as \\" inside the relevant "text", "reading", and "furigana" string values. Backslashes must appear as \\\\. Typographic/curly quotes (" " ' ') and the fullwidth quotation marks (「」『』) do NOT need escaping. Treat unusual symbols (®, ™, ・, etc.) as their own word entries with reading equal to text.

    Example for input "今日は良い天気ですね。":
    {"words":[{"text":"今日","reading":"きょう","furigana":[{"text":"今日","reading":"きょう"}],"tts_kana":false},{"text":"は","reading":"は","furigana":[{"text":"は","reading":null}],"tts_kana":false},{"text":"良い","reading":"よい","furigana":[{"text":"良","reading":"よ"},{"text":"い","reading":null}],"tts_kana":false},{"text":"天気","reading":"てんき","furigana":[{"text":"天気","reading":"てんき"}],"tts_kana":false},{"text":"です","reading":"です","furigana":[{"text":"です","reading":null}],"tts_kana":false},{"text":"ね","reading":"ね","furigana":[{"text":"ね","reading":null}],"tts_kana":false},{"text":"。","reading":"。","furigana":[{"text":"。","reading":null}],"tts_kana":false}],"translation":"It's nice weather today, isn't it?","literal_translation":"As for today, (it) is good weather, isn't it?"}

    Example of a word that needs the flag (rare/technical reading): for the word 精米歩合 the object would be {"text":"精米歩合","reading":"せいまいぶあい","furigana":[{"text":"精米歩合","reading":"せいまいぶあい"}],"tts_kana":true}.
    """

    private static let definitionsSystemPrompt = """
    You are a Japanese language assistant. The user will send a JSON object containing a Japanese sentence and an ordered list of its words. Each word is an object {"text", "reading"} where "reading" is the authoritative hiragana reading of that word in this sentence. Return exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary).

    Response shape:
    {"definitions": [...], "context_dependent": [...]}

    "definitions" must be an array of strings (or null) with the **same length and order** as the input "words" array. For each word, provide a concise English definition in the context of the sentence (1-2 phrases, e.g., "today", "good, fine", "topic-marking particle"). Use null for pure punctuation marks and standalone whitespace.

    Treat each word's provided "reading" as authoritative — it overrides any reading you might infer from the kanji. This matters most for proper nouns and names: when a definition includes a romanized form, romanize **from the provided reading**, never from a guessed kanji reading. For example, the word {"text":"安青錦","reading":"あおにしき"} is the sumo wrestler "Aonishiki" — romanize it as "Aonishiki", not "Yasuaonishiki".

    "context_dependent" must be a same-length, same-order array of booleans. For each word, set **true** if a competent speaker would translate it meaningfully differently in different common contexts (the word is polysemous and a cached definition would mislead in other sentences); set **false** if the word has one dominant meaning that fits most contexts. Use false for punctuation and grammatical particles.

    Polysemy guidance:
    - false (one dominant sense): 今日 (today), 食べる (to eat), 雨 (rain), 学校 (school), 美しい (beautiful), all particles (は, が, の, に, を), all copulas (です, だ), all sentence-final particles (ね, よ, か)
    - true (multiple senses depending on context): 走る ("to run [vehicle/person]" vs "to rush [errand]" vs "to extend [line]"), 開く ("to open" vs "to bloom"), 持つ ("to hold/carry" vs "to own/have" vs "to last"), 出る ("to leave" vs "to appear" vs "to attend"), 取る ("to take" vs "to choose" vs "to remove"), 立つ ("to stand" vs "to be erected" vs "to depart"), 上がる ("to go up" vs "to be finished" vs "to enter [a house]")

    Example input:
    {"sentence":"今日は良い天気ですね。","words":[{"text":"今日","reading":"きょう"},{"text":"は","reading":"は"},{"text":"良い","reading":"よい"},{"text":"天気","reading":"てんき"},{"text":"です","reading":"です"},{"text":"ね","reading":"ね"},{"text":"。","reading":"。"}]}

    Example response:
    {"definitions":["today","topic-marking particle","good, fine","weather","polite copula (\\"is/are\\")","sentence-final particle seeking agreement (\\"isn't it?\\")",null],"context_dependent":[false,false,false,false,false,false,false]}
    """

    private static let kanjiInfoSystemPrompt = """
    You are a Japanese kanji reference for an adult learner. The user will send a JSON array of kanji characters (up to 8). Return exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary), containing one entry per input kanji in the same order.

    Response shape:
    {"kanji":[{"character":"X","meanings":["...","..."],"onyomi":["...","..."],"kunyomi":["...","..."],"jlpt":5,"components":["...","..."],"mnemonic":"...","example":{"word":"...","reading":"...","meaning":"..."}}]}

    Fields for each entry:
    - "character": the input kanji (echo it back).
    - "meanings": 1-3 short English meanings (e.g., ["heaven","sky"]).
    - "onyomi": common on'yomi (Chinese-derived) readings in katakana. Use an empty array if none are commonly used.
    - "kunyomi": common kun'yomi (native Japanese) readings in hiragana. Use a period to mark okurigana boundaries (e.g., "た.べる"). Use an empty array if none are commonly used.
    - "jlpt": the kanji's JLPT level as an integer from 5 (N5, easiest) to 1 (N1, hardest), per the widely-used unofficial post-2010 JLPT kanji lists. Use null if the kanji does not appear on any JLPT list (rare kanji, name-only kanji).
    - "components": the parts a learner can actually SEE in the standard printed form, top-to-bottom / left-to-right, each as "<part> <keyword>" (e.g. "尸 flag", "衣 clothes", "亻 person"). 1-4 entries. Use only real, visible parts — never a part that merely resembles or historically derives from something that is not in the glyph. Use the widely-used learner keyword for each part. For a simple pictograph, one entry naming the kanji itself is fine.
    - "mnemonic": one or two sentences (max ~40 words) that help the learner recall the kanji's PRIMARY MEANING from its shape. Rules: (1) use ONLY the parts listed in "components", and every component you mention must be written as its character; (2) build a cause-and-effect scene where those parts together PRODUCE the meaning — the meaning must be the punchline, not a label bolted on; (3) be concrete and visual; no vague phrases like "a sweeping motion", "a component suggesting", "something like"; (4) do not merely restate the meaning or retell an etymology unless that etymology is itself a vivid, coherent picture. If the standard decomposition is genuinely unhelpful, it is acceptable to use a simpler visual reading of the overall shape, but say so plainly.
    - "example": one common, useful vocabulary word containing the kanji, as {"word","reading","meaning"}: "word" in kanji/kana as normally written, "reading" entirely in hiragana, "meaning" a short English gloss. Prefer an everyday word a learner is likely to meet; the target kanji's own reading in that word should be one of the listed readings when possible.

    A bad mnemonic (do not do this) for 展: "A corpse 尸 over a field 田 with a sweeping motion below — imagine a scroll being unrolled across a field." It names a part that is not in the glyph (田), hedges ("a sweeping motion"), and the parts never lead to the meaning.
    A good mnemonic for 展: components ["尸 flag", "廿 twenty", "衣 clothes"]; "Under a flag 尸, twenty 廿 sets of clothes 衣 are spread out on a long table for everyone to see — a display, unfolded and expanded."

    Example input: ["天","窓"]

    Example response:
    {"kanji":[{"character":"天","meanings":["heaven","sky","celestial"],"onyomi":["テン"],"kunyomi":["あめ","あま"],"jlpt":5,"components":["一 one","大 big"],"mnemonic":"A big 大 person stretching up with one 一 flat line over their head: the one thing even the biggest person can't reach past is the sky.","example":{"word":"天気","reading":"てんき","meaning":"weather"}},{"character":"窓","meanings":["window"],"onyomi":["ソウ"],"kunyomi":["まど"],"jlpt":3,"components":["穴 hole","厶 private","心 heart"],"mnemonic":"A hole 穴 in the wall where you keep your private 厶 heart 心 — you sit by it and let your thoughts drift outside: a window.","example":{"word":"窓口","reading":"まどぐち","meaning":"ticket window; service counter"}}]}
    """

    private static let breakdownSystemPrompt = """
    You are a Japanese language tutor. The user will send a JSON object containing a short Japanese passage (one sentence, or a few — e.g. a manga speech bubble), the words it contains (with readings and definitions where known), and an English translation. Respond with a detailed but concise vocabulary and grammar breakdown of the passage in plain Markdown. When the passage has multiple sentences, cover the vocabulary and grammar of all of them, and describe each sentence in the structure section.

    Output format, in this exact order:
    1. A section "## Vocabulary" with one bullet per content word (skip particles and punctuation). Use the form: `**WORD** (READING) — meaning [part of speech]`. List each unique content word once.
    2. A section "## Grammar" with bullets explaining the grammatical pieces (particles, verb conjugations, copulas, sentence-final particles, modifiers, etc.). Use the form: `**Pattern**: explanation`. Be specific about what each piece does and how it interacts with neighbors.
    3. A section "## Sentence structure" with a one or two sentence description of how the parts fit together (topic/comment, modifier/head, etc.).
    4. A section "## Notes" with one short paragraph (2-4 sentences) summarizing what the sentence is doing — register/politeness level, tense/mood, conversational role, anything notable about the style.

    Output ONLY the Markdown — start directly with the "## Vocabulary" heading. No preamble before it, no code fences, no commentary at the end.

    Example input:
    {"sentence":"今日は良い天気ですね。","words":[{"text":"今日","reading":"きょう","definition":"today"},{"text":"は","reading":"は","definition":"topic-marking particle"},{"text":"良い","reading":"よい","definition":"good, fine"},{"text":"天気","reading":"てんき","definition":"weather"},{"text":"です","reading":"です","definition":"polite copula"},{"text":"ね","reading":"ね","definition":"sentence-final particle for agreement"},{"text":"。","reading":"。","definition":null}],"translation":"It's nice weather today, isn't it?"}

    Example response:
    ## Vocabulary
    - **今日** (きょう) — today [noun]
    - **良い** (よい) — good, fine [i-adjective]
    - **天気** (てんき) — weather [noun]

    ## Grammar
    - **は (topic-marking particle)**: marks 今日 as the topic — what the rest of the sentence comments on. Pronounced "wa" when used as a particle.
    - **良い + 天気 (attributive adjective + noun)**: i-adjectives modify nouns directly in their dictionary form, with no linking word between them.
    - **です (polite copula)**: closes the sentence in a polite register. With an i-adjective + noun construction, です serves a softening/polite role rather than carrying the predication itself.
    - **ね (sentence-final particle)**: seeks agreement or shared feeling from the listener — closest English equivalents are "isn't it?" or "right?"

    ## Sentence structure
    [Topic 今日 は] + [adjective + noun: 良い 天気] + [polite copula です] + [agreement particle ね]. Literally: "As for today, [it]'s nice weather, isn't it?"

    ## Notes
    A casual but polite weather remark using the topic-comment structure typical of Japanese. The polite copula です places it in the polite register (丁寧語), and the sentence-final ね invites the listener to agree — a very common opener in conversation.
    """

    func translate(_ japanese: String) async throws -> TranslationResult {
        do {
            return try await translateAttempt(japanese)
        } catch TranslationError.invalidResponseFormat {
            let sanitized = Self.sanitizeForJSON(japanese)
            return try await translateAttempt(sanitized)
        }
    }

    private func translateAttempt(_ japanese: String) async throws -> TranslationResult {
        let rawText = try await sendMessage(
            systemPrompt: Self.translationSystemPrompt,
            userMessage: japanese,
            maxTokens: 16384
        )
        let jsonText = Self.extractJSON(from: rawText)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw TranslationError.invalidResponseFormat("non-UTF8 response — got: \(Self.previewSnippet(rawText))")
        }
        do {
            let response = try JSONDecoder().decode(TranslationResponse.self, from: jsonData)
            let trimmedTranslation = response.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLiteral = (response.literalTranslation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return TranslationResult(
                words: response.words,
                englishTranslation: trimmedTranslation,
                literalTranslation: trimmedLiteral
            )
        } catch {
            let detail = Self.decoderErrorDetail(error)
            throw TranslationError.invalidResponseFormat("\(detail) — got: \(Self.previewSnippet(rawText))")
        }
    }

    func fetchKanjiInfo(kanji: Character) async throws -> KanjiInfo {
        if let cached = await DefinitionCache.shared.kanjiInfo(for: kanji) {
            return cached
        }
        guard let info = try await fetchKanjiInfoBatch([kanji]).first else {
            throw TranslationError.invalidResponseFormat("response contained no entry for \(kanji)")
        }
        return info
    }

    /// Replaces the cached entry for one kanji with a fresh lookup, telling the model
    /// which mnemonic the user rejected so it writes a different one.
    func regenerateKanjiInfo(kanji: Character) async throws -> KanjiInfo {
        let previous = await DefinitionCache.shared.kanjiInfo(for: kanji)?.mnemonic
        var note = "The learner found the previous mnemonic for \(kanji) confusing and wants a different, clearer one."
        if let previous, !previous.isEmpty {
            note += " Do not reuse this story: \"\(previous)\""
        }
        guard let info = try await fetchKanjiInfoBatch(
            [kanji],
            extraInstruction: note,
            model: Self.mnemonicRerollModel
        ).first else {
            throw TranslationError.invalidResponseFormat("response contained no entry for \(kanji)")
        }
        return info
    }

    /// Rerolls one kanji constrained to the components the user hand-picked in the
    /// mnemonic editor (each already labelled "氵 water"). Uses the reroll model — the
    /// user is explicitly asking for a better story — and pins the result, since a
    /// mnemonic built from parts they curated shouldn't lose to a machine fetch on
    /// another device or in the kanji-study app.
    func regenerateKanjiInfo(kanji: Character, using components: [String]) async throws -> KanjiInfo {
        let previous = await DefinitionCache.shared.kanjiInfo(for: kanji)?.mnemonic
        let note = Self.componentInstruction(kanji: kanji, components: components, rejecting: previous)
        guard let info = try await fetchKanjiInfoBatch(
            [kanji],
            extraInstruction: note,
            model: Self.mnemonicRerollModel,
            pin: true
        ).first else {
            throw TranslationError.invalidResponseFormat("response contained no entry for \(kanji)")
        }
        return info
    }

    /// User-message suffix constraining a reroll to hand-picked parts. The chosen
    /// labels are echoed back into `components` verbatim so the keywords the user saw
    /// in the picker are the ones that end up on the card.
    ///
    /// Deliberately an *extra instruction* rather than a `kanjiInfoSystemPrompt`
    /// change: the system prompt stays byte-identical to the kanji-study app's, so
    /// there is nothing to mirror when this wording changes.
    static func componentInstruction(kanji: Character, components: [String],
                                     rejecting previous: String?) -> String {
        let list = "[" + components.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        var text = """
        The learner has hand-picked the exact components the mnemonic for \(kanji) must be built from. \
        Set "components" to exactly this list, verbatim and in this order: \(list). \
        Write the mnemonic using ONLY these parts: every one must appear in the story written as its \
        character, and no other part or shape may be mentioned. They must still combine into a \
        cause-and-effect scene that lands on the kanji's primary meaning. Keep all other fields accurate as usual.
        """
        if let previous, !previous.isEmpty {
            text += " Do not reuse this story: \"\(previous)\""
        }
        return text
    }

    /// Fetches up to `KanjiInfoPrefetcher.batchSize` kanji in one Opus request (same
    /// batch prompt as the kanji-study app) and caches every returned entry, stamped
    /// `fetchedAt` for the newest-wins shared-cache merge. Used by the modal fetch
    /// (batch of 1), regenerate, and the background prefetcher.
    ///
    /// Pinned entries are safe from the prefetcher for free: it re-checks the cache
    /// per kanji before fetching, and a pinned entry is by definition already cached.
    /// Only the two user-initiated reroll paths reach a kanji that already has info.
    func fetchKanjiInfoBatch(
        _ kanji: [Character],
        extraInstruction: String? = nil,
        model: String = TranslationService.kanjiInfoModel,
        pin: Bool = false
    ) async throws -> [KanjiInfo] {
        guard !kanji.isEmpty else { return [] }
        var userMessage = "[" + kanji.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        if let extraInstruction {
            userMessage += "\n\n" + extraInstruction
        }
        // An empty response gets one retry. A `max_tokens` truncation is transient —
        // thinking length varies run to run — so the same model usually answers the
        // second time. A `refusal` is not: the classifier is deterministic on the
        // input, so re-asking the same model just refuses again (that is exactly
        // what the old same-model retry did on a Fable reroll). Fable's classifiers
        // cover more categories than Opus 5's, and the server-side `fallbacks:
        // "default"` evidently didn't rescue the request (some categories fall back
        // to nothing), so a refused reroll retries on the Opus fetch model instead.
        // Only this error is retried; a bad key or a malformed body would just fail
        // the same way twice.
        let rawText: String
        do {
            rawText = try await sendKanjiInfoMessage(userMessage: userMessage, model: model)
        } catch let error as TranslationError {
            guard case .emptyResponse(let stopReason, let detail) = error else { throw error }
            let refused = stopReason == "refusal"
            let retryModel = (refused && model != Self.kanjiInfoModel) ? Self.kanjiInfoModel : model
            let why = (stopReason ?? "no stop_reason") + (detail.map { "; \($0)" } ?? "")
            Self.log.warning("Empty kanji-info response from \(model, privacy: .public) (\(why, privacy: .public)) — retrying on \(retryModel, privacy: .public)")
            rawText = try await sendKanjiInfoMessage(userMessage: userMessage, model: retryModel)
        }
        let jsonText = Self.extractJSON(from: rawText)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw TranslationError.invalidResponseFormat("non-UTF8 response")
        }
        let decoded: KanjiInfoBatchResponse
        do {
            decoded = try JSONDecoder().decode(KanjiInfoBatchResponse.self, from: jsonData)
        } catch {
            throw TranslationError.invalidResponseFormat(error.localizedDescription)
        }
        let wanted = Set(kanji.map(String.init))
        var results: [KanjiInfo] = []
        for var info in decoded.kanji where wanted.contains(info.character) {
            info.fetchedAt = Date()
            // Unpinned when `pin` is false — which is exactly how a confirmed
            // "New mnemonic" reroll gives up a pin the user no longer wants.
            if pin { info.pinned = true }
            if let character = info.character.first {
                await DefinitionCache.shared.setKanjiInfo(info, for: character)
            }
            results.append(info)
        }
        return results
    }

    func fetchBreakdown(sentence: String, words: [Word], translation: String) async throws -> String {
        let inputWords = words.map { BreakdownInputWord(text: $0.text, reading: $0.reading, definition: $0.definition) }
        let inputPayload = BreakdownInput(sentence: sentence, words: inputWords, translation: translation)
        let inputData = try JSONEncoder().encode(inputPayload)
        guard let inputString = String(data: inputData, encoding: .utf8) else {
            throw TranslationError.invalidResponseFormat("couldn't encode request payload")
        }

        let rawText = try await sendMessage(
            systemPrompt: Self.breakdownSystemPrompt,
            userMessage: inputString,
            maxTokens: 4096
        )
        let trimmed = Self.stripCodeFences(from: rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.invalidResponseFormat("empty breakdown response")
        }
        return trimmed
    }

    func fetchDefinitions(sentence: String, words: [Word]) async throws -> [String?] {
        var result: [String?] = Array(repeating: nil, count: words.count)
        var uncachedIndices: [Int] = []

        for (i, word) in words.enumerated() {
            if JapaneseWordFilter.isPurePunctuation(word.text) {
                continue
            }
            if let cached = await DefinitionCache.shared.definition(for: word.text) {
                result[i] = cached
            } else {
                uncachedIndices.append(i)
            }
        }

        if uncachedIndices.isEmpty {
            return result
        }

        // Send each word with its pass-1 reading so the model romanizes/disambiguates
        // from the authoritative reading rather than re-guessing the kanji (e.g. a
        // name like 安青錦 → あおにしき instead of mis-reading 安 as "yasu").
        let uncachedWords = uncachedIndices.map {
            DefinitionsInputWord(text: words[$0].text, reading: words[$0].reading)
        }
        let inputPayload = DefinitionsInput(sentence: sentence, words: uncachedWords)
        let inputData = try JSONEncoder().encode(inputPayload)
        guard let inputString = String(data: inputData, encoding: .utf8) else {
            throw TranslationError.invalidResponseFormat("couldn't encode request payload")
        }

        let rawText = try await sendMessage(
            systemPrompt: Self.definitionsSystemPrompt,
            userMessage: inputString,
            maxTokens: 4096
        )
        let jsonText = Self.extractJSON(from: rawText)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw TranslationError.invalidResponseFormat("non-UTF8 response")
        }
        let response: DefinitionsResponse
        do {
            response = try JSONDecoder().decode(DefinitionsResponse.self, from: jsonData)
        } catch {
            throw TranslationError.invalidResponseFormat(error.localizedDescription)
        }

        for (offset, originalIndex) in uncachedIndices.enumerated() where offset < response.definitions.count {
            let def = response.definitions[offset]
            result[originalIndex] = def

            let isContextDependent: Bool
            if let flags = response.contextDependent, offset < flags.count {
                isContextDependent = flags[offset]
            } else {
                isContextDependent = true
            }

            if let def, !isContextDependent {
                await DefinitionCache.shared.setDefinition(def, for: words[originalIndex].text)
            }
        }

        return result
    }

    /// Dispatches to whichever provider is selected in Settings. Both paths take the same
    /// system/user prompts and return the model's text, so the four public calls and all the
    /// JSON-extraction/parsing downstream are provider-agnostic.
    private func sendMessage(systemPrompt: String, userMessage: String, maxTokens: Int) async throws -> String {
        switch Self.provider {
        case .anthropic:
            return try await sendAnthropicMessage(systemPrompt: systemPrompt, userMessage: userMessage, maxTokens: maxTokens)
        case .openai:
            return try await sendOpenAIMessage(systemPrompt: systemPrompt, userMessage: userMessage, maxTokens: maxTokens)
        }
    }

    @concurrent
    private func sendAnthropicMessage(systemPrompt: String, userMessage: String, maxTokens: Int) async throws -> String {
        let apiKey = try AITransport.apiKey(.anthropic)
        let payload = MessagesRequest(
            model: Self.model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        let request = AIRequest(
            url: Self.anthropicEndpoint,
            headers: Self.anthropicHeaders(apiKey: apiKey),
            body: try JSONStore.encoder.encode(payload)
        )
        return try await AITransport.send(request, as: MessagesResponse.self).textOrThrow()
    }

    private static func anthropicHeaders(apiKey: String, beta: String? = nil) -> [String: String] {
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": anthropicVersion,
            "content-type": "application/json",
        ]
        if let beta { headers["anthropic-beta"] = beta }
        return headers
    }

    /// Anthropic-only path for kanji info (mnemonics): Opus 5 with high-effort thinking,
    /// server-side refusal fallback, and a long timeout — same request shape as the
    /// kanji-study app's `KanjiInfoService`. Deliberately bypasses the provider switch.
    @concurrent
    private func sendKanjiInfoMessage(
        userMessage: String,
        model: String = TranslationService.kanjiInfoModel
    ) async throws -> String {
        let apiKey = try AITransport.apiKey(.anthropic)
        let payload = KanjiInfoMessagesRequest(
            model: model,
            maxTokens: Self.kanjiInfoMaxTokens,
            system: Self.kanjiInfoSystemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        let request = AIRequest(
            url: Self.anthropicEndpoint,
            headers: Self.anthropicHeaders(apiKey: apiKey, beta: "server-side-fallback-2026-07-01"),
            body: try JSONStore.encoder.encode(payload),
            timeout: Self.kanjiInfoTimeout
        )
        return try await AITransport.send(request, as: MessagesResponse.self).textOrThrow()
    }

    /// OpenAI Chat Completions. gpt-4.1 uses the classic request shape (`max_tokens`, no hidden
    /// reasoning tokens), so the system prompt maps to a system message and the user prompt to a
    /// user message, and the assistant text comes back at `choices[0].message.content`. The error
    /// envelope is `{error:{message}}`, the same shape as Anthropic's, so `APIErrorEnvelope`
    /// decodes both.
    @concurrent
    private func sendOpenAIMessage(systemPrompt: String, userMessage: String, maxTokens: Int) async throws -> String {
        let apiKey = try AITransport.apiKey(.openai)
        let payload = OpenAIChatRequest(
            model: Self.openAIModel,
            maxTokens: maxTokens,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userMessage)
            ]
        )
        let request = AIRequest(
            url: Self.openAIEndpoint,
            headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
            body: try JSONStore.encoder.encode(payload)
        )
        let decoded = try await AITransport.send(request, as: OpenAIChatResponse.self)
        let choice = decoded.choices.first
        let text = choice?.message.content ?? ""
        // Same guard as the Anthropic path: an empty completion is its own failure,
        // not malformed JSON, and `finish_reason` ("length", "content_filter") says why.
        guard !text.isEmpty else {
            throw TranslationError.emptyResponse(stopReason: choice?.finishReason, detail: nil)
        }
        return text
    }

    static func extractJSON(from text: String) -> String {
        let stripped = stripCodeFences(from: text)
        guard let firstBrace = stripped.firstIndex(of: "{"),
              let lastBrace = stripped.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return stripped
        }
        return String(stripped[firstBrace...lastBrace])
    }

    static func stripCodeFences(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```json") {
            trimmed = String(trimmed.dropFirst("```json".count))
        } else if trimmed.hasPrefix("```markdown") {
            trimmed = String(trimmed.dropFirst("```markdown".count))
        } else if trimmed.hasPrefix("```") {
            trimmed = String(trimmed.dropFirst(3))
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func previewSnippet(_ text: String, headLimit: Int = 600, tailLimit: Int = 600) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= headLimit + tailLimit + 5 { return trimmed }
        let head = trimmed.prefix(headLimit)
        let tail = trimmed.suffix(tailLimit)
        return "\(head)…[\(trimmed.count - headLimit - tailLimit) chars elided]…\(tail)"
    }

    private static func decoderErrorDetail(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .dataCorrupted(let context):
                if let underlying = context.underlyingError as NSError?,
                   let debug = underlying.userInfo[NSDebugDescriptionErrorKey] as? String,
                   !debug.isEmpty {
                    return "dataCorrupted: \(debug)"
                }
                return "dataCorrupted: \(context.debugDescription)"
            case .keyNotFound(let key, let context):
                return "keyNotFound[\(key.stringValue)] at \(Self.formatPath(context.codingPath))"
            case .typeMismatch(let type, let context):
                return "typeMismatch[\(type)] at \(Self.formatPath(context.codingPath)): \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                return "valueNotFound[\(type)] at \(Self.formatPath(context.codingPath))"
            @unknown default:
                break
            }
        }
        let nsError = error as NSError
        if let debug = nsError.userInfo[NSDebugDescriptionErrorKey] as? String, !debug.isEmpty {
            return debug
        }
        return error.localizedDescription
    }

    private static func formatPath(_ path: [CodingKey]) -> String {
        path.isEmpty ? "root" : path.map(\.stringValue).joined(separator: "/")
    }

    private static let charsToStripForJSON: Set<Character> = [
        "\"", "'",
        "\u{201C}", "\u{201D}",
        "\u{2018}", "\u{2019}",
        "\u{201E}", "\u{201A}", "\u{201F}",
        "\u{2032}", "\u{2033}",
        "\u{00AB}", "\u{00BB}",
        "\u{301D}", "\u{301E}", "\u{301F}"
    ]

    static func sanitizeForJSON(_ text: String) -> String {
        let stripped = text.filter { !Self.charsToStripForJSON.contains($0) }
        return stripped.replacingOccurrences(of: "\\", with: "／")
    }
}

nonisolated private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

/// The Opus 5 kanji-info request: the standard Messages shape plus the server-side
/// refusal fallback (beta; the recommended default for Opus 5 requests) and
/// high-effort thinking (Terry prefers mnemonic quality over latency — the long
/// request timeout absorbs the wait instead).
nonisolated private struct KanjiInfoMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [MessagesRequest.Message]
    let fallbacks = "default"
    let outputConfig = OutputConfig(effort: "high")

    struct OutputConfig: Encodable { let effort: String }

    enum CodingKeys: String, CodingKey {
        case model, system, messages, fallbacks
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

nonisolated private struct MessagesResponse: Decodable {
    let content: [ContentBlock]
    /// "end_turn", "max_tokens", "refusal", … — the only way to tell a truncated
    /// response from a declined one, since both arrive as 200 with no text.
    let stopReason: String?
    /// Populated only when `stop_reason` is "refusal": the policy category
    /// ("cyber", "bio", "reasoning_extraction", …, or null), an optional
    /// explanation, and — when the server-side fallback couldn't run because the
    /// fallback model was rate-limited — the model it suggests retrying on. Purely
    /// informational; branch on `stopReason`, never on this.
    let stopDetails: StopDetails?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct StopDetails: Decodable {
        let category: String?
        let explanation: String?
        let recommendedModel: String?

        enum CodingKeys: String, CodingKey {
            case category, explanation
            case recommendedModel = "recommended_model"
        }

        /// One human-readable line for the error banner and the log, e.g.
        /// "category: cyber — <explanation>; recommended model: claude-opus-4-8".
        var summary: String? {
            var parts: [String] = []
            if let category { parts.append("category: \(category)") }
            if let explanation, !explanation.isEmpty { parts.append(explanation) }
            if let recommendedModel { parts.append("recommended model: \(recommendedModel)") }
            return parts.isEmpty ? nil : parts.joined(separator: " — ")
        }
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }

    /// The joined text blocks. Empty text is a real failure mode, not malformed
    /// JSON: on the kanji-info path thinking can eat the whole `max_tokens` budget
    /// before any text block is emitted, and on any path a refusal returns 200 with
    /// no text. Reported as `emptyResponse` so the banner is useful and the caller
    /// knows it's worth retrying.
    func textOrThrow() throws -> String {
        let text = content
            .compactMap { $0.type == "text" ? $0.text : nil }
            .joined()
        guard !text.isEmpty else {
            throw TranslationError.emptyResponse(stopReason: stopReason, detail: stopDetails?.summary)
        }
        return text
    }
}

nonisolated private struct OpenAIChatRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
    }
}

nonisolated private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
        /// "stop", "length", "content_filter", … — carried into `emptyResponse`.
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let content: String?
    }
}

nonisolated private struct TranslationResponse: Decodable {
    let words: [Word]
    let translation: String
    let literalTranslation: String?

    enum CodingKeys: String, CodingKey {
        case words
        case translation
        case literalTranslation = "literal_translation"
    }
}

nonisolated private struct DefinitionsInput: Encodable {
    let sentence: String
    let words: [DefinitionsInputWord]
}

nonisolated private struct DefinitionsInputWord: Encodable {
    let text: String
    let reading: String
}

nonisolated private struct DefinitionsResponse: Decodable {
    let definitions: [String?]
    let contextDependent: [Bool]?

    enum CodingKeys: String, CodingKey {
        case definitions
        case contextDependent = "context_dependent"
    }
}

nonisolated private struct KanjiInfoBatchResponse: Decodable {
    let kanji: [KanjiInfo]
}

nonisolated private struct BreakdownInput: Encodable {
    let sentence: String
    let words: [BreakdownInputWord]
    let translation: String
}

nonisolated private struct BreakdownInputWord: Encodable {
    let text: String
    let reading: String
    let definition: String?
}


// MARK: - Background kanji-info prefetch

/// Quietly fills the kanji-info cache while the app is in use, so opening
/// `KanjiDetailView` is instant instead of waiting a minute on the Opus call.
/// Two feeds: the just-parsed sentence's kanji (front of the queue) and the
/// all-time seen-kanji backlog from `FrequencyTracker`, most-seen first. One
/// serial worker drains the queue in batches of `batchSize`; kanji that gain a
/// cache entry while queued (an earlier batch, a CloudKit adoption from another
/// device or the kanji-study app) are skipped at fetch time, so no Opus call is
/// ever spent on a kanji that already has info. Errors are logged, not surfaced —
/// the modal's own fetch path remains the user-visible one. (Declared here rather
/// than its own file to avoid a new pbxproj entry, like `JapaneseWordFilter`.)
@MainActor
final class KanjiInfoPrefetcher {
    static let shared = KanjiInfoPrefetcher()

    /// Kanji per request — matches the kanji-study app's batch size.
    static let batchSize = 8

    private static let log = Logger(subsystem: "com.terrydonaghe.NihongoPro", category: "prefetch")

    private let translator = TranslationService()
    /// Kanji with a batch request currently in flight, mapped to that batch's task
    /// so `ensure` can await the prefetch instead of firing a duplicate request.
    private var inFlight: [Character: Task<Void, any Error>] = [:]
    private var queue: [Character] = []
    private var queued: Set<Character> = []
    private var worker: Task<Void, Never>?

    private init() {}

    private var hasAPIKey: Bool {
        !(KeychainStore.read(account: .anthropic) ?? "").isEmpty
    }

    /// Queues kanji for background fetch. `priority` puts them at the front (the
    /// current sentence's kanji) ahead of the backlog. Cache membership is checked
    /// at fetch time, not here, so enqueueing liberally is cheap.
    func enqueue(_ kanji: [Character], priority: Bool = false) {
        guard hasAPIKey else { return }
        let fresh = kanji.filter { $0.isKanji && !queued.contains($0) && inFlight[$0] == nil }
        if !fresh.isEmpty {
            queued.formUnion(fresh)
            if priority {
                queue.insert(contentsOf: fresh, at: 0)
            } else {
                queue.append(contentsOf: fresh)
            }
        }
        startWorkerIfNeeded()
    }

    /// Queues every kanji ever seen (most-seen first) behind whatever is already
    /// queued. Called once per launch after the initial iCloud sync, so kanji whose
    /// info just arrived from another device aren't re-fetched.
    func enqueueBacklog() {
        let ordered = FrequencyTracker.shared.kanjiCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .compactMap(\.key.first)
        enqueue(ordered)
    }

    /// The modal's entry point: cached → instant; a prefetch in flight → wait for
    /// it; otherwise fetch immediately (jumping the queue).
    func ensure(_ kanji: Character) async throws -> KanjiInfo {
        if let cached = await DefinitionCache.shared.kanjiInfo(for: kanji) {
            return cached
        }
        if let batch = inFlight[kanji] {
            // Wait for the prefetch batch that includes this kanji, then re-read the
            // cache; a failed batch just falls through to a direct fetch below.
            _ = try? await batch.value
            if let cached = await DefinitionCache.shared.kanjiInfo(for: kanji) {
                return cached
            }
        }
        return try await translator.fetchKanjiInfo(kanji: kanji)
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            var batch: [Character] = []
            while batch.count < Self.batchSize, !queue.isEmpty {
                let kanji = queue.removeFirst()
                queued.remove(kanji)
                if inFlight[kanji] != nil { continue }
                if await DefinitionCache.shared.kanjiInfo(for: kanji) != nil { continue }
                batch.append(kanji)
            }
            guard !batch.isEmpty else { continue }
            let batchTask = Task { [translator, batch] in
                _ = try await translator.fetchKanjiInfoBatch(batch)
            }
            for kanji in batch { inFlight[kanji] = batchTask }
            defer { for kanji in batch { inFlight[kanji] = nil } }
            do {
                try await batchTask.value
                Self.log.info("Prefetched info for \(batch.count) kanji, \(self.queue.count) queued")
            } catch TranslationError.missingAPIKey {
                queue.removeAll()
                queued.removeAll()
            } catch {
                // Keep going: one failed batch shouldn't stall the rest.
                Self.log.warning("Prefetch batch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        worker = nil
        // An enqueue that landed while the last batch was finishing saw a non-nil
        // worker and didn't restart it — catch that here.
        startWorkerIfNeeded()
    }
}

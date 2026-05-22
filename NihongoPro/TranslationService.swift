import Foundation

struct FuriganaSegment: Decodable {
    let text: String
    let reading: String?
}

struct Word: Decodable {
    let text: String
    let reading: String
    let furigana: [FuriganaSegment]
    var definition: String?
}

struct KanjiInfo: Decodable {
    let character: String
    let meanings: [String]
    let onyomi: [String]
    let kunyomi: [String]
    let note: String?
}

struct TranslationResult {
    let words: [Word]
    let englishTranslation: String
}

enum TranslationError: LocalizedError {
    case missingAPIKey
    case network(Error)
    case apiError(status: Int, message: String)
    case decodingFailed
    case invalidResponseFormat(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Tap the gear icon to add one."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let status, let message):
            return "API error (\(status)): \(message)"
        case .decodingFailed:
            return "Couldn't read the response from Anthropic."
        case .invalidResponseFormat(let detail):
            return "Couldn't parse the model's JSON response: \(detail)"
        }
    }
}

struct TranslationService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-6"
    private static let anthropicVersion = "2023-06-01"

    private static let translationSystemPrompt = """
    You are a Japanese language assistant. For each Japanese sentence the user sends, respond with exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary).

    The JSON has two fields:

    "words": an array of word objects covering the entire input in order. Concatenating each word's "text" must reproduce the input exactly (including punctuation and whitespace). Each word object has:
      - "text": the surface form of the word as written (e.g., "今日", "良い", "は", "。")
      - "reading": the full hiragana reading of the word (always provided; for words with no kanji, this equals "text")
      - "furigana": an array of {text, reading} display segments for the word. "reading" is the hiragana reading for kanji-only segments and null for kana/punctuation segments. Concatenating the segments' "text" must equal the word's "text".

    Do NOT include definitions in this response — definitions are fetched separately.

    Segmentation rules:
      - Treat each grammatical word as one entry: nouns, verbs (including fully conjugated forms), adjectives, particles (は, が, を, に, etc.), copulas (です, だ), auxiliary verbs, etc.
      - Within a word, split furigana segments so kanji-only and kana-only portions are separate (e.g., 良い -> [{text:"良", reading:"よ"}, {text:"い", reading:null}])
      - Whitespace and punctuation each get their own word entry
      - Readings must be hiragana only (no katakana, no romaji)

    "translation": a natural, fluent English translation of the full sentence.

    Example for input "今日は良い天気ですね。":
    {"words":[{"text":"今日","reading":"きょう","furigana":[{"text":"今日","reading":"きょう"}]},{"text":"は","reading":"は","furigana":[{"text":"は","reading":null}]},{"text":"良い","reading":"よい","furigana":[{"text":"良","reading":"よ"},{"text":"い","reading":null}]},{"text":"天気","reading":"てんき","furigana":[{"text":"天気","reading":"てんき"}]},{"text":"です","reading":"です","furigana":[{"text":"です","reading":null}]},{"text":"ね","reading":"ね","furigana":[{"text":"ね","reading":null}]},{"text":"。","reading":"。","furigana":[{"text":"。","reading":null}]}],"translation":"It's nice weather today, isn't it?"}
    """

    private static let definitionsSystemPrompt = """
    You are a Japanese language assistant. The user will send a JSON object containing a Japanese sentence and an ordered list of its words. Return exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary).

    Response shape:
    {"definitions": [...]}

    "definitions" must be an array of strings (or null) with the **same length and order** as the input "words" array. For each word, provide a concise English definition in the context of the sentence (1-2 phrases, e.g., "today", "good, fine", "topic-marking particle"). Use null for pure punctuation marks and standalone whitespace.

    Example input:
    {"sentence":"今日は良い天気ですね。","words":["今日","は","良い","天気","です","ね","。"]}

    Example response:
    {"definitions":["today","topic-marking particle","good, fine","weather","polite copula (\\"is/are\\")","sentence-final particle seeking agreement (\\"isn't it?\\")",null]}
    """

    private static let kanjiInfoSystemPrompt = """
    You are a Japanese kanji reference. The user will send a single kanji character. Return exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary).

    Response shape:
    {"character":"X","meanings":["...","..."],"onyomi":["...","..."],"kunyomi":["...","..."],"note":"..."}

    Fields:
    - "character": the input kanji (echo it back).
    - "meanings": 1-3 short English meanings (e.g., ["heaven","sky"]).
    - "onyomi": common on'yomi (Chinese-derived) readings in katakana. Use an empty array if none are commonly used.
    - "kunyomi": common kun'yomi (native Japanese) readings in hiragana. Use a period to mark okurigana boundaries (e.g., "た.べる"). Use an empty array if none are commonly used.
    - "note": 1-2 sentence memorable description: visual mnemonic, etymology, or common usage pattern. Use null if nothing notable.

    Example input: 天

    Example response:
    {"character":"天","meanings":["heaven","sky","celestial"],"onyomi":["テン"],"kunyomi":["あめ","あま"],"note":"Pictograph of a person (大) with a flat line above representing the sky. Appears in many words about weather (天気) and the heavens."}
    """

    private static let breakdownSystemPrompt = """
    You are a Japanese language tutor. The user will send a JSON object containing a Japanese sentence, the words it contains (with readings and definitions where known), and an English translation. Respond with a detailed but concise vocabulary and grammar breakdown of the sentence in plain Markdown.

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
        let rawText = try await sendMessage(
            systemPrompt: Self.translationSystemPrompt,
            userMessage: japanese,
            maxTokens: 2048
        )
        let jsonText = Self.extractJSON(from: rawText)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw TranslationError.invalidResponseFormat("non-UTF8 response")
        }
        do {
            let response = try JSONDecoder().decode(TranslationResponse.self, from: jsonData)
            let trimmedTranslation = response.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            return TranslationResult(words: response.words, englishTranslation: trimmedTranslation)
        } catch {
            throw TranslationError.invalidResponseFormat(error.localizedDescription)
        }
    }

    func fetchKanjiInfo(kanji: Character) async throws -> KanjiInfo {
        let rawText = try await sendMessage(
            systemPrompt: Self.kanjiInfoSystemPrompt,
            userMessage: String(kanji),
            maxTokens: 1024
        )
        let jsonText = Self.extractJSON(from: rawText)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw TranslationError.invalidResponseFormat("non-UTF8 response")
        }
        do {
            return try JSONDecoder().decode(KanjiInfo.self, from: jsonData)
        } catch {
            throw TranslationError.invalidResponseFormat(error.localizedDescription)
        }
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

    func fetchDefinitions(sentence: String, words: [String]) async throws -> [String?] {
        let inputPayload = DefinitionsInput(sentence: sentence, words: words)
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
        do {
            let response = try JSONDecoder().decode(DefinitionsResponse.self, from: jsonData)
            return response.definitions
        } catch {
            throw TranslationError.invalidResponseFormat(error.localizedDescription)
        }
    }

    private func sendMessage(systemPrompt: String, userMessage: String, maxTokens: Int) async throws -> String {
        guard let apiKey = KeychainStore.read(), !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload = MessagesRequest(
            model: Self.model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.decodingFailed
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw TranslationError.apiError(status: http.statusCode, message: message)
        }

        let decoded: MessagesResponse
        do {
            decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw TranslationError.decodingFailed
        }

        return decoded.content
            .compactMap { $0.type == "text" ? $0.text : nil }
            .joined()
    }

    private static func extractJSON(from text: String) -> String {
        stripCodeFences(from: text)
    }

    private static func stripCodeFences(from text: String) -> String {
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
}

private struct MessagesRequest: Encodable {
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

private struct MessagesResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

private struct TranslationResponse: Decodable {
    let words: [Word]
    let translation: String
}

private struct DefinitionsInput: Encodable {
    let sentence: String
    let words: [String]
}

private struct DefinitionsResponse: Decodable {
    let definitions: [String?]
}

private struct BreakdownInput: Encodable {
    let sentence: String
    let words: [BreakdownInputWord]
    let translation: String
}

private struct BreakdownInputWord: Encodable {
    let text: String
    let reading: String
    let definition: String?
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

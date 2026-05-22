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
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```json") {
            trimmed = String(trimmed.dropFirst("```json".count))
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

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

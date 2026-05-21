import Foundation

struct FuriganaSegment: Decodable {
    let text: String
    let reading: String?
}

struct Word: Decodable {
    let text: String
    let reading: String
    let furigana: [FuriganaSegment]
    let definition: String?
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
    private static let systemPrompt = """
    You are a Japanese language assistant. For each Japanese sentence the user sends, respond with exactly one JSON object and nothing else (no preamble, no markdown fences, no commentary).

    The JSON has two fields:

    "words": an array of word objects covering the entire input in order. Concatenating each word's "text" must reproduce the input exactly (including punctuation and whitespace). Each word object has:
      - "text": the surface form of the word as written (e.g., "今日", "良い", "は", "。")
      - "reading": the full hiragana reading of the word (always provided; for words with no kanji, this equals "text")
      - "furigana": an array of {text, reading} display segments for the word. "reading" is the hiragana reading for kanji-only segments and null for kana/punctuation segments. Concatenating the segments' "text" must equal the word's "text".
      - "definition": a concise English definition of the word in this context (1-2 phrases, e.g., "today", "good, fine", "topic-marking particle"). Use null only for pure punctuation marks.

    Segmentation rules:
      - Treat each grammatical word as one entry: nouns, verbs (including fully conjugated forms), adjectives, particles (は, が, を, に, etc.), copulas (です, だ), auxiliary verbs, etc.
      - Within a word, split furigana segments so kanji-only and kana-only portions are separate (e.g., 良い -> [{text:"良", reading:"よ"}, {text:"い", reading:null}]).
      - Whitespace and punctuation each get their own word entry with definition:null.
      - Readings must be hiragana only (no katakana, no romaji).

    "translation": a natural, fluent English translation of the full sentence.

    Example for input "今日は良い天気ですね。":
    {"words":[{"text":"今日","reading":"きょう","furigana":[{"text":"今日","reading":"きょう"}],"definition":"today"},{"text":"は","reading":"は","furigana":[{"text":"は","reading":null}],"definition":"topic-marking particle"},{"text":"良い","reading":"よい","furigana":[{"text":"良","reading":"よ"},{"text":"い","reading":null}],"definition":"good, fine"},{"text":"天気","reading":"てんき","furigana":[{"text":"天気","reading":"てんき"}],"definition":"weather"},{"text":"です","reading":"です","furigana":[{"text":"です","reading":null}],"definition":"polite copula (\\"is/are\\")"},{"text":"ね","reading":"ね","furigana":[{"text":"ね","reading":null}],"definition":"sentence-final particle seeking agreement (\\"isn't it?\\")"},{"text":"。","reading":"。","furigana":[{"text":"。","reading":null}],"definition":null}],"translation":"It's nice weather today, isn't it?"}
    """

    func analyze(_ japanese: String) async throws -> TranslationResult {
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
            maxTokens: 4096,
            system: Self.systemPrompt,
            messages: [.init(role: "user", content: japanese)]
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

        let rawText = decoded.content
            .compactMap { $0.type == "text" ? $0.text : nil }
            .joined()

        let jsonText = Self.extractJSON(from: rawText)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw TranslationError.invalidResponseFormat("non-UTF8 response")
        }

        do {
            let analysis = try JSONDecoder().decode(AnalysisResponse.self, from: jsonData)
            let trimmedTranslation = analysis.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            return TranslationResult(words: analysis.words, englishTranslation: trimmedTranslation)
        } catch {
            throw TranslationError.invalidResponseFormat(error.localizedDescription)
        }
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

private struct AnalysisResponse: Decodable {
    let words: [Word]
    let translation: String
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

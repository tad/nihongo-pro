import Foundation

enum TranslationError: LocalizedError {
    case missingAPIKey
    case network(Error)
    case apiError(status: Int, message: String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Tap the gear icon to add one."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let status, let message):
            return "API error (\(status)): \(message)"
        case .decodingFailed:
            return "Couldn't read the translation response."
        }
    }
}

struct TranslationService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-6"
    private static let anthropicVersion = "2023-06-01"
    private static let systemPrompt = """
    You are a Japanese-to-English translator. Translate the user's Japanese text into natural, fluent English. \
    Output only the translation — no preamble, no romanization, no notes.
    """

    func translate(_ japanese: String) async throws -> String {
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
            maxTokens: 1024,
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

        do {
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            let text = decoded.content
                .compactMap { $0.type == "text" ? $0.text : nil }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranslationError.decodingFailed }
            return text
        } catch {
            throw TranslationError.decodingFailed
        }
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

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

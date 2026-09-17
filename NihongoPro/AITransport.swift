import Foundation

/// One POST to an AI provider, ready to send: the endpoint, its headers (the key
/// goes in here), the already-encoded JSON body, and how long to wait.
nonisolated struct AIRequest {
    var url: URL
    var headers: [String: String]
    var body: Data
    var timeout: TimeInterval = 60
}

/// The one HTTP round-trip every AI call goes through. Provider-specific work —
/// which key, which headers, what the payload and response look like — stays in
/// the caller; this handles the part that used to be copy-pasted three times:
/// network errors, the HTTP status check, the `{error:{message}}` envelope both
/// providers use, and decoding. It also counts the request in `AIActivity`, so the
/// toolbar sparkle covers every AI call by construction.
nonisolated enum AITransport {
    /// The stored key for `account`, or `TranslationError.missingAPIKey`.
    static func apiKey(_ account: KeychainStore.Account) throws -> String {
        guard let key = KeychainStore.read(account: account), !key.isEmpty else {
            throw TranslationError.missingAPIKey
        }
        return key
    }

    @concurrent
    static func send<Response: Decodable & Sendable>(_ request: AIRequest, as type: Response.Type) async throws -> Response {
        await AIActivity.shared.begin()
        defer { await AIActivity.shared.end() }

        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "POST"
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = request.body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw TranslationError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.decodingFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONStore.decoder.decode(APIErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw TranslationError.apiError(status: http.statusCode, message: message)
        }

        do {
            return try JSONStore.decoder.decode(Response.self, from: data)
        } catch {
            throw TranslationError.decodingFailed
        }
    }
}

/// `{ "error": { "message": … } }` — Anthropic and OpenAI use the same envelope.
nonisolated struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

import Foundation

/// Thin client for the ElevenLabs text-to-speech REST API.
///
/// Two calls are used by the app:
/// - `synthesize(_:voiceID:apiKey:)` returns raw MP3 audio for a sentence/word.
/// - `fetchVoices(apiKey:)` lists the account's voices to populate the Settings picker.
///
/// The key is read from the Keychain (`KeychainStore.read(account: .elevenLabs)`), never
/// stored here. All network failures throw so `SpeechService` can fall back to the on-device
/// Apple voice and the app keeps working offline.
enum ElevenLabsService {
    /// Turbo v2.5: honors `language_code` (so kanji reads as Japanese, not Chinese) AND renders
    /// the selected Voice Library voice on the standard `/v1/text-to-speech` endpoint.
    /// `eleven_v3` was tried but failed on this endpoint — synthesis errored and the app
    /// silently fell back to the robotic Apple voice (ignoring the chosen premium voice). Do
    /// NOT use `eleven_multilingual_v2` — it ignores `language_code` and mis-reads kanji as
    /// Chinese. Pair this with `apply_language_text_normalization` so natural kanji text is read
    /// correctly (the Japanese normalizer), keeping prosody natural.
    static let modelID = "eleven_turbo_v2_5"

    /// ISO 639-1 language passed as `language_code` to force Japanese normalization + pronunciation.
    static let languageCode = "ja"

    /// Fallback voice used when the user hasn't picked one in Settings yet. "Rachel" is an
    /// always-present premade voice; the Settings voice picker lets the user choose a
    /// Japanese-native voice for noticeably better pronunciation.
    static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"

    private static let base = URL(string: "https://api.elevenlabs.io/v1")!

    struct Voice: Identifiable, Decodable, Hashable {
        let voiceID: String
        let name: String

        var id: String { voiceID }

        enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case name
        }
    }

    /// A voice from the public Voice Library (`/v1/shared-voices`). Carries a `previewURL`
    /// MP3 sample that can be auditioned for free, and a `publicOwnerID` needed to add it.
    struct SharedVoice: Identifiable, Decodable, Hashable {
        let voiceID: String
        let publicOwnerID: String
        let name: String
        let accent: String?
        let descriptive: String?
        let useCase: String?
        let previewURL: String?

        var id: String { voiceID }

        /// Short human-readable subtitle, e.g. "Japanese · narration".
        var subtitle: String {
            [accent, useCase, descriptive]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(2)
                .joined(separator: " · ")
        }

        enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case publicOwnerID = "public_owner_id"
            case name, accent, descriptive
            case useCase = "use_case"
            case previewURL = "preview_url"
        }
    }

    enum ElevenLabsError: LocalizedError {
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Unexpected response from ElevenLabs."
            case let .http(code, body):
                let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return "ElevenLabs error \(code)\(snippet.isEmpty ? "" : ": \(snippet.prefix(200))")"
            }
        }
    }

    /// Returns MP3 audio bytes for `text` spoken by `voiceID`. `normalize` toggles the Japanese
    /// text normalizer — keep it on for kanji (resolves readings in context), but turn it off
    /// for pure-kana input where it has nothing to resolve and can re-mangle the sokuon.
    static func synthesize(_ text: String, voiceID: String, apiKey: String, normalize: Bool = true) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent("text-to-speech/\(voiceID)"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "language_code": languageCode,
            // Runs ElevenLabs' Japanese text normalizer over natural (kanji) text — resolves
            // kanji readings in context so we can feed real orthography (natural prosody)
            // instead of pre-flattening to kana (which reads flat/robotic). Disabled for
            // pure-kana input, where it has nothing to resolve and can re-mangle the sokuon.
            // Adds latency, but results are cached so it's a one-time cost per sentence.
            "apply_language_text_normalization": normalize,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ElevenLabsError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Lists the voices already in this account (premade + added). Used to dedupe so a
    /// previously-added library voice is reused instead of consuming another voice slot.
    static func fetchVoices(apiKey: String) async throws -> [Voice] {
        var request = URLRequest(url: base.appendingPathComponent("voices"))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ElevenLabsError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Wrapper: Decodable { let voices: [Voice] }
        return try JSONDecoder().decode(Wrapper.self, from: data).voices
    }

    /// Lists native Japanese voices from the public Voice Library. These are recorded by
    /// Japanese speakers, so paired with the multilingual model they read with native
    /// pronunciation (unlike the default English premade voices).
    static func fetchJapaneseVoices(apiKey: String) async throws -> [SharedVoice] {
        var components = URLComponents(url: base.appendingPathComponent("shared-voices"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "page_size", value: "100")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ElevenLabsError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Wrapper: Decodable { let voices: [SharedVoice] }
        return try JSONDecoder().decode(Wrapper.self, from: data).voices
    }

    /// Adds a Voice Library voice to the account, returning the new owned `voice_id` usable
    /// for text-to-speech. (Library voices can't be synthesized directly — they must be added.)
    static func addSharedVoice(publicOwnerID: String, voiceID: String, name: String, apiKey: String) async throws -> String {
        let url = base
            .appendingPathComponent("voices/add")
            .appendingPathComponent(publicOwnerID)
            .appendingPathComponent(voiceID)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["new_name": name])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ElevenLabsError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct Wrapper: Decodable { let voiceID: String; enum CodingKeys: String, CodingKey { case voiceID = "voice_id" } }
        return try JSONDecoder().decode(Wrapper.self, from: data).voiceID
    }
}

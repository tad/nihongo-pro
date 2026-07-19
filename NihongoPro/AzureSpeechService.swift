import Foundation

/// Thin client for the Azure AI Speech text-to-speech REST API.
///
/// Two calls are used by the app:
/// - `synthesize(_:voiceName:style:apiKey:region:)` returns raw MP3 audio for a sentence/word.
/// - `fetchJapaneseVoices(apiKey:region:)` lists the region's ja-JP neural voices for the
///   Settings picker.
///
/// Azure is the premium engine: the voice is locked to a `ja-JP` neural voice (no language
/// auto-detect, so kanji never reads as Chinese) and the engine uses a real Japanese
/// morphological dictionary, so common readings, the sokuon (っ/つ), and numbers are handled
/// natively rather than guessed. Some voices also support speaking styles (`StyleList`).
///
/// The key is read from the Keychain (`KeychainStore.read(account: .azure)`), never stored
/// here; the region is a plain (non-secret) UserDefaults value. All network failures throw so
/// `SpeechService` can fall back to the on-device Apple voice and the app keeps working offline.
///
/// Endpoint host is region-scoped: `https://{region}.tts.speech.microsoft.com`. Azure requires
/// a `User-Agent` header on these requests or it rejects them.
enum AzureSpeechService {
    /// Fallback ja-JP neural voice used before the user picks one. Nanami is always present in
    /// every region that offers Japanese.
    static let defaultVoice = "ja-JP-NanamiNeural"

    enum AzureError: LocalizedError {
        case missingRegion
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingRegion:
                return "No Azure region set."
            case .invalidResponse:
                return "Unexpected response from Azure Speech."
            case let .http(code, body):
                let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Azure Speech error \(code)\(snippet.isEmpty ? "" : ": \(snippet.prefix(200))")"
            }
        }
    }

    /// A ja-JP neural voice from `/cognitiveservices/voices/list`. `shortName` (e.g.
    /// `ja-JP-NanamiNeural`) is what SSML references; `displayName`/`localName` are for the picker.
    struct Voice: Identifiable, Decodable, Hashable {
        let shortName: String
        let displayName: String
        let localName: String
        let gender: String
        let locale: String
        let styleList: [String]?

        var id: String { shortName }

        /// Short subtitle for the picker row, e.g. "ななみ · Female".
        var subtitle: String {
            [localName, gender]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }

        enum CodingKeys: String, CodingKey {
            case shortName = "ShortName"
            case displayName = "DisplayName"
            case localName = "LocalName"
            case gender = "Gender"
            case locale = "Locale"
            case styleList = "StyleList"
        }
    }

    /// Returns MP3 audio bytes for `text` spoken by `voiceName` (a ja-JP ShortName). The text is
    /// wrapped in minimal SSML — no `<prosody rate>`, because playback rate is applied on the
    /// `AVAudioPlayer`, so the cached MP3 stays rate-neutral. A non-empty `style` (one of the
    /// voice's `StyleList` entries, e.g. `cheerful`) wraps the text in `<mstts:express-as>`,
    /// which needs the `mstts` namespace on `<speak>`.
    static func synthesize(_ text: String, voiceName: String, style: String = "", apiKey: String, region: String) async throws -> Data {
        guard !region.isEmpty else { throw AzureError.missingRegion }
        guard let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1") else {
            throw AzureError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        // Azure rejects TTS requests that omit a User-Agent.
        request.setValue("NihongoPro", forHTTPHeaderField: "User-Agent")

        let voice = voiceName.isEmpty ? defaultVoice : voiceName
        let escaped = escapeXML(text)
        let inner = style.isEmpty
            ? escaped
            : "<mstts:express-as style='\(style)'>\(escaped)</mstts:express-as>"
        let ssml = """
        <speak version='1.0' xmlns:mstts='https://www.w3.org/2001/mstts' xml:lang='ja-JP'><voice name='\(voice)'>\(inner)</voice></speak>
        """
        request.httpBody = Data(ssml.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AzureError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AzureError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Lists the region's neural voices and filters to `ja-JP`. Used to populate the Settings
    /// picker. (Voice availability is per-region, so this is fetched against the user's region.)
    static func fetchJapaneseVoices(apiKey: String, region: String) async throws -> [Voice] {
        guard !region.isEmpty else { throw AzureError.missingRegion }
        guard let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/voices/list") else {
            throw AzureError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("NihongoPro", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AzureError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AzureError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let voices = try JSONDecoder().decode([Voice].self, from: data)
        return voices
            .filter { $0.locale == "ja-JP" }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Escapes the five XML predefined entities so arbitrary Japanese/punctuation can't break
    /// the SSML document.
    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

import AVFoundation
import CryptoKit
import Foundation

enum SpeechRate: String, CaseIterable, Identifiable {
    case natural
    case slower
    case slowest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "Natural"
        case .slower: return "Slower (85%)"
        case .slowest: return "Slowest (65%)"
        }
    }

    var multiplier: Float {
        switch self {
        case .natural: return 1.0
        case .slower: return 0.85
        case .slowest: return 0.65
        }
    }

    static var current: SpeechRate {
        let raw = UserDefaults.standard.string(forKey: "speechRate") ?? SpeechRate.natural.rawValue
        return SpeechRate(rawValue: raw) ?? .natural
    }
}

final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?

    /// UserDefaults flag set by the Settings "Use premium voice" toggle.
    static var premiumEnabled: Bool {
        UserDefaults.standard.bool(forKey: "usePremiumVoice")
    }

    /// Voice chosen in Settings, or the ElevenLabs fallback voice when unset.
    static var selectedElevenVoiceID: String {
        let id = UserDefaults.standard.string(forKey: "elevenVoiceID") ?? ""
        return id.isEmpty ? ElevenLabsService.defaultVoiceID : id
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()

        if Self.premiumEnabled,
           let apiKey = KeychainStore.read(account: .elevenLabs),
           !apiKey.isEmpty {
            speakWithElevenLabs(trimmed, apiKey: apiKey)
        } else {
            speakWithApple(trimmed)
        }
    }

    /// Plays a remote MP3 sample (e.g. an ElevenLabs Voice Library `preview_url`). Does not
    /// touch the synthesis API, so auditioning library voices is free.
    func playPreview(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        stop()
        isSpeaking = true
        fetchTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                await self?.startPlayback(data)
            } catch is CancellationError {
                // stopped by user
            } catch {
                await self?.setSpeaking(false)
            }
        }
    }

    @MainActor
    private func setSpeaking(_ value: Bool) {
        isSpeaking = value
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        if isSpeaking { isSpeaking = false }
    }

    // MARK: - Apple (on-device) voice

    private func speakWithApple(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.selectedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * SpeechRate.current.multiplier
        synthesizer.speak(utterance)
    }

    // MARK: - ElevenLabs (premium) voice

    private func speakWithElevenLabs(_ text: String, apiKey: String) {
        let voiceID = Self.selectedElevenVoiceID
        isSpeaking = true // optimistic: shows the stop control while audio is fetched
        fetchTask = Task { [weak self] in
            do {
                let data = try await Self.audioData(text: text, voiceID: voiceID, apiKey: apiKey)
                try Task.checkCancellation()
                await self?.startPlayback(data)
            } catch is CancellationError {
                // User pressed stop; state already reset there.
            } catch {
                // Any failure (offline, bad key, quota) → fall back to the on-device voice.
                await self?.fallBackToApple(text)
            }
        }
    }

    @MainActor
    private func startPlayback(_ data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.rate = SpeechRate.current.multiplier
            audioPlayer = player
            player.play()
            isSpeaking = true
        } catch {
            isSpeaking = false
        }
    }

    @MainActor
    private func fallBackToApple(_ text: String) {
        isSpeaking = false
        speakWithApple(text)
    }

    // MARK: - Premium audio cache (cachesDirectory)

    /// Returns cached MP3 for (model, voice, text) or fetches + caches it.
    private static func audioData(text: String, voiceID: String, apiKey: String) async throws -> Data {
        if let cached = try? Data(contentsOf: cacheURL(text: text, voiceID: voiceID)) {
            return cached
        }
        let data = try await ElevenLabsService.synthesize(text, voiceID: voiceID, apiKey: apiKey)
        try? data.write(to: cacheURL(text: text, voiceID: voiceID), options: .atomic)
        return data
    }

    private static func cacheURL(text: String, voiceID: String) -> URL {
        let key = "\(ElevenLabsService.modelID)|\(voiceID)|\(text)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ElevenLabsAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(hex + ".mp3")
    }

    static func availableJapaneseVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "ja-JP" }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    private static func selectedVoice() -> AVSpeechSynthesisVoice? {
        let identifier = UserDefaults.standard.string(forKey: "speechVoiceIdentifier") ?? ""
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return bestJapaneseVoice()
    }

    private static func bestJapaneseVoice() -> AVSpeechSynthesisVoice? {
        availableJapaneseVoices().first ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}

extension SpeechService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }
}

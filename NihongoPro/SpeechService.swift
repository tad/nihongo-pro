import AVFoundation
import CryptoKit
import Foundation
import Observation
import UIKit

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

/// Which engine synthesizes speech. Persisted as a raw string under `voiceEngine`.
enum VoiceEngine: String, CaseIterable, Identifiable {
    case apple
    case azure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "On-device"
        case .azure: return "Azure"
        }
    }
}

/// Text-to-speech for the sentence card, the word sheet and the Settings sample.
/// `@MainActor @Observable`: views read `isSpeaking` in their bodies, and every
/// mutation of it — including the ones triggered by AV delegate callbacks — lands
/// on the main actor. `AVAudioPlayerDelegate` is main-actor-isolated in the SDK, so
/// its callbacks arrive here directly; `AVSpeechSynthesizerDelegate` documents no
/// delivery thread, so those callbacks are `nonisolated` and hop with a `Task`.
@MainActor
@Observable
final class SpeechService: NSObject {
    private(set) var isSpeaking: Bool = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    /// The engine selected in Settings; defaults to the on-device Apple voice.
    static var voiceEngine: VoiceEngine {
        let raw = UserDefaults.standard.string(forKey: "voiceEngine") ?? ""
        return VoiceEngine(rawValue: raw) ?? .apple
    }

    /// Azure region (e.g. `westus2`), stored as a plain (non-secret) UserDefaults value.
    static var azureRegion: String {
        UserDefaults.standard.string(forKey: "azureRegion") ?? ""
    }

    /// Azure ja-JP voice ShortName chosen in Settings, or the Azure fallback voice when unset.
    static var selectedAzureVoice: String {
        let name = UserDefaults.standard.string(forKey: "azureVoiceName") ?? ""
        return name.isEmpty ? AzureSpeechService.defaultVoice : name
    }

    /// Azure speaking style (e.g. `cheerful`) for the selected voice, or "" for the voice's
    /// default delivery. Only some ja-JP voices support styles (see `AzureSpeechService.Voice.styleList`).
    static var selectedAzureStyle: String {
        UserDefaults.standard.string(forKey: "azureVoiceStyle") ?? ""
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()

        switch Self.voiceEngine {
        case .azure:
            let region = Self.azureRegion
            if let apiKey = KeychainStore.read(account: .azure), !apiKey.isEmpty, !region.isEmpty {
                speakWithAzure(trimmed, apiKey: apiKey, region: region)
            } else {
                speakWithApple(trimmed)
            }
        case .apple:
            speakWithApple(trimmed)
        }
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

    // MARK: - Audio session

    private static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// On iPhone, force `.playback` so the ring/silent switch can't mute study
    /// audio (an iPad has no such switch, and we leave its session untouched so
    /// iPad behavior is unchanged). No-op on iPad.
    private func activatePlaybackSessionForPhone() {
        guard Self.isPhone else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Apple (on-device) voice

    private func speakWithApple(_ text: String) {
        activatePlaybackSessionForPhone()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.selectedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * SpeechRate.current.multiplier
        synthesizer.speak(utterance)
    }

    // MARK: - Azure (premium) voice

    private func speakWithAzure(_ text: String, apiKey: String, region: String) {
        let voice = Self.selectedAzureVoice
        let style = Self.selectedAzureStyle
        isSpeaking = true // optimistic: shows the stop control while audio is fetched
        fetchTask = Task { [weak self] in
            do {
                let data = try await Self.azureAudioData(text: text, voice: voice, style: style, apiKey: apiKey, region: region)
                try Task.checkCancellation()
                self?.startPlayback(data)
            } catch is CancellationError {
                // User pressed stop; state already reset there.
            } catch {
                // Any failure (offline, bad key/region, quota) → fall back to the on-device voice.
                self?.fallBackToApple(text)
            }
        }
    }

    private func startPlayback(_ data: Data) {
        do {
            // iPhone: `.playback` so the ring/silent switch can't mute audio.
            // iPad: keep `.ambient` (unchanged).
            try AVAudioSession.sharedInstance().setCategory(Self.isPhone ? .playback : .ambient)
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

    private func fallBackToApple(_ text: String) {
        isSpeaking = false
        speakWithApple(text)
    }

    // MARK: - Premium audio cache (cachesDirectory)

    /// Returns cached Azure MP3 for (region, voice, style, text) or fetches + caches it.
    /// Nonisolated so the network round-trip and the cache read/write stay off the main actor.
    nonisolated private static func azureAudioData(text: String, voice: String, style: String, apiKey: String, region: String) async throws -> Data {
        let key = "azure|\(region)|\(voice)|\(style)|\(text)"
        return try await cachedAudio(key: key, subdir: "AzureAudio") {
            try await AzureSpeechService.synthesize(text, voiceName: voice, style: style, apiKey: apiKey, region: region)
        }
    }

    /// Generic disk cache: returns the MP3 at `key`/`subdir` or runs `fetch`, caching the result.
    nonisolated private static func cachedAudio(key: String, subdir: String, fetch: () async throws -> Data) async throws -> Data {
        let url = cacheURL(key: key, subdir: subdir)
        if let cached = try? Data(contentsOf: url) {
            return cached
        }
        let data = try await fetch()
        try? data.write(to: url, options: .atomic)
        return data
    }

    nonisolated private static func cacheURL(key: String, subdir: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(subdir, isDirectory: true)
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
    // The synthesizer's delegate has no documented delivery thread, so these are
    // nonisolated and hop onto the main actor (a `Task`, not `assumeIsolated`, so a
    // callback on another queue can never trap).
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

extension SpeechService: AVAudioPlayerDelegate {
    // `AVAudioPlayerDelegate` is main-actor-isolated in the SDK, so these run here.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isSpeaking = false
        audioPlayer = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isSpeaking = false
        audioPlayer = nil
    }
}

import AVFoundation
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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.selectedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * SpeechRate.current.multiplier
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
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

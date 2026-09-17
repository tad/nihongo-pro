import Foundation

/// Every `UserDefaults` key the app uses, in one place. Views bind with
/// `@AppStorage(SettingsKey.x.rawValue, …)` (so SwiftUI reactivity is untouched)
/// and the services read the same keys through `AppSettings`, so a key can't be
/// spelled two ways again.
nonisolated enum SettingsKey: String, CaseIterable {
    case aiProvider
    case showFurigana
    case autoReadAloud
    case speechRate
    case speechVoiceIdentifier
    case voiceEngine
    case azureRegion
    case azureVoiceName
    case azureVoiceStyle
    case videoStudySyncURL
    case syncDeviceID
}

/// Typed, live reads of the settings for the non-view code (`SpeechService`,
/// `TranslationService`, `VideoStudySync`, `SyncCoordinator`). Every accessor
/// reads `UserDefaults` on each call, so a change made in `SettingsView` takes
/// effect on the next use without re-instantiating anything. The fallbacks here
/// are the same defaults the views declare on their `@AppStorage` properties.
nonisolated enum AppSettings {
    static var aiProvider: AIProvider { AIProvider(rawValue: string(.aiProvider)) ?? .anthropic }
    static var voiceEngine: VoiceEngine { VoiceEngine(rawValue: string(.voiceEngine)) ?? .apple }
    static var speechRate: SpeechRate { SpeechRate(rawValue: string(.speechRate)) ?? .natural }
    /// An `AVSpeechSynthesisVoice.identifier`, or "" for "auto (best quality)".
    static var speechVoiceIdentifier: String { string(.speechVoiceIdentifier) }
    /// Azure region (e.g. `westus2`) — not a secret, so it lives here rather than the Keychain.
    static var azureRegion: String { string(.azureRegion) }
    /// Azure voice ShortName, or "" for the engine's default voice.
    static var azureVoiceName: String { string(.azureVoiceName) }
    /// Azure speaking style, or "" for the voice's default delivery.
    static var azureVoiceStyle: String { string(.azureVoiceStyle) }
    static var autoReadAloud: Bool { UserDefaults.standard.bool(forKey: SettingsKey.autoReadAloud.rawValue) }
    static var showFurigana: Bool { UserDefaults.standard.bool(forKey: SettingsKey.showFurigana.rawValue) }
    static var videoStudySyncURL: String { string(.videoStudySyncURL) }

    /// Stable per-install identifier; also the recordName of this device's CloudKit
    /// record. Created on first read and never changed.
    static let deviceID: String = {
        let key = SettingsKey.syncDeviceID.rawValue
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }()

    private static func string(_ key: SettingsKey) -> String {
        UserDefaults.standard.string(forKey: key.rawValue) ?? ""
    }
}

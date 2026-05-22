import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let speechService: SpeechService

    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @State private var hasExistingKey: Bool
    @AppStorage("speechRate") private var speechRateRaw: String = SpeechRate.natural.rawValue
    @AppStorage("speechVoiceIdentifier") private var speechVoiceIdentifier: String = ""

    init(speechService: SpeechService) {
        self.speechService = speechService
        _hasExistingKey = State(initialValue: KeychainStore.read() != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored securely in the iOS Keychain. Used only to call api.anthropic.com for translations.")
                }

                Section {
                    Picker("Voice", selection: $speechVoiceIdentifier) {
                        Text("Auto (best quality)").tag("")
                        ForEach(SpeechService.availableJapaneseVoices(), id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                    Picker("Rate", selection: $speechRateRaw) {
                        ForEach(SpeechRate.allCases) { rate in
                            Text(rate.label).tag(rate.rawValue)
                        }
                    }
                    Button("Play Sample") {
                        speechService.speak("こんにちは、日本語を話しています。")
                    }
                } header: {
                    Text("Speech")
                } footer: {
                    Text("Download more Japanese voices in iPadOS Settings → Accessibility → Spoken Content → Voices → Japanese. After installing, fully quit and reopen Nihongo Pro for new voices to appear here.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if hasExistingKey {
                    Section {
                        Button("Remove Saved Key", role: .destructive) {
                            try? KeychainStore.delete()
                            hasExistingKey = false
                            apiKey = ""
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if hasExistingKey {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Key") { save() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(!hasExistingKey)
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let qualityName: String
        switch voice.quality {
        case .premium: qualityName = "Premium"
        case .enhanced: qualityName = "Enhanced"
        default: qualityName = "Default"
        }
        return "\(voice.name) — \(qualityName)"
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.save(trimmed)
            dismiss()
        } catch {
            errorMessage = "Couldn't save to Keychain: \(error.localizedDescription)"
        }
    }
}

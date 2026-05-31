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

    // Premium voice (ElevenLabs)
    @AppStorage("usePremiumVoice") private var usePremiumVoice: Bool = false
    @AppStorage("elevenVoiceID") private var elevenVoiceID: String = ""
    @AppStorage("elevenVoiceName") private var elevenVoiceName: String = ""
    @State private var elevenKey: String = ""
    @State private var hasElevenKey: Bool
    @State private var japaneseVoices: [ElevenLabsService.SharedVoice] = []
    @State private var voicesLoading = false
    @State private var selectingVoiceID: String?
    @State private var elevenError: String?

    init(speechService: SpeechService) {
        self.speechService = speechService
        _hasExistingKey = State(initialValue: KeychainStore.read() != nil)
        _hasElevenKey = State(initialValue: KeychainStore.read(account: .elevenLabs) != nil)
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
                    Text("The on-device voice. Used offline and whenever the premium voice is off. Download more Japanese voices in iPadOS Settings → Accessibility → Spoken Content → Voices → Japanese, then fully quit and reopen Nihongo Pro for them to appear here.")
                }

                Section {
                    Toggle("Use premium voice", isOn: $usePremiumVoice)

                    SecureField("ElevenLabs API key", text: $elevenKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button(hasElevenKey ? "Update Key" : "Save Key") { saveElevenKey() }
                        .disabled(elevenKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    if hasElevenKey {
                        if !elevenVoiceName.isEmpty {
                            HStack {
                                Text("Selected voice")
                                Spacer()
                                Text(elevenVoiceName).foregroundStyle(.secondary)
                            }
                        }

                        if voicesLoading {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Loading Japanese voices…").foregroundStyle(.secondary)
                            }
                        } else if japaneseVoices.isEmpty {
                            Button("Load Japanese voices") { loadVoices() }
                        } else {
                            ForEach(japaneseVoices) { voice in
                                voiceRow(voice)
                            }
                        }

                        Button("Remove Premium Key", role: .destructive) {
                            try? KeychainStore.delete(account: .elevenLabs)
                            hasElevenKey = false
                            elevenKey = ""
                            japaneseVoices = []
                        }
                    }

                    if let elevenError {
                        Text(elevenError).foregroundStyle(.red).font(.caption)
                    }
                } header: {
                    Text("Premium Voice (ElevenLabs)")
                } footer: {
                    Text("A much more natural neural voice via ElevenLabs. These are native Japanese voices from ElevenLabs' Voice Library. Tap the speaker to hear a free sample; tap a voice to select it (this adds it to your ElevenLabs account). Requires your own API key and an internet connection, and synthesis costs a small amount per play. When premium is off, you're offline, or anything fails, the on-device voice above is used automatically.")
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
            .task(id: hasElevenKey) { loadVoices() }
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

    private func saveElevenKey() {
        let trimmed = elevenKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.save(trimmed, account: .elevenLabs)
            elevenError = nil
            hasElevenKey = true
            elevenKey = ""
            loadVoices()
        } catch {
            elevenError = "Couldn't save to Keychain: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func voiceRow(_ voice: ElevenLabsService.SharedVoice) -> some View {
        HStack(spacing: 12) {
            Button {
                if let preview = voice.previewURL { speechService.playPreview(preview) }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .disabled(voice.previewURL == nil)
            .accessibilityLabel("Play sample of \(voice.name)")

            Button {
                selectVoice(voice)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).foregroundStyle(.primary)
                        if !voice.subtitle.isEmpty {
                            Text(voice.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if selectingVoiceID == voice.voiceID {
                        ProgressView().controlSize(.small)
                    } else if elevenVoiceName == voice.name {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectingVoiceID != nil)
        }
    }

    private func loadVoices() {
        guard let key = KeychainStore.read(account: .elevenLabs), !key.isEmpty else { return }
        voicesLoading = true
        elevenError = nil
        Task {
            do {
                let voices = try await ElevenLabsService.fetchJapaneseVoices(apiKey: key)
                await MainActor.run {
                    japaneseVoices = voices
                    voicesLoading = false
                }
            } catch {
                await MainActor.run {
                    elevenError = "Couldn't load voices: \(error.localizedDescription)"
                    voicesLoading = false
                }
            }
        }
    }

    /// Adds the chosen library voice to the account (reusing it if already added) and stores
    /// the resulting owned voice ID for synthesis.
    private func selectVoice(_ voice: ElevenLabsService.SharedVoice) {
        guard let key = KeychainStore.read(account: .elevenLabs), !key.isEmpty else { return }
        selectingVoiceID = voice.voiceID
        elevenError = nil
        Task {
            do {
                let owned = (try? await ElevenLabsService.fetchVoices(apiKey: key)) ?? []
                let ownedID: String
                if let existing = owned.first(where: { $0.name == voice.name }) {
                    ownedID = existing.voiceID
                } else {
                    ownedID = try await ElevenLabsService.addSharedVoice(
                        publicOwnerID: voice.publicOwnerID,
                        voiceID: voice.voiceID,
                        name: voice.name,
                        apiKey: key
                    )
                }
                await MainActor.run {
                    elevenVoiceID = ownedID
                    elevenVoiceName = voice.name
                    selectingVoiceID = nil
                }
            } catch {
                await MainActor.run {
                    elevenError = "Couldn't select voice: \(error.localizedDescription)"
                    selectingVoiceID = nil
                }
            }
        }
    }
}

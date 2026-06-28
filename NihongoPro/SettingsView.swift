import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let speechService: SpeechService

    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @State private var hasExistingKey: Bool

    // Which AI service powers the translation/definition/kanji/breakdown calls.
    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.anthropic.rawValue
    @State private var openAIKey: String = ""
    @State private var hasOpenAIKey: Bool
    @AppStorage("speechRate") private var speechRateRaw: String = SpeechRate.natural.rawValue
    @AppStorage("speechVoiceIdentifier") private var speechVoiceIdentifier: String = ""

    // Which engine synthesizes speech.
    @AppStorage("voiceEngine") private var voiceEngineRaw: String = VoiceEngine.apple.rawValue

    // Premium voice (Azure)
    @AppStorage("azureRegion") private var azureRegion: String = ""
    @AppStorage("azureVoiceName") private var azureVoiceName: String = ""
    @AppStorage("azureVoiceStyle") private var azureVoiceStyle: String = ""
    @State private var azureKey: String = ""
    @State private var hasAzureKey: Bool
    @State private var azureVoices: [AzureSpeechService.Voice] = []
    @State private var azureVoicesLoading = false
    @State private var azureError: String?

    // Video-Study sync (push known words/kanji to the Chrome extension via the CF worker).
    @AppStorage("videoStudySyncURL") private var videoStudySyncURL: String = ""
    @State private var syncSecret: String = ""
    @State private var hasSyncSecret: Bool
    @State private var syncMessage: String?

    init(speechService: SpeechService) {
        self.speechService = speechService
        _hasExistingKey = State(initialValue: KeychainStore.read() != nil)
        _hasOpenAIKey = State(initialValue: KeychainStore.read(account: .openai) != nil)
        _hasAzureKey = State(initialValue: KeychainStore.read(account: .azure) != nil)
        _hasSyncSecret = State(initialValue: KeychainStore.read(account: .videoStudySync) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $aiProviderRaw) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text("Which AI service powers translations, definitions, kanji info, and breakdowns. Claude uses your Anthropic key; ChatGPT uses your OpenAI key. Set the matching key below.")
                }

                Section {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored securely in the iOS Keychain. Used only to call api.anthropic.com when the provider is Claude.")
                }

                Section {
                    SecureField("sk-...", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button(hasOpenAIKey ? "Update Key" : "Save Key") { saveOpenAIKey() }
                        .disabled(openAIKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasOpenAIKey {
                        Button("Remove OpenAI Key", role: .destructive) {
                            try? KeychainStore.delete(account: .openai)
                            hasOpenAIKey = false
                            openAIKey = ""
                        }
                    }
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text("Stored securely in the iOS Keychain. Used only to call api.openai.com when the provider is ChatGPT (gpt-4.1).")
                }

                Section {
                    TextField("https://video-study-sync.<you>.workers.dev", text: $videoStudySyncURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    SecureField("shared secret", text: $syncSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button(hasSyncSecret ? "Update" : "Save") { saveSyncConfig() }
                        .disabled(syncSecret.trimmingCharacters(in: .whitespaces).isEmpty && !hasSyncSecret)
                    Button("Sync now") { VideoStudySync.shared.uploadNow(); syncMessage = "Pushed." }
                        .disabled(!VideoStudySync.shared.isConfigured)
                    if hasSyncSecret {
                        Button("Remove sync secret", role: .destructive) {
                            try? KeychainStore.delete(account: .videoStudySync)
                            hasSyncSecret = false
                            syncSecret = ""
                        }
                    }
                    if let syncMessage {
                        Text(syncMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Video-Study Sync")
                } footer: {
                    Text("Pushes your known words & kanji to the Video-Study Chrome extension via your Cloudflare worker. Enter the worker URL and the same shared secret you set on the worker. One-way; runs automatically when you change a familiarity level.")
                }

                Section {
                    Picker("Engine", selection: $voiceEngineRaw) {
                        ForEach(VoiceEngine.allCases) { engine in
                            Text(engine.label).tag(engine.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Rate", selection: $speechRateRaw) {
                        ForEach(SpeechRate.allCases) { rate in
                            Text(rate.label).tag(rate.rawValue)
                        }
                    }
                    Button("Play Sample") {
                        speechService.speak("こんにちは、日本語を話しています。")
                    }
                } header: {
                    Text("Voice Engine")
                } footer: {
                    Text("Which engine speaks. On-device works offline and free; Azure is a more capable cloud voice that needs your own key below. Play Sample uses the selected engine (falling back to on-device if its key is missing). Rate applies to both.")
                }

                Section {
                    Picker("Voice", selection: $speechVoiceIdentifier) {
                        Text("Auto (best quality)").tag("")
                        ForEach(SpeechService.availableJapaneseVoices(), id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                } header: {
                    Text("On-device Voice")
                } footer: {
                    Text("The Apple voice. Used offline and whenever Azure is unavailable. Download more Japanese voices in iPadOS Settings → Accessibility → Spoken Content → Voices → Japanese, then fully quit and reopen Nihongo Pro for them to appear here.")
                }

                Section {
                    SecureField("Azure Speech key", text: $azureKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    TextField("Region (e.g. westus2)", text: $azureRegion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(hasAzureKey ? "Update Key" : "Save Key") { saveAzureKey() }
                        .disabled(azureKey.trimmingCharacters(in: .whitespaces).isEmpty
                                  || azureRegion.trimmingCharacters(in: .whitespaces).isEmpty)

                    if hasAzureKey {
                        if !azureVoiceName.isEmpty {
                            HStack {
                                Text("Selected voice")
                                Spacer()
                                Text(azureVoiceDisplayName).foregroundStyle(.secondary)
                            }
                        }

                        if !selectedVoiceStyles.isEmpty {
                            Picker("Style", selection: $azureVoiceStyle) {
                                Text("Default").tag("")
                                ForEach(selectedVoiceStyles, id: \.self) { style in
                                    Text(styleLabel(style)).tag(style)
                                }
                            }
                        }

                        if azureVoicesLoading {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Loading Japanese voices…").foregroundStyle(.secondary)
                            }
                        } else if azureVoices.isEmpty {
                            Button("Load Japanese voices") { loadAzureVoices() }
                        } else {
                            ForEach(azureVoices) { voice in
                                azureVoiceRow(voice)
                            }
                        }

                        Button("Remove Azure Key", role: .destructive) {
                            try? KeychainStore.delete(account: .azure)
                            hasAzureKey = false
                            azureKey = ""
                            azureVoices = []
                        }
                    }

                    if let azureError {
                        Text(azureError).foregroundStyle(.red).font(.caption)
                    }
                } header: {
                    Text("Premium Voice (Azure)")
                } footer: {
                    Text("Microsoft Azure neural voices. The voice is locked to Japanese and the engine uses a real Japanese dictionary, so readings, the small っ, and numbers are handled reliably. Some voices also offer speaking styles (cheerful, newscast…). The free tier covers 500,000 characters/month — far more than personal study uses. Needs your Azure key and region; used only when the engine above is set to Azure.")
                }

                Section {
                    HStack {
                        Text("iCloud account")
                        Spacer()
                        Text(SyncStatus.shared.accountAvailable ? "Available" : "Not available")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Last synced")
                        Spacer()
                        Text(lastSyncedText).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Other devices")
                        Spacer()
                        Text("\(SyncStatus.shared.remoteDeviceCount)").foregroundStyle(.secondary)
                    }
                    if let syncError = SyncStatus.shared.lastError {
                        Text(syncError).foregroundStyle(.red).font(.caption)
                    }
                    Button {
                        Task { await SyncCoordinator.shared.syncNow() }
                    } label: {
                        HStack {
                            Text("Sync now")
                            if SyncStatus.shared.isSyncing {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(SyncStatus.shared.isSyncing)
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    Text("Progress (exposure counts, activity, familiarity, saved sentences) syncs across your devices via iCloud. Sign into the same iCloud account on each device. This device: \(SyncCoordinator.shortDeviceID).")
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
            .task(id: hasAzureKey) { loadAzureVoices() }
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

    private var lastSyncedText: String {
        guard let date = SyncStatus.shared.lastSyncDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

    private func saveSyncConfig() {
        // The worker URL persists automatically via @AppStorage; just store the secret (if
        // entered) in the Keychain, then push immediately.
        let trimmed = syncSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            do {
                try KeychainStore.save(trimmed, account: .videoStudySync)
                hasSyncSecret = true
                syncSecret = ""
            } catch {
                syncMessage = "Couldn't save secret: \(error.localizedDescription)"
                return
            }
        }
        VideoStudySync.shared.uploadNow()
        syncMessage = "Saved and pushed."
    }

    private func saveOpenAIKey() {
        let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.save(trimmed, account: .openai)
            errorMessage = nil
            hasOpenAIKey = true
            openAIKey = ""
        } catch {
            errorMessage = "Couldn't save to Keychain: \(error.localizedDescription)"
        }
    }

    // MARK: - Azure

    /// The display name for the currently-selected Azure voice, looked up from the loaded list;
    /// falls back to the stored ShortName if the list hasn't loaded yet.
    private var azureVoiceDisplayName: String {
        azureVoices.first(where: { $0.shortName == azureVoiceName })?.displayName ?? azureVoiceName
    }

    /// Speaking styles supported by the currently-selected voice (empty if none / not loaded).
    private var selectedVoiceStyles: [String] {
        azureVoices.first(where: { $0.shortName == azureVoiceName })?.styleList ?? []
    }

    /// Turns an Azure style id (e.g. `newscast-casual`) into a display label (`Newscast casual`).
    private func styleLabel(_ style: String) -> String {
        style.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func saveAzureKey() {
        let trimmed = azureKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.save(trimmed, account: .azure)
            azureError = nil
            hasAzureKey = true
            azureKey = ""
            loadAzureVoices()
        } catch {
            azureError = "Couldn't save to Keychain: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func azureVoiceRow(_ voice: AzureSpeechService.Voice) -> some View {
        Button {
            azureVoiceName = voice.shortName
            // Drop a style the new voice doesn't offer so we never send an invalid express-as.
            if !(voice.styleList ?? []).contains(azureVoiceStyle) { azureVoiceStyle = "" }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.displayName).foregroundStyle(.primary)
                    if !voice.subtitle.isEmpty {
                        Text(voice.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    if let styles = voice.styleList, !styles.isEmpty {
                        Text("Styles: " + styles.map(styleLabel).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
                Spacer()
                if azureVoiceName == voice.shortName {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadAzureVoices() {
        guard let key = KeychainStore.read(account: .azure), !key.isEmpty else { return }
        let region = azureRegion.trimmingCharacters(in: .whitespaces)
        guard !region.isEmpty else { return }
        azureVoicesLoading = true
        azureError = nil
        Task {
            do {
                let voices = try await AzureSpeechService.fetchJapaneseVoices(apiKey: key, region: region)
                await MainActor.run {
                    azureVoices = voices
                    azureVoicesLoading = false
                }
            } catch {
                await MainActor.run {
                    azureError = "Couldn't load voices: \(error.localizedDescription)"
                    azureVoicesLoading = false
                }
            }
        }
    }
}

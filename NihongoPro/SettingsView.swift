import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @State private var hasExistingKey: Bool

    init() {
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
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(!hasExistingKey)
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

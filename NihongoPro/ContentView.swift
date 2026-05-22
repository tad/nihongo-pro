import SwiftUI

private struct WordSelection: Identifiable {
    let id = UUID()
    let word: Word
}

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var words: [Word] = []
    @State private var englishTranslation: String = ""
    @State private var isTranslating: Bool = false
    @State private var errorMessage: String?
    @State private var showingSettings: Bool = false
    @State private var selectedWord: WordSelection?
    @State private var isLoadingDefinitions: Bool = false
    @State private var definitionsError: String?
    @StateObject private var speechService = SpeechService()

    private let translator = TranslationService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ScrollView {
                    translationDisplay
                }
                .frame(maxHeight: .infinity)
                inputArea
            }
            .padding(32)
            .navigationTitle("Nihongo Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(speechService: speechService)
            }
            .sheet(item: $selectedWord) { selection in
                WordDefinitionView(word: selection.word, speechService: speechService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                if KeychainStore.read() == nil {
                    showingSettings = true
                }
            }
        }
    }

    private var translationDisplay: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isTranslating {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Waiting on Claude…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
            } else if words.isEmpty {
                Text("Paste a Japanese sentence below and tap Translate.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    FuriganaText(words: words) { word in
                        selectedWord = WordSelection(word: word)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        if speechService.isSpeaking {
                            speechService.stop()
                        } else {
                            speechService.speak(words.map(\.text).joined())
                        }
                    } label: {
                        Image(systemName: speechService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .font(.title)
                            .foregroundStyle(.tint)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speechService.isSpeaking ? "Stop audio" : "Play audio")
                }

                if !englishTranslation.isEmpty {
                    Divider()

                    Text(englishTranslation)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    definitionsStatus
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var definitionsStatus: some View {
        if isLoadingDefinitions {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading word definitions…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let definitionsError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("Couldn't load definitions: \(definitionsError)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Retry") {
                    Task { await fetchDefinitions() }
                }
                .font(.callout)
            }
        }
    }

    private var inputArea: some View {
        VStack(alignment: .trailing, spacing: 12) {
            TextEditor(text: $inputText)
                .font(.system(size: 22, design: .serif))
                .frame(minHeight: 120, maxHeight: 180)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("日本語をここに貼り付けてください…")
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }

            if let errorMessage {
                Button {
                    self.errorMessage = nil
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await translate() }
            } label: {
                HStack {
                    if isTranslating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isTranslating ? "Translating…" : "Translate")
                        .font(.headline)
                }
                .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
        }
    }

    private func translate() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isTranslating = true
        errorMessage = nil
        definitionsError = nil
        words = []
        englishTranslation = ""

        do {
            let result = try await translator.translate(trimmed)
            words = result.words
            englishTranslation = result.englishTranslation
            speechService.speak(trimmed)
        } catch let error as TranslationError {
            errorMessage = error.errorDescription
            isTranslating = false
            return
        } catch {
            errorMessage = error.localizedDescription
            isTranslating = false
            return
        }
        isTranslating = false

        await fetchDefinitions()
    }

    private func fetchDefinitions() async {
        let wordTexts = words.map(\.text)
        let sentence = wordTexts.joined()
        guard !wordTexts.isEmpty, !sentence.isEmpty else { return }

        definitionsError = nil
        isLoadingDefinitions = true

        do {
            let definitions = try await translator.fetchDefinitions(sentence: sentence, words: wordTexts)
            var updated = words
            for i in updated.indices where i < definitions.count {
                updated[i].definition = definitions[i]
            }
            words = updated
        } catch let error as TranslationError {
            definitionsError = error.errorDescription
        } catch {
            definitionsError = error.localizedDescription
        }
        isLoadingDefinitions = false
    }
}

#Preview {
    ContentView()
}

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
    @State private var showingStats: Bool = false
    @State private var selectedWord: WordSelection?
    @State private var isLoadingDefinitions: Bool = false
    @State private var definitionsError: String?
    @State private var breakdown: String?
    @State private var isLoadingBreakdown: Bool = false
    @State private var breakdownError: String?
    @State private var showingBreakdown: Bool = false
    @State private var isTranslationRevealed: Bool = false
    @State private var parsedInputText: String = ""
    @State private var autoParseTask: Task<Void, Never>?
    @State private var studySession: StudySession?
    @FocusState private var isInputFocused: Bool
    @StateObject private var speechService = SpeechService()

    private let translator = TranslationService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    ScrollView {
                        translationDisplay
                    }
                    .frame(maxHeight: .infinity)
                    inputArea
                }
                .padding(32)
            }
            .navigationTitle("Nihongo Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if SavedSessionStore.shared.hasSavedSession {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            resumeSavedSession()
                        } label: {
                            Label("Resume last study session", systemImage: "arrow.uturn.backward.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingStats = true
                    } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                    .accessibilityLabel("Progress")
                }
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
            .sheet(isPresented: $showingStats) {
                StatsView(translator: translator, speechService: speechService)
            }
            .sheet(item: $selectedWord) { selection in
                WordDefinitionView(word: selection.word, translator: translator, speechService: speechService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $studySession) { session in
                StudySessionView(session: session, translator: translator, speechService: speechService)
            }
            .onAppear {
                if KeychainStore.read() == nil {
                    showingSettings = true
                }
            }
            .onChange(of: inputText) { _, _ in
                handleInputChange()
            }
        }
    }

    private var translationDisplay: some View {
        Group {
            if words.isEmpty && isTranslating {
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
                emptyState
            } else {
                parsedSentenceCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.55))
            Text("Paste a Japanese sentence")
                .font(.title3)
                .foregroundStyle(.primary)
            Text("It'll appear here for you to read before the translation reveals.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }

    private var parsedSentenceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            definitionsStatus

            if isTranslationRevealed && !englishTranslation.isEmpty {
                Divider()

                if showingBreakdown {
                    breakdownContent
                } else {
                    Text(englishTranslation)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .cardChrome()
    }

    @ViewBuilder
    private var breakdownContent: some View {
        if isLoadingBreakdown {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Building breakdown…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let breakdownError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("Couldn't build breakdown: \(breakdownError)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Retry") {
                    Task { await fetchBreakdown() }
                }
                .font(.callout)
            }
        } else if let breakdown {
            VStack(alignment: .leading, spacing: 20) {
                Text(englishTranslation)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                BreakdownView(markdown: breakdown)
                    .textSelection(.enabled)
            }
        }
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
                .focused($isInputFocused)
                .frame(minHeight: 120, maxHeight: 180)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isInputFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                )
                .animation(.smooth(duration: 0.2), value: isInputFocused)
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

            if isMultiSentence(inputText) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Looks like more than one sentence — please paste just one. Long sentences are fine.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    clear()
                } label: {
                    Text("Clear")
                        .font(.headline)
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isTranslating || (inputText.isEmpty && words.isEmpty && englishTranslation.isEmpty && errorMessage == nil))

                Spacer()

                if !isTranslationRevealed && !words.isEmpty && !englishTranslation.isEmpty {
                    Button {
                        isTranslationRevealed = true
                    } label: {
                        Text("Show translation")
                            .font(.headline)
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if isTranslationRevealed && !showingBreakdown {
                    Button {
                        showBreakdown()
                    } label: {
                        Text("Breakdown")
                            .font(.headline)
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(englishTranslation.isEmpty || isTranslating || isLoadingBreakdown)
                }

                if !words.isEmpty {
                    Button {
                        startStudySession()
                    } label: {
                        Text("Start study")
                            .font(.headline)
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isTranslating || isLoadingDefinitions || englishTranslation.isEmpty)
                }
            }
        }
    }

    private func isMultiSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var count = 0
        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..<trimmed.endIndex,
            options: .bySentences
        ) { substring, _, _, stop in
            guard let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
                return
            }
            count += 1
            if count > 1 {
                stop = true
            }
        }
        return count > 1
    }

    private func startStudySession() {
        guard !words.isEmpty, !englishTranslation.isEmpty else { return }
        let sentence = parsedInputText.isEmpty ? inputText.trimmingCharacters(in: .whitespacesAndNewlines) : parsedInputText
        studySession = StudySession(
            sentence: sentence,
            words: words,
            referenceTranslation: englishTranslation
        )
    }

    private func resumeSavedSession() {
        guard let saved = SavedSessionStore.shared.load() else { return }
        SavedSessionStore.shared.clear()
        studySession = StudySession(restoring: saved)
    }

    private func clear() {
        autoParseTask?.cancel()
        autoParseTask = nil
        if speechService.isSpeaking {
            speechService.stop()
        }
        inputText = ""
        words = []
        englishTranslation = ""
        errorMessage = nil
        definitionsError = nil
        breakdown = nil
        breakdownError = nil
        showingBreakdown = false
        isTranslationRevealed = false
        parsedInputText = ""
        isLoadingDefinitions = false
        isLoadingBreakdown = false
    }

    private func handleInputChange() {
        autoParseTask?.cancel()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed != parsedInputText {
            words = []
            englishTranslation = ""
            breakdown = nil
            breakdownError = nil
            definitionsError = nil
            showingBreakdown = false
            isTranslationRevealed = false
            parsedInputText = ""
        }

        guard !trimmed.isEmpty,
              !isMultiSentence(inputText),
              KeychainStore.read() != nil,
              trimmed != parsedInputText else {
            return
        }

        autoParseTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await translate()
        }
    }

    private func translate() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isTranslating = true
        errorMessage = nil
        definitionsError = nil
        breakdown = nil
        breakdownError = nil
        showingBreakdown = false
        words = []
        englishTranslation = ""

        do {
            let result = try await translator.translate(trimmed)
            guard trimmed == inputText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                isTranslating = false
                return
            }
            words = result.words
            englishTranslation = result.englishTranslation
            parsedInputText = trimmed
            await FrequencyTracker.shared.recordSentence(words: result.words)
            speechService.speak(trimmed)
        } catch let error as TranslationError {
            guard trimmed == inputText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                isTranslating = false
                return
            }
            errorMessage = error.errorDescription
            isTranslating = false
            return
        } catch {
            guard trimmed == inputText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                isTranslating = false
                return
            }
            errorMessage = error.localizedDescription
            isTranslating = false
            return
        }
        isTranslating = false

        await fetchDefinitions()
    }

    private func showBreakdown() {
        if breakdown != nil {
            showingBreakdown = true
        } else {
            Task { await fetchBreakdown() }
        }
    }

    private func fetchBreakdown() async {
        let wordList = words
        let translation = englishTranslation
        let sentence = wordList.map(\.text).joined()
        guard !wordList.isEmpty, !translation.isEmpty else { return }

        breakdownError = nil
        isLoadingBreakdown = true
        showingBreakdown = true

        do {
            let result = try await translator.fetchBreakdown(
                sentence: sentence,
                words: wordList,
                translation: translation
            )
            breakdown = result
        } catch let error as TranslationError {
            breakdownError = error.errorDescription
        } catch {
            breakdownError = error.localizedDescription
        }
        isLoadingBreakdown = false
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

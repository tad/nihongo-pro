import SwiftUI

private struct WordSelection: Identifiable {
    let id = UUID()
    let word: Word
}

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var words: [Word] = []
    @State private var englishTranslation: String = ""
    @State private var literalTranslation: String = ""
    @State private var isTranslating: Bool = false
    @State private var errorMessage: String?
    @State private var showingSettings: Bool = false
    @State private var showingStats: Bool = false
    @State private var showingLibrary: Bool = false
    @State private var drillMode: Bool = false
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
    @State private var showingEndSessionConfirmation: Bool = false
    @AppStorage("showFurigana") private var showFurigana: Bool = false
    @AppStorage("autoReadAloud") private var autoReadAloud: Bool = false
    @FocusState private var isInputFocused: Bool
    @StateObject private var speechService = SpeechService()

    private let translator = TranslationService()

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    ScrollView {
                        translationDisplay
                    }
                    .frame(maxHeight: .infinity)
                    // iPhone: dragging the sentence area also dismisses the keyboard.
                    // iPad keeps the default (.automatic) so its behavior is unchanged.
                    .scrollDismissesKeyboard(isPhone ? .interactively : .automatic)
                    inputArea
                }
                .padding(isPhone ? 16 : 32)

                if let session = studySession, session.isOnBreak {
                    breakOverlay(session: session)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: studySession?.isOnBreak)
            .navigationTitle("Nihongo Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let session = studySession {
                    ToolbarItem(placement: .topBarTrailing) {
                        PomodoroPill(session: session)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingEndSessionConfirmation = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("End session")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        drillMode.toggle()
                    } label: {
                        Image(systemName: drillMode ? "graduationcap.fill" : "graduationcap")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(drillMode ? Color.accentColor : .secondary)
                    }
                    .accessibilityLabel(drillMode ? "Exit reading drill" : "Reading drill")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFurigana.toggle()
                    } label: {
                        Image(systemName: showFurigana ? "character.book.closed.fill" : "character.book.closed")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(showFurigana ? Color.accentColor : .secondary)
                    }
                    .accessibilityLabel(showFurigana ? "Hide furigana" : "Show furigana")
                    .disabled(drillMode)
                }
                if isPhone {
                    // On iPhone the top bar can't hold every button — collapse
                    // navigation into a single "More" menu (toggles stay visible).
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingLibrary = true
                            } label: {
                                Label("Saved sentences", systemImage: "books.vertical")
                            }
                            Button {
                                showingStats = true
                            } label: {
                                Label("Progress", systemImage: "chart.bar.fill")
                            }
                            Button {
                                showingSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingLibrary = true
                        } label: {
                            Image(systemName: "books.vertical")
                        }
                        .accessibilityLabel("Saved sentences")
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
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(speechService: speechService)
            }
            .sheet(isPresented: $showingStats) {
                StatsView(translator: translator, speechService: speechService)
            }
            .sheet(isPresented: $showingLibrary) {
                LibraryView { sentence in
                    load(sentence)
                }
            }
            .sheet(item: $selectedWord) { selection in
                WordDefinitionView(word: selection.word, translator: translator, speechService: speechService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("End session?", isPresented: $showingEndSessionConfirmation) {
                Button("Keep going", role: .cancel) { }
                Button("End session", role: .destructive) {
                    studySession?.end()
                    studySession = nil
                }
            } message: {
                Text("The pomodoro timer will stop.")
            }
            .onAppear {
                if KeychainStore.read() == nil {
                    showingSettings = true
                }
            }
            .onChange(of: inputText) { _, _ in
                handleInputChange()
            }
            .onChange(of: studySession?.isFinished) { _, finished in
                if finished == true {
                    studySession = nil
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
    }

    /// Handle a deep link like `nihongopro://lookup?text=...` (e.g. from MangaAssist):
    /// drop the sentence into the input field, which auto-translates via onChange.
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "nihongopro",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
              !text.isEmpty else { return }
        inputText = text
    }

    private func breakOverlay(session: StudySession) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Take a break")
                    .font(.title)
                    .bold()
                Text(session.pomodoroDisplay)
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text("Your study session ends when the break is over.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 20)
            .padding(40)
        }
    }

    private var translationDisplay: some View {
        Group {
            if words.isEmpty && isTranslating {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Waiting on \(TranslationService.provider.label)…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
                .transition(.opacity)
            } else if words.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                parsedSentenceCard
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: words.isEmpty)
        .animation(.smooth(duration: 0.25), value: isTranslating)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // Faint serif 読 watermark — echoes the app icon.
            Text("読")
                .font(.system(size: 96, design: .serif))
                .foregroundStyle(Color.accentColor.opacity(0.22))
            Text("Paste a Japanese sentence or speech bubble")
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
                FuriganaText(words: words, showFurigana: showFurigana, drillMode: drillMode) { word in
                    selectedWord = WordSelection(word: word)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    Button {
                        if speechService.isSpeaking {
                            speechService.stop()
                        } else {
                            speechService.speak(words.sentenceSpeechText())
                        }
                    } label: {
                        Image(systemName: speechService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .font(.title)
                            .foregroundStyle(.tint)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.pulse, isActive: speechService.isSpeaking)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speechService.isSpeaking ? "Stop audio" : "Play audio")

                    Button {
                        toggleSaved()
                    } label: {
                        Image(systemName: isCurrentSentenceSaved ? "bookmark.fill" : "bookmark")
                            .font(.title2)
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(isCurrentSentenceSaved ? Color.accentColor : .secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(englishTranslation.isEmpty)
                    .accessibilityLabel(isCurrentSentenceSaved ? "Remove from saved sentences" : "Save sentence")
                }
            }

            definitionsStatus

            if isTranslationRevealed && !englishTranslation.isEmpty {
                Group {
                    Divider()

                    if showingBreakdown {
                        breakdownContent
                    } else {
                        translationBlock
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.35), value: isTranslationRevealed)
        .animation(.smooth(duration: 0.3), value: showingBreakdown)
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
                translationBlock

                BreakdownView(markdown: breakdown)
                    .textSelection(.enabled)
            }
        }
    }

    /// The literal (grammar-following) translation captioned "Literal" above the natural
    /// translation captioned "Natural". The literal block is omitted when empty (e.g. the
    /// model didn't return one, or a sentence saved before this feature was reloaded).
    @ViewBuilder
    private var translationBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !literalTranslation.isEmpty {
                labeledTranslation("Literal", literalTranslation)
            }
            labeledTranslation("Natural", englishTranslation)
        }
    }

    @ViewBuilder
    private func labeledTranslation(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.title2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .toolbar {
                    // iPhone: a Done button above the keyboard so it can be
                    // dismissed once the user is finished typing/pasting (the
                    // keyboard otherwise eats too much of the small screen). The
                    // `.keyboard` placement only shows while editing. iPad is
                    // unaffected — no keyboard toolbar is added there.
                    if isPhone {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button {
                                isInputFocused = false
                            } label: {
                                Label("Done", systemImage: "keyboard.chevron.compact.down")
                            }
                        }
                    }
                }

            // A quiet running count once the input nears the limit, so hitting
            // the hard cap is never a surprise. The over-limit warning below
            // takes over past the cap.
            if !isOverLimit(inputText) && trimmedLength(inputText) >= Self.counterRevealThreshold {
                Text("\(trimmedLength(inputText)) / \(Self.maxInputLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: trimmedLength(inputText))
                    .padding(.trailing, 4)
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

            if isOverLimit(inputText) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("That's \(trimmedLength(inputText)) characters — the limit is \(Self.maxInputLength). Please trim it to about a speech bubble (a few sentences are fine).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isPhone {
                // On iPhone the action buttons don't fit on one row — stack them
                // full-width, primary action on top, Clear at the bottom.
                VStack(spacing: 12) {
                    if !isTranslationRevealed && !words.isEmpty && !englishTranslation.isEmpty {
                        showTranslationButton
                    }
                    if isTranslationRevealed && !showingBreakdown {
                        breakdownButton
                    }
                    if !words.isEmpty && studySession == nil {
                        startStudyButton
                    }
                    clearButton
                }
            } else {
                HStack(spacing: 12) {
                    clearButton

                    Spacer()

                    if !isTranslationRevealed && !words.isEmpty && !englishTranslation.isEmpty {
                        showTranslationButton
                    }

                    if isTranslationRevealed && !showingBreakdown {
                        breakdownButton
                    }

                    if !words.isEmpty && studySession == nil {
                        startStudyButton
                    }
                }
            }
        }
    }

    // Action-row buttons. Shared by the iPad HStack and the iPhone VStack so the
    // labels / conditions / disabled-state never drift; only the container and the
    // button width (fixed minWidth on iPad, full-width on iPhone) differ.
    private func actionButtonWidth(_ minWidth: CGFloat) -> some ViewModifier {
        ActionButtonWidth(isPhone: isPhone, minWidth: minWidth)
    }

    @ViewBuilder private var clearButton: some View {
        Button(role: .destructive) {
            clear()
        } label: {
            Text("Clear")
                .font(.headline)
                .modifier(actionButtonWidth(100))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isTranslating || (inputText.isEmpty && words.isEmpty && englishTranslation.isEmpty && errorMessage == nil))
    }

    @ViewBuilder private var showTranslationButton: some View {
        Button {
            isTranslationRevealed = true
        } label: {
            Text("Show translation")
                .font(.headline)
                .modifier(actionButtonWidth(180))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder private var breakdownButton: some View {
        Button {
            showBreakdown()
        } label: {
            Text("Breakdown")
                .font(.headline)
                .modifier(actionButtonWidth(130))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(englishTranslation.isEmpty || isTranslating || isLoadingBreakdown)
    }

    @ViewBuilder private var startStudyButton: some View {
        Button {
            startStudySession()
        } label: {
            Text("Start study")
                .font(.headline)
                .modifier(actionButtonWidth(130))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isTranslating || isLoadingDefinitions || englishTranslation.isEmpty)
    }

    /// Maximum input length in characters. Sized for a manga speech bubble or a
    /// few sentences (a typical bubble is 10–60 characters, so even a dense
    /// narration box fits), while refusing a pasted wall of text — the
    /// word-by-word parse grows linearly with input and gets slow, expensive,
    /// and unreadable past this.
    static let maxInputLength = 200

    /// The character count at which the quiet "N / 200" counter appears below
    /// the editor (75% of the cap).
    static let counterRevealThreshold = 150

    private func trimmedLength(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private func isOverLimit(_ text: String) -> Bool {
        trimmedLength(text) > Self.maxInputLength
    }

    private func startStudySession() {
        guard studySession == nil else { return }
        studySession = StudySession()
    }

    private var isCurrentSentenceSaved: Bool {
        !parsedInputText.isEmpty && SavedSentenceStore.shared.isSaved(parsedInputText)
    }

    private func toggleSaved() {
        guard !words.isEmpty, !parsedInputText.isEmpty else { return }
        SavedSentenceStore.shared.toggle(
            text: parsedInputText,
            words: words,
            englishTranslation: englishTranslation,
            literalTranslation: literalTranslation.isEmpty ? nil : literalTranslation
        )
    }

    /// Reloads a bookmarked sentence into the main display. Sets `parsedInputText`
    /// before `inputText` so the `onChange` auto-parse handler sees them equal and
    /// bails — the saved parse (furigana + definitions) is reused as-is, no network.
    private func load(_ sentence: SavedSentence) {
        autoParseTask?.cancel()
        autoParseTask = nil
        if speechService.isSpeaking {
            speechService.stop()
        }
        words = sentence.words
        englishTranslation = sentence.englishTranslation
        literalTranslation = sentence.literalTranslation ?? ""
        parsedInputText = sentence.text
        inputText = sentence.text
        isTranslationRevealed = false
        showingBreakdown = false
        breakdown = nil
        breakdownError = nil
        errorMessage = nil
        definitionsError = nil
        isLoadingDefinitions = false
        isLoadingBreakdown = false
        isTranslating = false
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
        literalTranslation = ""
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
            literalTranslation = ""
            breakdown = nil
            breakdownError = nil
            definitionsError = nil
            showingBreakdown = false
            isTranslationRevealed = false
            parsedInputText = ""
        }

        guard !trimmed.isEmpty,
              !isOverLimit(inputText),
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
        literalTranslation = ""

        do {
            let result = try await translator.translate(trimmed)
            guard trimmed == inputText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                isTranslating = false
                return
            }
            words = result.words
            englishTranslation = result.englishTranslation
            literalTranslation = result.literalTranslation
            parsedInputText = trimmed
            await FrequencyTracker.shared.recordSentence(words: result.words)
            ActivityTracker.shared.recordParse()
            // Mostly natural kanji (natural prosody), with only pass-1-flagged tricky-reading
            // words swapped to kana so rare compounds (精米歩合) are pronounced correctly.
            if autoReadAloud {
                speechService.speak(result.words.sentenceSpeechText())
            }
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
        let currentWords = words
        let sentence = currentWords.map(\.text).joined()
        guard !currentWords.isEmpty, !sentence.isEmpty else { return }

        definitionsError = nil
        isLoadingDefinitions = true

        do {
            let definitions = try await translator.fetchDefinitions(sentence: sentence, words: currentWords)
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

/// Sizes an action-button label: full-width on iPhone (stacked layout), fixed
/// `minWidth` on iPad (horizontal row).
private struct ActionButtonWidth: ViewModifier {
    let isPhone: Bool
    let minWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: isPhone ? .infinity : nil)
            .frame(minWidth: isPhone ? nil : minWidth)
    }
}

private struct PomodoroPill: View {
    @Bindable var session: StudySession

    var body: some View {
        let tint: Color = session.isOnBreak ? .orange : .accentColor
        HStack(spacing: 6) {
            Image(systemName: session.isOnBreak ? "moon.fill" : "timer")
                .font(.caption)
                .contentTransition(.symbolEffect(.replace))
            Text(session.pomodoroDisplay)
                .font(.callout)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(session.isOnBreak ? .orange : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.65), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .animation(.smooth(duration: 0.3), value: session.isOnBreak)
        .animation(.smooth(duration: 0.25), value: session.pomodoroDisplay)
    }
}

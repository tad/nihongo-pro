import SwiftUI

struct StudySessionView: View {
    @Bindable var session: StudySession
    let translator: TranslationService

    @State private var showingEndConfirmation: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    phaseContent
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                if session.isOnBreak {
                    breakOverlay
                        .transition(.opacity)
                }
            }
            .navigationTitle("Study Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingEndConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PomodoroPill(session: session)
                }
            }
            .interactiveDismissDisabled(true)
            .alert("End study session?", isPresented: $showingEndConfirmation) {
                Button("Continue studying", role: .cancel) { }
                Button("End session", role: .destructive) {
                    session.end()
                    dismiss()
                }
            } message: {
                Text("Your progress will be discarded.")
            }
            .onChange(of: session.phase) { _, newPhase in
                if newPhase == .completed {
                    session.end()
                }
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .vocabPreQuiz:
            VocabPreQuizCard(session: session, translator: translator)
        case .kanjiPreQuiz:
            KanjiPreQuizCard(session: session, translator: translator)
        case .kanjiStudy, .wordStudy, .translation:
            PendingPhasesCard()
        case .completed:
            SessionCompleteCard(session: session) {
                dismiss()
            }
        }
    }

    private var breakOverlay: some View {
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
                Text("The session resumes automatically when the timer ends.")
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
}

struct PomodoroPill: View {
    @Bindable var session: StudySession

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.isOnBreak ? "moon.fill" : "timer")
                .font(.caption)
            Text(session.pomodoroDisplay)
                .font(.callout)
                .monospacedDigit()
        }
        .foregroundStyle(session.isOnBreak ? .orange : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (session.isOnBreak ? Color.orange : Color.accentColor)
                .opacity(0.15)
        )
        .clipShape(Capsule())
    }
}

private struct PreQuizResult {
    let passed: Bool
    let feedback: String
}

struct VocabPreQuizCard: View {
    @Bindable var session: StudySession
    let translator: TranslationService

    @State private var definitionInput: String = ""
    @State private var pronunciationInput: String = ""
    @State private var isEvaluating: Bool = false
    @State private var result: PreQuizResult?

    private enum Field: Hashable { case definition, pronunciation }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            if let word = session.currentVocab {
                Text("Vocabulary quiz — \(session.vocabIndex + 1) of \(session.vocabPlan.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(word.text)
                    .font(.system(size: 72, weight: .regular, design: .serif))
                    .textSelection(.disabled)

                if let result {
                    resultView(word: word, result: result)
                } else {
                    inputView(word: word)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func inputView(word: Word) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Definition")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("English meaning…", text: $definitionInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)
                .focused($focusedField, equals: .definition)
                .onSubmit {
                    focusedField = .pronunciation
                }

            Text("Pronunciation (hiragana or rōmaji)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("e.g., kyou or きょう", text: $pronunciationInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .pronunciation)
                .onSubmit {
                    if canSubmit {
                        Task { await checkAnswer(word: word) }
                    }
                }
        }
        .frame(maxWidth: 480)
        .onAppear {
            focusedField = .definition
        }

        Button {
            Task { await checkAnswer(word: word) }
        } label: {
            HStack {
                if isEvaluating {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(isEvaluating ? "Checking…" : "Check")
                    .font(.headline)
            }
            .frame(minWidth: 160)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit || isEvaluating)
    }

    @ViewBuilder
    private func resultView(word: Word, result: PreQuizResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)
                    .font(.title)
                Text(result.passed ? "Correct!" : "Not quite")
                    .font(.title2)
                    .bold()
            }

            if let def = word.definition {
                Text("**Definition:** \(def)")
            }
            Text("**Pronunciation:** \(word.reading)")

            if !result.feedback.isEmpty {
                Text(result.feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                advance()
            } label: {
                Text("Next →")
                    .font(.headline)
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var canSubmit: Bool {
        !definitionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pronunciationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func checkAnswer(word: Word) async {
        isEvaluating = true
        defer { isEvaluating = false }

        let pronCorrect = pronunciationMatches(userInput: pronunciationInput, reference: word.reading)

        var defCorrect = false
        var feedback = ""
        if let referenceDef = word.definition {
            do {
                let evaluation = try await translator.evaluateDefinition(
                    item: word.text,
                    reference: referenceDef,
                    userAnswer: definitionInput
                )
                defCorrect = evaluation.correct
                feedback = evaluation.feedback
            } catch {
                defCorrect = definitionInput.lowercased().contains(referenceDef.lowercased())
                feedback = "(Evaluation unavailable; used literal match.)"
            }
        } else {
            defCorrect = !definitionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            feedback = "(No reference definition cached — your answer was accepted.)"
        }

        let combinedFeedback: String
        if pronCorrect && defCorrect {
            combinedFeedback = feedback
        } else if defCorrect && !pronCorrect {
            combinedFeedback = "Definition fits, but the pronunciation is \(word.reading)."
        } else if pronCorrect && !defCorrect {
            combinedFeedback = feedback
        } else {
            combinedFeedback = feedback.isEmpty ? "Both the definition and pronunciation need work." : feedback
        }

        result = PreQuizResult(passed: pronCorrect && defCorrect, feedback: combinedFeedback)
    }

    private func advance() {
        guard let result else { return }
        session.recordVocabResult(passed: result.passed)
        definitionInput = ""
        pronunciationInput = ""
        self.result = nil
    }
}

struct KanjiPreQuizCard: View {
    @Bindable var session: StudySession
    let translator: TranslationService

    @State private var definitionInput: String = ""
    @State private var isEvaluating: Bool = false
    @State private var result: PreQuizResult?
    @State private var referenceInfo: KanjiInfo?
    @State private var isLoadingReference: Bool = true
    @FocusState private var isDefinitionFocused: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            if let kanji = session.currentKanji {
                Text("Kanji quiz — \(session.kanjiIndex + 1) of \(session.kanjiPlan.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(kanji))
                    .font(.system(size: 96, weight: .regular, design: .serif))
                    .textSelection(.disabled)

                if isLoadingReference {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading reference…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let result {
                    resultView(kanji: kanji, result: result)
                } else {
                    inputView(kanji: kanji)
                }
            }
        }
        .padding(.horizontal, 32)
        .task(id: session.kanjiIndex) {
            await loadReference()
        }
    }

    @ViewBuilder
    private func inputView(kanji: Character) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meanings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("English meaning(s)…", text: $definitionInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($isDefinitionFocused)
                .onSubmit {
                    if canSubmit {
                        Task { await checkAnswer(kanji: kanji) }
                    }
                }
        }
        .frame(maxWidth: 480)
        .onAppear {
            isDefinitionFocused = true
        }

        Button {
            Task { await checkAnswer(kanji: kanji) }
        } label: {
            HStack {
                if isEvaluating {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(isEvaluating ? "Checking…" : "Check")
                    .font(.headline)
            }
            .frame(minWidth: 160)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit || isEvaluating)
    }

    @ViewBuilder
    private func resultView(kanji: Character, result: PreQuizResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)
                    .font(.title)
                Text(result.passed ? "Correct!" : "Not quite")
                    .font(.title2)
                    .bold()
            }

            if let info = referenceInfo {
                Text("**Meanings:** \(info.meanings.joined(separator: ", "))")
                if !info.onyomi.isEmpty {
                    Text("**On'yomi:** \(info.onyomi.joined(separator: " ・ "))")
                }
                if !info.kunyomi.isEmpty {
                    Text("**Kun'yomi:** \(info.kunyomi.joined(separator: " ・ "))")
                }
            }

            if !result.feedback.isEmpty {
                Text(result.feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                advance()
            } label: {
                Text("Next →")
                    .font(.headline)
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var canSubmit: Bool {
        !definitionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadReference() async {
        guard let kanji = session.currentKanji else { return }
        isLoadingReference = true
        do {
            referenceInfo = try await translator.fetchKanjiInfo(kanji: kanji)
        } catch {
            referenceInfo = nil
        }
        isLoadingReference = false
    }

    private func checkAnswer(kanji: Character) async {
        isEvaluating = true
        defer { isEvaluating = false }

        var defCorrect = false
        var feedback = ""
        if let info = referenceInfo {
            let reference = info.meanings.joined(separator: ", ")
            do {
                let evaluation = try await translator.evaluateDefinition(
                    item: String(kanji),
                    reference: reference,
                    userAnswer: definitionInput
                )
                defCorrect = evaluation.correct
                feedback = evaluation.feedback
            } catch {
                defCorrect = info.meanings.contains { definitionInput.lowercased().contains($0.lowercased()) }
                feedback = "(Evaluation unavailable; used literal match.)"
            }
        } else {
            defCorrect = !definitionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            feedback = "(Reference unavailable — your answer was accepted.)"
        }

        result = PreQuizResult(passed: defCorrect, feedback: feedback)
    }

    private func advance() {
        guard let result else { return }
        session.recordKanjiPreQuizResult(passed: result.passed)
        definitionInput = ""
        self.result = nil
        referenceInfo = nil
    }
}

struct PendingPhasesCard: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Pre-quiz finished. Skipping to summary…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .onAppear {
        }
    }
}

private func pronunciationMatches(userInput: String, reference: String) -> Bool {
    let user = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !user.isEmpty, !ref.isEmpty else { return false }
    if user == ref { return true }

    let mutable = NSMutableString(string: user)
    var range = CFRangeMake(0, mutable.length)
    if CFStringTransform(mutable, &range, "Latin-Hiragana" as CFString, false) {
        if (mutable as String) == ref { return true }
    }
    return false
}

struct SessionCompleteCard: View {
    @Bindable var session: StudySession
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("Session complete")
                .font(.title)
                .bold()

            VStack(spacing: 6) {
                Text("Pre-quiz finished")
                    .foregroundStyle(.secondary)
                Text("\(session.studyVocab.count) word\(session.studyVocab.count == 1 ? "" : "s") to study")
                Text("\(session.studyKanji.count) kanji to study")
            }
            .font(.callout)

            Text("Study and translation phases ship in the next update.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Button {
                onFinish()
            } label: {
                Text("Finish")
                    .font(.headline)
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 12)
        }
        .padding(40)
        .frame(maxWidth: 480)
    }
}

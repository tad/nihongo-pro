import Foundation
import SwiftUI
import AudioToolbox

@MainActor
@Observable
final class StudySession: Identifiable {
    enum Phase: String, Codable, Equatable {
        case vocabPreQuiz
        case kanjiPreQuiz
        case kanjiStudy
        case wordStudy
        case translation
        case completed
    }

    let id = UUID()
    let sentence: String
    let referenceTranslation: String
    let originalWords: [Word]

    let vocabPlan: [Word]
    let kanjiPlan: [Character]

    var vocabIndex: Int = 0
    var kanjiIndex: Int = 0
    var studyVocab: [Word] = []
    var studyKanji: [Character] = []
    var studyVocabIndex: Int = 0
    var studyKanjiIndex: Int = 0
    var phase: Phase = .vocabPreQuiz

    var pomodoroDisplay: String = "25:00"
    var isOnBreak: Bool = false

    private var pomodoroEndDate: Date = .distantFuture
    private var timerTask: Task<Void, Never>?
    private let workDuration: TimeInterval = 25 * 60    
    private let breakDuration: TimeInterval = 5 * 60
    private static let chimeSoundID: SystemSoundID = 1057

    init(sentence: String, words: [Word], referenceTranslation: String) {
        self.sentence = sentence
        self.referenceTranslation = referenceTranslation
        self.originalWords = words

        let familiarity = FamiliarityStore.shared

        var seenWords = Set<String>()
        let uniqueWords = words.filter { word in
            guard !JapaneseWordFilter.isPurePunctuation(word.text) else { return false }
            guard !JapaneseWordFilter.commonParticles.contains(word.text) else { return false }
            guard familiarity.wordLevel(for: word.text) != .known else { return false }
            return seenWords.insert(word.text).inserted
        }
        self.vocabPlan = uniqueWords.shuffled()

        var seenKanji = Set<Character>()
        var uniqueKanji: [Character] = []
        for word in uniqueWords {
            for ch in word.text where ch.isKanji {
                guard familiarity.kanjiLevel(for: ch) != .known else { continue }
                if seenKanji.insert(ch).inserted {
                    uniqueKanji.append(ch)
                }
            }
        }
        self.kanjiPlan = uniqueKanji.shuffled()

        if uniqueWords.isEmpty {
            self.phase = uniqueKanji.isEmpty ? .translation : .kanjiPreQuiz
        }

        startWorkInterval()
    }

    init(restoring saved: SavedSession) {
        self.sentence = saved.sentence
        self.referenceTranslation = saved.referenceTranslation
        self.originalWords = saved.originalWords
        self.vocabPlan = saved.vocabPlan
        self.kanjiPlan = saved.kanjiPlan.compactMap { $0.first }
        self.vocabIndex = saved.vocabIndex
        self.kanjiIndex = saved.kanjiIndex
        self.studyVocab = saved.studyVocab
        self.studyKanji = saved.studyKanji.compactMap { $0.first }
        self.studyVocabIndex = saved.studyVocabIndex
        self.studyKanjiIndex = saved.studyKanjiIndex
        self.phase = saved.phase

        startWorkInterval()
    }

    func saveProgress() {
        let snapshot = SavedSession(
            sentence: sentence,
            referenceTranslation: referenceTranslation,
            originalWords: originalWords,
            vocabPlan: vocabPlan,
            kanjiPlan: kanjiPlan.map { String($0) },
            vocabIndex: vocabIndex,
            kanjiIndex: kanjiIndex,
            studyVocab: studyVocab,
            studyKanji: studyKanji.map { String($0) },
            studyVocabIndex: studyVocabIndex,
            studyKanjiIndex: studyKanjiIndex,
            phase: phase,
            savedAt: Date()
        )
        SavedSessionStore.shared.save(snapshot)
    }

    var currentVocab: Word? {
        guard vocabIndex < vocabPlan.count else { return nil }
        return vocabPlan[vocabIndex]
    }

    var currentKanji: Character? {
        guard kanjiIndex < kanjiPlan.count else { return nil }
        return kanjiPlan[kanjiIndex]
    }

    var currentStudyKanji: Character? {
        guard studyKanjiIndex < studyKanji.count else { return nil }
        return studyKanji[studyKanjiIndex]
    }

    var currentStudyWord: Word? {
        guard studyVocabIndex < studyVocab.count else { return nil }
        return studyVocab[studyVocabIndex]
    }

    func skipToStudy() {
        studyVocab = vocabPlan.shuffled()
        studyKanji = kanjiPlan.shuffled()
        studyVocabIndex = 0
        studyKanjiIndex = 0
        vocabIndex = vocabPlan.count
        kanjiIndex = kanjiPlan.count

        if !studyKanji.isEmpty {
            phase = .kanjiStudy
        } else if !studyVocab.isEmpty {
            phase = .wordStudy
        } else {
            phase = .translation
        }
    }

    func skipCurrentVocab() {
        guard vocabIndex < vocabPlan.count else { return }
        vocabIndex += 1
        if vocabIndex >= vocabPlan.count {
            if !kanjiPlan.isEmpty {
                phase = .kanjiPreQuiz
            } else {
                transitionAfterPreQuizzes()
            }
        }
    }

    func skipCurrentKanjiPreQuiz() {
        guard kanjiIndex < kanjiPlan.count else { return }
        kanjiIndex += 1
        if kanjiIndex >= kanjiPlan.count {
            transitionAfterPreQuizzes()
        }
    }

    func recordVocabResult(passed: Bool) {
        guard vocabIndex < vocabPlan.count else { return }
        let word = vocabPlan[vocabIndex]
        if !passed {
            studyVocab.append(word)
        }
        vocabIndex += 1
        if vocabIndex >= vocabPlan.count {
            if !kanjiPlan.isEmpty {
                phase = .kanjiPreQuiz
            } else {
                transitionAfterPreQuizzes()
            }
        }
    }

    func recordKanjiPreQuizResult(passed: Bool) {
        guard kanjiIndex < kanjiPlan.count else { return }
        let kanji = kanjiPlan[kanjiIndex]
        if !passed {
            studyKanji.append(kanji)
        }
        kanjiIndex += 1
        if kanjiIndex >= kanjiPlan.count {
            transitionAfterPreQuizzes()
        }
    }

    func advanceKanjiStudy() {
        studyKanjiIndex += 1
        if studyKanjiIndex >= studyKanji.count {
            transitionAfterKanjiStudy()
        }
    }

    func advanceWordStudy() {
        studyVocabIndex += 1
        if studyVocabIndex >= studyVocab.count {
            phase = .translation
        }
    }

    private func transitionAfterPreQuizzes() {
        if !studyKanji.isEmpty {
            studyKanji.shuffle()
            studyKanjiIndex = 0
            phase = .kanjiStudy
        } else if !studyVocab.isEmpty {
            studyVocab.shuffle()
            studyVocabIndex = 0
            phase = .wordStudy
        } else {
            phase = .translation
        }
    }

    private func transitionAfterKanjiStudy() {
        if !studyVocab.isEmpty {
            studyVocab.shuffle()
            studyVocabIndex = 0
            phase = .wordStudy
        } else {
            phase = .translation
        }
    }

    func end() {
        timerTask?.cancel()
        timerTask = nil
        phase = .completed
    }

    private func startWorkInterval() {
        isOnBreak = false
        pomodoroEndDate = Date().addingTimeInterval(workDuration)
        pomodoroDisplay = Self.formatTime(workDuration)
        scheduleTick()
    }

    private func startBreakInterval() {
        isOnBreak = true
        pomodoroEndDate = Date().addingTimeInterval(breakDuration)
        pomodoroDisplay = Self.formatTime(breakDuration)
        AudioServicesPlaySystemSound(Self.chimeSoundID)
    }

    private func scheduleTick() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func tick() {
        let remaining = pomodoroEndDate.timeIntervalSinceNow
        if remaining <= 0 {
            if isOnBreak {
                startWorkInterval()
            } else {
                startBreakInterval()
            }
            return
        }
        pomodoroDisplay = Self.formatTime(remaining)
    }

    private static func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(ceil(interval)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

}

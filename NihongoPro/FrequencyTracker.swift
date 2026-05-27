import Foundation

enum JapaneseWordFilter {
    static let commonParticles: Set<String> = [
        "は", "が", "を", "に", "で", "と", "も", "か", "の", "へ", "や",
        "ね", "よ", "な", "わ", "ぞ", "ぜ", "さ", "し",
        "まで", "から", "など", "だけ", "ばかり", "しか",
        "でも", "けど", "けれど", "けれども",
        "には", "とは", "では", "のは", "のに", "ので",
        "って"
    ]

    static func isPurePunctuation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let allowed = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func shouldCount(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if isPurePunctuation(text) { return false }
        if commonParticles.contains(text) { return false }
        return true
    }
}

actor FrequencyTracker {
    static let shared = FrequencyTracker()

    private var wordCounts: [String: Int] = [:]
    private var kanjiCounts: [String: Int] = [:]
    private let wordCountsURL: URL
    private let kanjiCountsURL: URL

    private init() {
        let dir = Self.cacheDirectory()
        let wordURL = dir.appendingPathComponent("word_frequencies.json")
        let kanjiURL = dir.appendingPathComponent("kanji_frequencies.json")
        self.wordCountsURL = wordURL
        self.kanjiCountsURL = kanjiURL

        if let data = try? Data(contentsOf: wordURL),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.wordCounts = decoded
        }
        if let data = try? Data(contentsOf: kanjiURL),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.kanjiCounts = decoded
        }

        let stale = wordCounts.keys.filter { !JapaneseWordFilter.shouldCount($0) }
        if !stale.isEmpty {
            for key in stale { wordCounts.removeValue(forKey: key) }
            if let data = try? JSONEncoder().encode(wordCounts) {
                try? data.write(to: wordCountsURL, options: .atomic)
            }
        }
    }

    func recordSentence(words: [Word]) {
        for word in words {
            guard JapaneseWordFilter.shouldCount(word.text) else { continue }
            wordCounts[word.text, default: 0] += 1
            for char in word.text where char.isKanji {
                kanjiCounts[String(char), default: 0] += 1
            }
        }
        persistWordCounts()
        persistKanjiCounts()
    }

    func wordFrequency(for word: String) -> Int {
        wordCounts[word] ?? 0
    }

    func kanjiFrequency(for kanji: Character) -> Int {
        kanjiCounts[String(kanji)] ?? 0
    }

    func snapshot() -> (words: [String: Int], kanji: [String: Int]) {
        (wordCounts, kanjiCounts)
    }

    private func persistWordCounts() {
        guard let data = try? JSONEncoder().encode(wordCounts) else { return }
        try? data.write(to: wordCountsURL, options: .atomic)
    }

    private func persistKanjiCounts() {
        guard let data = try? JSONEncoder().encode(kanjiCounts) else { return }
        try? data.write(to: kanjiCountsURL, options: .atomic)
    }

    private static func cacheDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.temporaryDirectory
        let appDir = base.appendingPathComponent("NihongoPro", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }
}

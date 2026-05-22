import Foundation

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
    }

    func recordSentence(words: [Word]) {
        for word in words {
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

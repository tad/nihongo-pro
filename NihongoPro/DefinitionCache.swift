import Foundation

/// The app's Application Support data directory — the single home for every JSON
/// store and sync file. Created on first use; falls back to the temp directory if
/// Application Support is somehow unavailable. Shared by all stores so the path
/// logic lives in one place. (Declared here rather than its own file to avoid a
/// new pbxproj entry, like `JapaneseWordFilter` in `FrequencyTracker.swift`.)
enum AppDataDirectory {
    static func url() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NihongoPro", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

actor DefinitionCache {
    static let shared = DefinitionCache()

    private var kanjiCache: [String: KanjiInfo] = [:]
    private var wordCache: [String: String] = [:]
    private let kanjiCacheURL: URL
    private let wordCacheURL: URL

    private init() {
        let dir = AppDataDirectory.url()
        // v2: KanjiInfo gained the "jlpt" field. Legacy entries decode with jlpt == nil,
        // which is indistinguishable from a genuinely list-less kanji, so bumping the
        // filename forces a one-time re-fetch of every previously-cached kanji.
        let kanjiURL = dir.appendingPathComponent("kanji_cache_v2.json")
        // v2: word definitions are now fetched with the pass-1 reading attached, so
        // the model romanizes/disambiguates from the authoritative reading. Bumping
        // the filename forces a one-time re-fetch of every previously-cached word
        // (which were all fetched reading-blind, e.g. names like 安青錦 → "Yasuaonishiki").
        let wordURL = dir.appendingPathComponent("word_definitions_v2.json")
        self.kanjiCacheURL = kanjiURL
        self.wordCacheURL = wordURL

        // Delete superseded definition caches once (idempotent — no-ops once gone).
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("word_cache.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("word_definitions.json"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("kanji_cache.json"))

        if let data = try? Data(contentsOf: kanjiURL),
           let decoded = try? JSONDecoder().decode([String: KanjiInfo].self, from: data) {
            self.kanjiCache = decoded
        }
        if let data = try? Data(contentsOf: wordURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.wordCache = decoded
        }
    }

    func kanjiInfo(for kanji: Character) -> KanjiInfo? {
        kanjiCache[String(kanji)]
    }

    func setKanjiInfo(_ info: KanjiInfo, for kanji: Character) {
        kanjiCache[String(kanji)] = info
        persistKanjiCache()
    }

    func definition(for word: String) -> String? {
        wordCache[word]
    }

    func setDefinition(_ definition: String, for word: String) {
        wordCache[word] = definition
        persistWordCache()
    }

    private func persistKanjiCache() {
        guard let data = try? JSONEncoder().encode(kanjiCache) else { return }
        try? data.write(to: kanjiCacheURL, options: .atomic)
    }

    private func persistWordCache() {
        guard let data = try? JSONEncoder().encode(wordCache) else { return }
        try? data.write(to: wordCacheURL, options: .atomic)
    }
}

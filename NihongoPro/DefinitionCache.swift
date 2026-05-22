import Foundation

actor DefinitionCache {
    static let shared = DefinitionCache()

    private var kanjiCache: [String: KanjiInfo] = [:]
    private var wordCache: [String: String] = [:]
    private let kanjiCacheURL: URL
    private let wordCacheURL: URL

    private init() {
        let dir = Self.cacheDirectory()
        let kanjiURL = dir.appendingPathComponent("kanji_cache.json")
        let wordURL = dir.appendingPathComponent("word_definitions.json")
        self.kanjiCacheURL = kanjiURL
        self.wordCacheURL = wordURL

        let legacyWordCache = dir.appendingPathComponent("word_cache.json")
        try? FileManager.default.removeItem(at: legacyWordCache)

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

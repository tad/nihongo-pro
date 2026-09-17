import Foundation

/// The app's Application Support data directory — the single home for every JSON
/// store and sync file. Created on first use; falls back to the temp directory if
/// Application Support is somehow unavailable. Shared by all stores so the path
/// logic lives in one place. (Declared here rather than its own file to avoid a
/// new pbxproj entry, like `JapaneseWordFilter` in `FrequencyTracker.swift`.)
nonisolated enum AppDataDirectory {
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
        // v3: KanjiInfo gained "components"/"mnemonic"/"example" (the kanji-study
        // study aids) and dropped the "note" request. Legacy entries decode with those
        // fields nil, which is indistinguishable from a fetch that genuinely returned
        // none, so bumping the filename forces a one-time re-fetch of every
        // previously-cached kanji. (v2 had bumped for the "jlpt" field.)
        let kanjiURL = dir.appendingPathComponent("kanji_cache_v3.json")
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
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("kanji_cache_v2.json"))

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
        // The kanji-info cache is shared through CloudKit (with other devices AND
        // the kanji-study app), so a fresh fetch queues an upload. The coordinator is
        // main-actor-isolated; the cache write above is already complete.
        Task { @MainActor in SyncCoordinator.shared.markDirty() }
    }

    // MARK: Shared kanji-info cache (CloudKit)

    /// Everything this device knows, published in its sync record so other
    /// devices/apps never re-pay the model call for a kanji already fetched.
    func kanjiInfoSlice() -> [String: KanjiInfo] {
        kanjiCache
    }

    /// Newest-wins merge of another device's (or the kanji-study app's) kanji-info
    /// entries into the local cache. Ties and untimestamped-vs-untimestamped keep
    /// the local entry; a regenerated mnemonic (fresh `fetchedAt`) wins everywhere.
    /// Deliberately does NOT mark the sync record dirty — adopted entries are
    /// re-published on the next local fetch, and the source device's record already
    /// carries them.
    func applyRemoteKanjiInfo(_ entries: [String: KanjiInfo]) {
        var changed = false
        for (kanji, remote) in entries where Self.shouldAdopt(remote: remote, over: kanjiCache[kanji]) {
            kanjiCache[kanji] = remote
            changed = true
        }
        if changed { persistKanjiCache() }
    }

    /// Newest-wins, except that a pinned local entry only yields to a remote that is
    /// both newer AND itself pinned — a mnemonic the user wrote (in either app) is
    /// never replaced by a machine fetch from somewhere else. Two hand-edits race by
    /// timestamp as normal, so the later edit still wins.
    ///
    /// This is the same rule as the kanji-study app's `KanjiInfoService.shouldAdopt`,
    /// and both apps preserve `pinned` when they re-publish the shared slice, so a
    /// pin set in either app holds everywhere.
    nonisolated static func shouldAdopt(remote: KanjiInfo, over local: KanjiInfo?) -> Bool {
        guard let local else { return true }
        let remoteTime = remote.fetchedAt ?? .distantPast
        let localTime = local.fetchedAt ?? .distantPast
        guard remoteTime > localTime else { return false }
        if local.pinned == true && remote.pinned != true { return false }
        return true
    }

    /// Saves a mnemonic the user typed themselves. Stamped `fetchedAt` so it wins the
    /// newest-wins merge on every other device and in the kanji-study app, and pinned
    /// so no later fetch replaces it. Passing `components` also records the parts they
    /// selected; nil leaves the existing ones alone. Returns the stored entry (nil if
    /// the kanji has no cached info yet) so the caller can refresh its view state.
    @discardableResult
    func saveCustomMnemonic(_ mnemonic: String, components: [String]?,
                            for kanji: Character) -> KanjiInfo? {
        guard var info = kanjiCache[String(kanji)] else { return nil }
        info.mnemonic = mnemonic
        if let components { info.components = components }
        info.fetchedAt = Date()
        info.pinned = true
        // Goes through setKanjiInfo so the persist + markDirty happen in one place.
        setKanjiInfo(info, for: kanji)
        return info
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

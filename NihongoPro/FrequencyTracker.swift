import Foundation

nonisolated enum JapaneseWordFilter {
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
        return text.allSatisfy { $0.isPunctuation || $0.isWhitespace }
    }

    static func shouldCount(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if isPurePunctuation(text) { return false }
        if commonParticles.contains(text) { return false }
        return true
    }
}

/// Per-word and per-kanji exposure counts. Counts are **additive across devices**:
/// this device tracks only its OWN counts (`my…`), and the displayed totals are the
/// sum of this device's counts plus every other device's slice fetched via iCloud
/// (`remote`). Summing per-device slices means a count is never lost even if the
/// user studies on both devices offline (see [SyncCoordinator]).
///
/// `@MainActor @Observable` like the other progress stores (it used to be an actor):
/// the dictionaries are small, `recordSentence` runs once per parse, and reading it
/// from view bodies lets `StatsView` update live instead of once per open.
@MainActor
@Observable
final class FrequencyTracker: RemoteSliceStore {
    static let shared = FrequencyTracker()

    /// Merged (this device + all remote devices) totals. Read by `StatsView` /
    /// `ExportService`; recomputed whenever a slice changes.
    private(set) var wordCounts: [String: Int] = [:]
    private(set) var kanjiCounts: [String: Int] = [:]

    /// This device's own counts.
    private var myWord: [String: Int] = [:]
    private var myKanji: [String: Int] = [:]
    /// Other devices' slices, keyed by deviceID (cached locally so totals are correct offline).
    var remote: [String: DeviceFreqSlice] = [:]

    private let sliceURL: URL
    let remoteURL: URL

    private init() {
        let dir = AppDataDirectory.url()
        self.sliceURL = dir.appendingPathComponent("freq_slice.json")
        self.remoteURL = dir.appendingPathComponent("freq_remote.json")

        // Load this device's slice, migrating from the pre-sync files on first run.
        if let decoded = JSONStore.load(DeviceFreqSlice.self, from: sliceURL) {
            myWord = decoded.word
            myKanji = decoded.kanji
        } else {
            myWord = JSONStore.load([String: Int].self, from: dir.appendingPathComponent("word_frequencies.json")) ?? [:]
            myKanji = JSONStore.load([String: Int].self, from: dir.appendingPathComponent("kanji_frequencies.json")) ?? [:]
        }
        remote = JSONStore.load([String: DeviceFreqSlice].self, from: remoteURL) ?? [:]

        // Scrub punctuation/particles that older versions may have stored.
        let stale = myWord.keys.filter { !JapaneseWordFilter.shouldCount($0) }
        if !stale.isEmpty {
            for key in stale { myWord.removeValue(forKey: key) }
            JSONStore.save(localSlice(), to: sliceURL)
        }

        recompute()
    }

    func recordSentence(words: [Word]) {
        for word in words {
            guard JapaneseWordFilter.shouldCount(word.text) else { continue }
            myWord[word.text, default: 0] += 1
            for char in word.text where char.isKanji {
                myKanji[String(char), default: 0] += 1
            }
        }
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
    }

    func wordFrequency(for word: String) -> Int {
        wordCounts[word] ?? 0
    }

    func kanjiFrequency(for kanji: Character) -> Int {
        kanjiCounts[String(kanji)] ?? 0
    }

    /// Merged totals across all devices.
    func snapshot() -> (words: [String: Int], kanji: [String: Int]) {
        (wordCounts, kanjiCounts)
    }

    // MARK: Sync

    func localSlice() -> DeviceFreqSlice {
        DeviceFreqSlice(word: myWord, kanji: myKanji)
    }

    func recompute() {
        var words = myWord
        var kanji = myKanji
        for slice in remote.values {
            for (k, v) in slice.word { words[k, default: 0] += v }
            for (k, v) in slice.kanji { kanji[k, default: 0] += v }
        }
        wordCounts = words
        kanjiCounts = kanji
    }

    private func persistSlice() {
        JSONStore.saveLater(localSlice(), to: sliceURL)
    }
}

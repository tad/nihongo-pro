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

/// Per-word and per-kanji exposure counts. Counts are **additive across devices**:
/// this device tracks only its OWN counts (`my…`), and the displayed totals are the
/// sum of this device's counts plus every other device's slice fetched via iCloud
/// (`remote`). Summing per-device slices means a count is never lost even if the
/// user studies on both devices offline (see [SyncCoordinator]).
actor FrequencyTracker {
    static let shared = FrequencyTracker()

    /// This device's own counts.
    private var myWord: [String: Int] = [:]
    private var myKanji: [String: Int] = [:]
    /// Other devices' slices, keyed by deviceID (cached locally so totals are correct offline).
    private var remote: [String: DeviceFreqSlice] = [:]

    private let sliceURL: URL
    private let remoteURL: URL

    private init() {
        let dir = AppDataDirectory.url()
        self.sliceURL = dir.appendingPathComponent("freq_slice.json")
        self.remoteURL = dir.appendingPathComponent("freq_remote.json")

        // Load this device's slice, migrating from the pre-sync files on first run.
        if let data = try? Data(contentsOf: sliceURL),
           let decoded = try? JSONDecoder().decode(DeviceFreqSlice.self, from: data) {
            myWord = decoded.word
            myKanji = decoded.kanji
        } else {
            let legacyWord = dir.appendingPathComponent("word_frequencies.json")
            let legacyKanji = dir.appendingPathComponent("kanji_frequencies.json")
            if let data = try? Data(contentsOf: legacyWord),
               let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
                myWord = decoded
            }
            if let data = try? Data(contentsOf: legacyKanji),
               let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
                myKanji = decoded
            }
        }

        if let data = try? Data(contentsOf: remoteURL),
           let decoded = try? JSONDecoder().decode([String: DeviceFreqSlice].self, from: data) {
            remote = decoded
        }

        // Scrub punctuation/particles that older versions may have stored.
        let stale = myWord.keys.filter { !JapaneseWordFilter.shouldCount($0) }
        if !stale.isEmpty {
            for key in stale { myWord.removeValue(forKey: key) }
            if let data = try? JSONEncoder().encode(DeviceFreqSlice(word: myWord, kanji: myKanji)) {
                try? data.write(to: sliceURL, options: .atomic)
            }
        }
    }

    func recordSentence(words: [Word]) {
        for word in words {
            guard JapaneseWordFilter.shouldCount(word.text) else { continue }
            myWord[word.text, default: 0] += 1
            for char in word.text where char.isKanji {
                myKanji[String(char), default: 0] += 1
            }
        }
        persistSlice()
        SyncCoordinator.shared.markDirty()
    }

    func wordFrequency(for word: String) -> Int {
        var total = myWord[word] ?? 0
        for slice in remote.values { total += slice.word[word] ?? 0 }
        return total
    }

    func kanjiFrequency(for kanji: Character) -> Int {
        let key = String(kanji)
        var total = myKanji[key] ?? 0
        for slice in remote.values { total += slice.kanji[key] ?? 0 }
        return total
    }

    /// Merged totals across all devices.
    func snapshot() -> (words: [String: Int], kanji: [String: Int]) {
        var words = myWord
        var kanji = myKanji
        for slice in remote.values {
            for (k, v) in slice.word { words[k, default: 0] += v }
            for (k, v) in slice.kanji { kanji[k, default: 0] += v }
        }
        return (words, kanji)
    }

    // MARK: Sync

    func localSlice() -> DeviceFreqSlice {
        DeviceFreqSlice(word: myWord, kanji: myKanji)
    }

    func applyRemoteSlice(deviceID: String, slice: DeviceFreqSlice) {
        remote[deviceID] = slice
        persistRemote()
    }

    func removeRemoteSlice(deviceID: String) {
        remote.removeValue(forKey: deviceID)
        persistRemote()
    }

    func clearRemoteSlices() {
        remote.removeAll()
        persistRemote()
    }

    /// Device IDs whose slices this device has merged in (for the sync status UI).
    func knownRemoteDeviceIDs() -> [String] {
        Array(remote.keys)
    }

    private func persistSlice() {
        guard let data = try? JSONEncoder().encode(DeviceFreqSlice(word: myWord, kanji: myKanji)) else { return }
        try? data.write(to: sliceURL, options: .atomic)
    }

    private func persistRemote() {
        guard let data = try? JSONEncoder().encode(remote) else { return }
        try? data.write(to: remoteURL, options: .atomic)
    }
}

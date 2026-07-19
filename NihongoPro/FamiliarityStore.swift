import Foundation
import SwiftUI

/// `@MainActor @Observable` per-word and per-kanji familiarity ratings. Ratings
/// sync across devices with **per-key newest-wins** semantics: this device records
/// each rating it sets with a timestamp (`my…`), and the exposed `wordLevels` /
/// `kanjiLevels` merge this device's ratings with every other device's slice
/// (`remote`), taking the most recently set value per key. Setting `.unknown` is
/// kept as a TOMBSTONE (timestamped) rather than dropped, so a clear on one device
/// can out-rank an older rating on another (see [SyncCoordinator]).
@MainActor
@Observable
final class FamiliarityStore {
    static let shared = FamiliarityStore()

    enum Level: String, Codable, CaseIterable, Identifiable {
        case unknown
        case familiar
        case known

        var id: String { rawValue }

        var label: String {
            switch self {
            case .unknown: return "Unknown"
            case .familiar: return "Familiar"
            case .known: return "Known"
            }
        }
    }

    /// Merged (this device + all remote devices) ratings, tombstones excluded.
    /// Read by `StatsView` / `FuriganaText` / `ExportService`.
    private(set) var wordLevels: [String: Level] = [:]
    private(set) var kanjiLevels: [String: Level] = [:]

    /// This device's own ratings, including `.unknown` tombstones, with timestamps.
    private var myWord: [String: FamiliaritySliceEntry] = [:]
    private var myKanji: [String: FamiliaritySliceEntry] = [:]
    /// Other devices' slices, keyed by deviceID.
    private var remote: [String: DeviceFamiliaritySlice] = [:]

    private let sliceURL: URL
    private let remoteURL: URL

    private init() {
        let dir = AppDataDirectory.url()
        self.sliceURL = dir.appendingPathComponent("familiarity_slice.json")
        self.remoteURL = dir.appendingPathComponent("familiarity_remote.json")

        if let data = try? Data(contentsOf: sliceURL),
           let decoded = try? JSONDecoder().decode(DeviceFamiliaritySlice.self, from: data) {
            myWord = decoded.word
            myKanji = decoded.kanji
        } else {
            // Migrate the pre-sync files (plain [key: Level]) on first run.
            let now = Date()
            let legacyWord = dir.appendingPathComponent("word_familiarity.json")
            let legacyKanji = dir.appendingPathComponent("kanji_familiarity.json")
            if let data = try? Data(contentsOf: legacyWord),
               let decoded = try? JSONDecoder().decode([String: Level].self, from: data) {
                for (k, level) in decoded {
                    myWord[k] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: now)
                }
            }
            if let data = try? Data(contentsOf: legacyKanji),
               let decoded = try? JSONDecoder().decode([String: Level].self, from: data) {
                for (k, level) in decoded {
                    myKanji[k] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: now)
                }
            }
        }

        if let data = try? Data(contentsOf: remoteURL),
           let decoded = try? JSONDecoder().decode([String: DeviceFamiliaritySlice].self, from: data) {
            remote = decoded
        }

        recompute()
    }

    func wordLevel(for word: String) -> Level {
        wordLevels[word] ?? .unknown
    }

    func kanjiLevel(for kanji: Character) -> Level {
        kanjiLevels[String(kanji)] ?? .unknown
    }

    func setWordLevel(_ level: Level, for word: String) {
        myWord[word] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: Date())
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
        VideoStudySync.shared.scheduleSync()
    }

    func setKanjiLevel(_ level: Level, for kanji: Character) {
        myKanji[String(kanji)] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: Date())
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
        VideoStudySync.shared.scheduleSync()
    }

    // MARK: Sync

    func localSlice() -> DeviceFamiliaritySlice {
        DeviceFamiliaritySlice(word: myWord, kanji: myKanji)
    }

    func applyRemoteSlice(deviceID: String, slice: DeviceFamiliaritySlice) {
        remote[deviceID] = slice
        recompute()
        persistRemote()
    }

    func removeRemoteSlice(deviceID: String) {
        remote.removeValue(forKey: deviceID)
        recompute()
        persistRemote()
    }

    func clearRemoteSlices() {
        remote.removeAll()
        recompute()
        persistRemote()
    }

    // MARK: Video-Study two-way sync

    /// Merge timestamped entries from the Video-Study extension into THIS device's slice
    /// (newest-wins per key, tombstones included). They become first-class ratings, so they
    /// persist locally and also ride CloudKit to the user's other devices.
    func applyVideoStudyEntries(word: [String: FamiliaritySliceEntry],
                                kanji: [String: FamiliaritySliceEntry]) {
        let wordChanged = Self.mergeNewer(word, into: &myWord)
        let kanjiChanged = Self.mergeNewer(kanji, into: &myKanji)
        if wordChanged || kanjiChanged {
            recompute()
            persistSlice()
            SyncCoordinator.shared.markDirty()
        }
    }

    /// Merged familiarity (this device + CloudKit remotes), entries **including** `.unknown`
    /// tombstones, for pushing to the Video-Study relay.
    func mergedFamiliarityForSync() -> (word: [String: FamiliaritySliceEntry],
                                        kanji: [String: FamiliaritySliceEntry]) {
        (Self.mergeEntries(my: myWord, remote: remote.values.map(\.word)),
         Self.mergeEntries(my: myKanji, remote: remote.values.map(\.kanji)))
    }

    private static func mergeEntries(my: [String: FamiliaritySliceEntry],
                                     remote: [[String: FamiliaritySliceEntry]]) -> [String: FamiliaritySliceEntry] {
        var winners = my
        for slice in remote {
            _ = mergeNewer(slice, into: &winners)
        }
        return winners
    }

    /// Merges `incoming` into `target`, keeping the newer `modifiedAt` per key.
    /// Returns whether anything in `target` changed.
    @discardableResult
    private static func mergeNewer(_ incoming: [String: FamiliaritySliceEntry],
                                   into target: inout [String: FamiliaritySliceEntry]) -> Bool {
        var changed = false
        for (key, entry) in incoming {
            if let current = target[key], entry.modifiedAt <= current.modifiedAt { continue }
            target[key] = entry
            changed = true
        }
        return changed
    }

    private func recompute() {
        wordLevels = Self.merge(my: myWord, remote: remote.values.map(\.word))
        kanjiLevels = Self.merge(my: myKanji, remote: remote.values.map(\.kanji))
    }

    /// Picks the newest `modifiedAt` per key across all slices; drops tombstones.
    private static func merge(my: [String: FamiliaritySliceEntry], remote: [[String: FamiliaritySliceEntry]]) -> [String: Level] {
        var result: [String: Level] = [:]
        for (key, entry) in mergeEntries(my: my, remote: remote) {
            if let level = Level(rawValue: entry.level), level != .unknown {
                result[key] = level
            }
        }
        return result
    }

    private func persistSlice() {
        let slice = DeviceFamiliaritySlice(word: myWord, kanji: myKanji)
        let url = sliceURL
        Task.detached {
            guard let data = try? JSONEncoder().encode(slice) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistRemote() {
        let snapshot = remote
        let url = remoteURL
        Task.detached {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

struct WordFamiliarityPicker: View {
    let word: String
    var onKnown: (() -> Void)? = nil

    var body: some View {
        Picker("Familiarity", selection: Binding(
            get: { FamiliarityStore.shared.wordLevel(for: word) },
            set: { newLevel in
                FamiliarityStore.shared.setWordLevel(newLevel, for: word)
                if newLevel == .known, let onKnown {
                    Task { @MainActor in onKnown() }
                }
            }
        )) {
            ForEach(FamiliarityStore.Level.allCases) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct KanjiFamiliarityPicker: View {
    let kanji: Character
    var onKnown: (() -> Void)? = nil

    var body: some View {
        Picker("Familiarity", selection: Binding(
            get: { FamiliarityStore.shared.kanjiLevel(for: kanji) },
            set: { newLevel in
                FamiliarityStore.shared.setKanjiLevel(newLevel, for: kanji)
                if newLevel == .known, let onKnown {
                    Task { @MainActor in onKnown() }
                }
            }
        )) {
            ForEach(FamiliarityStore.Level.allCases) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

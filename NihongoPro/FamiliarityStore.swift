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
final class FamiliarityStore: RemoteSliceStore {
    static let shared = FamiliarityStore()

    nonisolated enum Level: String, Codable, CaseIterable, Identifiable {
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
    var remote: [String: DeviceFamiliaritySlice] = [:]

    private let sliceURL: URL
    let remoteURL: URL

    private init() {
        let dir = AppDataDirectory.url()
        self.sliceURL = dir.appendingPathComponent("familiarity_slice.json")
        self.remoteURL = dir.appendingPathComponent("familiarity_remote.json")

        if let decoded = JSONStore.load(DeviceFamiliaritySlice.self, from: sliceURL) {
            myWord = decoded.word
            myKanji = decoded.kanji
        } else {
            // Migrate the pre-sync files (plain [key: Level]) on first run.
            let now = Date()
            for (k, level) in JSONStore.load([String: Level].self, from: dir.appendingPathComponent("word_familiarity.json")) ?? [:] {
                myWord[k] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: now)
            }
            for (k, level) in JSONStore.load([String: Level].self, from: dir.appendingPathComponent("kanji_familiarity.json")) ?? [:] {
                myKanji[k] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: now)
            }
        }
        remote = JSONStore.load([String: DeviceFamiliaritySlice].self, from: remoteURL) ?? [:]

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

    nonisolated static func mergeEntries(my: [String: FamiliaritySliceEntry],
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
    nonisolated static func mergeNewer(_ incoming: [String: FamiliaritySliceEntry],
                                       into target: inout [String: FamiliaritySliceEntry]) -> Bool {
        var changed = false
        for (key, entry) in incoming {
            if let current = target[key], entry.modifiedAt <= current.modifiedAt { continue }
            target[key] = entry
            changed = true
        }
        return changed
    }

    func recompute() {
        wordLevels = Self.merge(my: myWord, remote: remote.values.map(\.word))
        kanjiLevels = Self.merge(my: myKanji, remote: remote.values.map(\.kanji))
    }

    /// Picks the newest `modifiedAt` per key across all slices; drops tombstones.
    nonisolated static func merge(my: [String: FamiliaritySliceEntry], remote: [[String: FamiliaritySliceEntry]]) -> [String: Level] {
        var result: [String: Level] = [:]
        for (key, entry) in mergeEntries(my: my, remote: remote) {
            if let level = Level(rawValue: entry.level), level != .unknown {
                result[key] = level
            }
        }
        return result
    }

    private func persistSlice() {
        JSONStore.saveLater(localSlice(), to: sliceURL)
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

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
        let dir = Self.storeDirectory()
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
    }

    func setKanjiLevel(_ level: Level, for kanji: Character) {
        myKanji[String(kanji)] = FamiliaritySliceEntry(level: level.rawValue, modifiedAt: Date())
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
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

    private func recompute() {
        wordLevels = Self.merge(my: myWord, remote: remote.values.map(\.word))
        kanjiLevels = Self.merge(my: myKanji, remote: remote.values.map(\.kanji))
    }

    /// Picks the newest `modifiedAt` per key across all slices; drops tombstones.
    private static func merge(my: [String: FamiliaritySliceEntry], remote: [[String: FamiliaritySliceEntry]]) -> [String: Level] {
        var winners = my
        for slice in remote {
            for (key, entry) in slice {
                if let current = winners[key] {
                    if entry.modifiedAt > current.modifiedAt { winners[key] = entry }
                } else {
                    winners[key] = entry
                }
            }
        }
        var result: [String: Level] = [:]
        for (key, entry) in winners {
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

    private static func storeDirectory() -> URL {
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

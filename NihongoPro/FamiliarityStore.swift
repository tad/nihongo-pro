import Foundation
import SwiftUI

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

    private(set) var wordLevels: [String: Level] = [:]
    private(set) var kanjiLevels: [String: Level] = [:]

    private let wordLevelsURL: URL
    private let kanjiLevelsURL: URL

    private init() {
        let dir = Self.storeDirectory()
        let wordURL = dir.appendingPathComponent("word_familiarity.json")
        let kanjiURL = dir.appendingPathComponent("kanji_familiarity.json")
        self.wordLevelsURL = wordURL
        self.kanjiLevelsURL = kanjiURL

        if let data = try? Data(contentsOf: wordURL),
           let decoded = try? JSONDecoder().decode([String: Level].self, from: data) {
            self.wordLevels = decoded
        }
        if let data = try? Data(contentsOf: kanjiURL),
           let decoded = try? JSONDecoder().decode([String: Level].self, from: data) {
            self.kanjiLevels = decoded
        }
    }

    func wordLevel(for word: String) -> Level {
        wordLevels[word] ?? .unknown
    }

    func kanjiLevel(for kanji: Character) -> Level {
        kanjiLevels[String(kanji)] ?? .unknown
    }

    func setWordLevel(_ level: Level, for word: String) {
        if level == .unknown {
            wordLevels.removeValue(forKey: word)
        } else {
            wordLevels[word] = level
        }
        persistWordLevels()
    }

    func setKanjiLevel(_ level: Level, for kanji: Character) {
        let key = String(kanji)
        if level == .unknown {
            kanjiLevels.removeValue(forKey: key)
        } else {
            kanjiLevels[key] = level
        }
        persistKanjiLevels()
    }

    private func persistWordLevels() {
        let snapshot = wordLevels
        let url = wordLevelsURL
        Task.detached {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistKanjiLevels() {
        let snapshot = kanjiLevels
        let url = kanjiLevelsURL
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

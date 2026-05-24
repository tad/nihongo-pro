import Foundation
import SwiftUI

struct SavedSession: Codable {
    let sentence: String
    let referenceTranslation: String
    let originalWords: [Word]
    let vocabPlan: [Word]
    let kanjiPlan: [String]
    let vocabIndex: Int
    let kanjiIndex: Int
    let studyVocab: [Word]
    let studyKanji: [String]
    let studyVocabIndex: Int
    let studyKanjiIndex: Int
    let phase: StudySession.Phase
    let savedAt: Date
}

@MainActor
@Observable
final class SavedSessionStore {
    static let shared = SavedSessionStore()

    private(set) var hasSavedSession: Bool = false
    private let storageURL: URL

    private init() {
        let dir = Self.storeDirectory()
        self.storageURL = dir.appendingPathComponent("saved_session.json")
        self.hasSavedSession = FileManager.default.fileExists(atPath: storageURL.path)
    }

    func save(_ saved: SavedSession) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        do {
            try data.write(to: storageURL, options: .atomic)
            hasSavedSession = true
        } catch {
            hasSavedSession = FileManager.default.fileExists(atPath: storageURL.path)
        }
    }

    func load() -> SavedSession? {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode(SavedSession.self, from: data) else {
            return nil
        }
        return saved
    }

    func clear() {
        try? FileManager.default.removeItem(at: storageURL)
        hasSavedSession = FileManager.default.fileExists(atPath: storageURL.path)
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

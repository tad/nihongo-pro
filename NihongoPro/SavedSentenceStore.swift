import Foundation
import SwiftUI

/// A sentence the user has bookmarked, with its full parse baked in so it can be
/// reopened offline (furigana + per-word definitions intact). `Word` is already
/// `Codable`, so the whole record persists trivially.
struct SavedSentence: Codable, Identifiable {
    let id: UUID
    let text: String
    let words: [Word]
    let englishTranslation: String
    /// Grammar-following literal rendering. Optional so sentences saved before this
    /// feature decode cleanly (older records simply have no literal translation).
    let literalTranslation: String?
    let savedAt: Date

    init(id: UUID = UUID(), text: String, words: [Word], englishTranslation: String, literalTranslation: String? = nil, savedAt: Date) {
        self.id = id
        self.text = text
        self.words = words
        self.englishTranslation = englishTranslation
        self.literalTranslation = literalTranslation
        self.savedAt = savedAt
    }
}

/// `@MainActor @Observable` disk-backed store for bookmarked sentences. Mirrors the
/// `FamiliarityStore` pattern: read synchronously inside SwiftUI bodies, writes
/// dispatched via `Task.detached` (atomic). Persists to
/// `applicationSupportDirectory/NihongoPro/saved_sentences.json`.
@MainActor
@Observable
final class SavedSentenceStore {
    static let shared = SavedSentenceStore()

    /// Newest first.
    private(set) var sentences: [SavedSentence] = []

    private let storeURL: URL

    private init() {
        let dir = Self.storeDirectory()
        self.storeURL = dir.appendingPathComponent("saved_sentences.json")

        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([SavedSentence].self, from: data) {
            self.sentences = decoded.sorted { $0.savedAt > $1.savedAt }
        }
    }

    /// A sentence is identified by its surface text — saving the same text twice
    /// updates the existing record rather than duplicating it.
    func isSaved(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sentences.contains { $0.text == trimmed }
    }

    func save(text: String, words: [Word], englishTranslation: String, literalTranslation: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.isEmpty else { return }
        sentences.removeAll { $0.text == trimmed }
        let entry = SavedSentence(
            text: trimmed,
            words: words,
            englishTranslation: englishTranslation,
            literalTranslation: literalTranslation,
            savedAt: Date()
        )
        sentences.insert(entry, at: 0)
        persist()
    }

    func remove(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sentences.removeAll { $0.text == trimmed }
        persist()
    }

    func remove(id: UUID) {
        sentences.removeAll { $0.id == id }
        persist()
    }

    /// Toggles save state for the given parse. Returns the new state (true = now saved).
    @discardableResult
    func toggle(text: String, words: [Word], englishTranslation: String, literalTranslation: String? = nil) -> Bool {
        if isSaved(text) {
            remove(text)
            return false
        } else {
            save(text: text, words: words, englishTranslation: englishTranslation, literalTranslation: literalTranslation)
            return true
        }
    }

    private func persist() {
        let snapshot = sentences
        let url = storeURL
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

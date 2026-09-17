import Foundation
import SwiftUI

/// A sentence the user has bookmarked, with its full parse baked in so it can be
/// reopened offline (furigana + per-word definitions intact). `Word` is already
/// `Codable`, so the whole record persists trivially.
nonisolated struct SavedSentence: Codable, Identifiable {
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

/// `@MainActor @Observable` store for bookmarked sentences. Sentences sync across
/// devices as a **union keyed by trimmed text**: this device tracks its own entries
/// and deletions (`mySaved`, with `deletedAt` tombstones), and the exposed
/// `sentences` merges them with every other device's slice (`remote`), taking the
/// most recent event (save or delete) per text. Tombstones stop a sentence deleted
/// on one device from resurrecting from another (see [SyncCoordinator]).
@MainActor
@Observable
final class SavedSentenceStore: RemoteSliceStore {
    static let shared = SavedSentenceStore()

    /// Merged, newest first, tombstones excluded.
    private(set) var sentences: [SavedSentence] = []

    /// This device's own entries, including `deletedAt` tombstones.
    private var mySaved: [SavedSliceEntry] = []
    /// Other devices' slices, keyed by deviceID.
    var remote: [String: DeviceSavedSlice] = [:]

    private let sliceURL: URL
    let remoteURL: URL

    private init() {
        let dir = AppDataDirectory.url()
        self.sliceURL = dir.appendingPathComponent("saved_slice.json")
        self.remoteURL = dir.appendingPathComponent("saved_remote.json")

        if let decoded = JSONStore.load(DeviceSavedSlice.self, from: sliceURL) {
            mySaved = decoded.entries
        } else if let decoded = JSONStore.load([SavedSentence].self, from: dir.appendingPathComponent("saved_sentences.json")) {
            // Migrate the pre-sync file on first run.
            mySaved = decoded.map {
                SavedSliceEntry(
                    id: $0.id,
                    text: $0.text,
                    words: $0.words,
                    englishTranslation: $0.englishTranslation,
                    literalTranslation: $0.literalTranslation,
                    savedAt: $0.savedAt,
                    deletedAt: nil
                )
            }
        }

        remote = JSONStore.load([String: DeviceSavedSlice].self, from: remoteURL) ?? [:]

        recompute()
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
        // Reuse this text's existing id on re-save so list identity stays stable.
        let existingID = mySaved.first(where: { $0.text == trimmed })?.id ?? UUID()
        mySaved.removeAll { $0.text == trimmed }
        mySaved.append(SavedSliceEntry(
            id: existingID,
            text: trimmed,
            words: words,
            englishTranslation: englishTranslation,
            literalTranslation: literalTranslation,
            savedAt: Date(),
            deletedAt: nil
        ))
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
    }

    func remove(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = mySaved.first(where: { $0.text == trimmed })
        mySaved.removeAll { $0.text == trimmed }
        // Record a tombstone (newer than any remote save) so the delete wins on merge.
        mySaved.append(SavedSliceEntry(
            id: existing?.id ?? UUID(),
            text: trimmed,
            words: existing?.words ?? [],
            englishTranslation: existing?.englishTranslation ?? "",
            literalTranslation: existing?.literalTranslation,
            savedAt: existing?.savedAt ?? .distantPast,
            deletedAt: Date()
        ))
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
    }

    func remove(id: UUID) {
        guard let text = sentences.first(where: { $0.id == id })?.text
            ?? mySaved.first(where: { $0.id == id })?.text else { return }
        remove(text)
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

    // MARK: Sync

    func localSlice() -> DeviceSavedSlice {
        DeviceSavedSlice(entries: mySaved)
    }

    func recompute() {
        sentences = Self.merge(my: mySaved, remote: remote.values.map(\.entries))
    }

    /// Union by text; the entry with the latest event (save or delete) wins; if that
    /// winner is a tombstone the text is omitted. Result is newest-save first.
    nonisolated static func merge(my: [SavedSliceEntry], remote: [[SavedSliceEntry]]) -> [SavedSentence] {
        var winners: [String: SavedSliceEntry] = [:]
        func consider(_ entry: SavedSliceEntry) {
            if let current = winners[entry.text] {
                if entry.eventTime > current.eventTime { winners[entry.text] = entry }
            } else {
                winners[entry.text] = entry
            }
        }
        for entry in my { consider(entry) }
        for slice in remote {
            for entry in slice { consider(entry) }
        }
        return winners.values
            .filter { $0.deletedAt == nil }
            .map {
                SavedSentence(
                    id: $0.id,
                    text: $0.text,
                    words: $0.words,
                    englishTranslation: $0.englishTranslation,
                    literalTranslation: $0.literalTranslation,
                    savedAt: $0.savedAt
                )
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private func persistSlice() {
        JSONStore.saveLater(localSlice(), to: sliceURL)
    }
}

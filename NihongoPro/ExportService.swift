import Foundation
import SwiftUI
import UIKit

/// Gathers every piece of locally-persisted progress into a single JSON document
/// the user can share out (AirDrop, Files, Mail…) as a backup. Round-trippable —
/// the file mirrors the on-disk JSON stores plus a small header.
enum ExportService {
    nonisolated struct ExportDocument: Encodable {
        let exportedAt: Date
        let appVersion: String
        let wordFrequencies: [String: Int]
        let kanjiFrequencies: [String: Int]
        let wordFamiliarity: [String: FamiliarityStore.Level]
        let kanjiFamiliarity: [String: FamiliarityStore.Level]
        let dailyActivity: [String: Int]
        let dailyStudySessions: [String: Int]
        let savedSentences: [SavedSentence]
    }

    /// Builds the export file in the temp directory and returns its URL, or nil on
    /// encode/write failure. Reads the latest in-memory state of every store so the
    /// export reflects edits made during this session.
    @MainActor
    static func makeExportFile() async -> URL? {
        let freq = FrequencyTracker.shared.snapshot()
        let familiarity = FamiliarityStore.shared
        let activity = ActivityTracker.shared
        let saved = SavedSentenceStore.shared

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let document = ExportDocument(
            exportedAt: Date(),
            appVersion: version,
            wordFrequencies: freq.words,
            kanjiFrequencies: freq.kanji,
            wordFamiliarity: familiarity.wordLevels,
            kanjiFamiliarity: familiarity.kanjiLevels,
            dailyActivity: activity.dailyCounts,
            dailyStudySessions: activity.dailySessions,
            savedSentences: saved.sentences
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoPro-Progress.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}

/// Thin wrapper around `UIActivityViewController` so a freshly-built export file can
/// be shared from SwiftUI via `.sheet(item:)`.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

import Foundation

/// One-way push of the merged familiarity (known/familiar words + kanji) to the Video-Study
/// Chrome extension via a small Cloudflare Worker relay. Nihongo Pro is the source of truth;
/// the extension pulls and merges. Uploads are debounced on change and fired once on launch.
///
/// Config: worker URL in `@AppStorage("videoStudySyncURL")`, shared secret in the Keychain
/// (`KeychainStore.Account.videoStudySync`). No-ops until both are set.
@MainActor
final class VideoStudySync {
    static let shared = VideoStudySync()
    private init() {}

    private var pending: Task<Void, Never>?

    private var config: (url: URL, secret: String)? {
        let urlString = (UserDefaults.standard.string(forKey: "videoStudySyncURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty,
              let secret = KeychainStore.read(account: .videoStudySync), !secret.isEmpty,
              let url = URL(string: urlString)
        else { return nil }
        return (url, secret)
    }

    var isConfigured: Bool { config != nil }

    /// Debounced upload — call on each familiarity change so rapid edits batch into one PUT.
    func scheduleUpload() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            await self?.upload()
        }
    }

    /// Immediate upload — call on launch.
    func uploadNow() {
        Task { await upload() }
    }

    private func upload() async {
        guard let (url, secret) = config else { return }

        // wordLevels/kanjiLevels are the merged view with tombstones already excluded.
        let store = FamiliarityStore.shared
        let words = store.wordLevels.mapValues { $0.rawValue }
        let kanji = store.kanjiLevels.mapValues { $0.rawValue }
        let payload: [String: Any] = ["words": words, "kanji": kanji]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url.appendingPathComponent("familiarity"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Shared-Secret")
        request.httpBody = body

        _ = try? await URLSession.shared.data(for: request)
    }
}

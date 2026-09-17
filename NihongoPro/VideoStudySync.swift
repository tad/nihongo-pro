import Foundation

/// Two-way familiarity sync with the **Video-Study** Chrome extension via a Cloudflare Worker
/// relay (KV-backed, `X-Shared-Secret` auth). Per-key newest-wins with tombstones, so marks
/// AND clears propagate both directions.
///
/// `sync()` pulls the relay blob and merges it into this device's slice (which then persists
/// and rides CloudKit to other devices), then pushes the merged familiarity back. Runs on
/// launch, on a periodic timer, and debounced after each local change.
///
/// Config: worker URL in `@AppStorage("videoStudySyncURL")`, shared secret in the Keychain
/// (`KeychainStore.Account.videoStudySync`). No-ops until both are set.
@MainActor
final class VideoStudySync {
    static let shared = VideoStudySync()
    private init() {}

    private var pending: Task<Void, Never>?

    // Wire format (matches the worker + extension). `level` ∈ unknown|familiar|known;
    // `t` is epoch milliseconds.
    nonisolated private struct WireEntry: Codable { let level: String; let t: Double }
    nonisolated private struct WireBlob: Codable {
        let words: [String: WireEntry]?
        let kanji: [String: WireEntry]?
    }
    nonisolated private struct WirePush: Codable {
        let words: [String: WireEntry]
        let kanji: [String: WireEntry]
    }

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

    func syncNow() {
        Task { await sync() }
    }

    /// Debounced sync — call after a local familiarity change so rapid edits batch.
    func scheduleSync() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            await self?.sync()
        }
    }

    func sync() async {
        guard let (url, secret) = config else { return }
        let endpoint = url.appendingPathComponent("familiarity")

        // 1. Pull + merge into this device's slice.
        if let blob = await get(endpoint, secret: secret) {
            FamiliarityStore.shared.applyVideoStudyEntries(
                word: entries(from: blob.words),
                kanji: entries(from: blob.kanji)
            )
        }

        // 2. Push the merged state (this device + CloudKit remotes), tombstones included.
        let merged = FamiliarityStore.shared.mergedFamiliarityForSync()
        let push = WirePush(words: wire(from: merged.word), kanji: wire(from: merged.kanji))
        await post(endpoint, secret: secret, body: push)
    }

    // MARK: Conversions

    private func entries(from dict: [String: WireEntry]?) -> [String: FamiliaritySliceEntry] {
        var out: [String: FamiliaritySliceEntry] = [:]
        for (key, e) in dict ?? [:] {
            out[key] = FamiliaritySliceEntry(level: e.level,
                                             modifiedAt: Date(timeIntervalSince1970: e.t / 1000))
        }
        return out
    }

    private func wire(from dict: [String: FamiliaritySliceEntry]) -> [String: WireEntry] {
        var out: [String: WireEntry] = [:]
        for (key, e) in dict {
            out[key] = WireEntry(level: e.level, t: e.modifiedAt.timeIntervalSince1970 * 1000)
        }
        return out
    }

    // MARK: HTTP

    private func get(_ endpoint: URL, secret: String) async -> WireBlob? {
        var request = URLRequest(url: endpoint)
        request.setValue(secret, forHTTPHeaderField: "X-Shared-Secret")
        guard let (data, resp) = try? await URLSession.shared.data(for: request),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let blob = try? JSONDecoder().decode(WireBlob.self, from: data)
        else { return nil }
        return blob
    }

    private func post(_ endpoint: URL, secret: String, body: WirePush) async {
        guard let data = try? JSONEncoder().encode(body) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Shared-Secret")
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
}

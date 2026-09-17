import Foundation
import os

/// One place for every store's JSON persistence.
///
/// The encoder and decoder deliberately keep Foundation's **default** strategies:
/// these bytes are read back by older installs of this app, by the kanji-study app
/// (through the shared CloudKit `DeviceSnapshot`), and by the migration paths, so
/// changing a key or date strategy here would silently break all of them.
/// (`ExportService` owns its own pretty-printed ISO-8601 encoder — that file format
/// is its own.)
nonisolated enum JSONStore {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    private static let log = Logger(subsystem: "com.terrydonaghe.NihongoPro", category: "store")

    /// Reads and decodes `url`, or nil if the file is missing or unreadable. A file
    /// that exists but fails to decode is logged — that is a bug or a format change,
    /// not the ordinary first-launch case.
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            log.error("Couldn't decode \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// `load(_:from:)` off the caller's actor, for payloads that arrive on the main
    /// actor (the CloudKit asset in `SyncCoordinator.applyFetched`).
    @concurrent
    static func loadAsync<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async -> T? {
        load(type, from: url)
    }

    /// Encodes `value` and writes it atomically, synchronously on the caller. Used
    /// by the actor stores (their executor is already off main) and by the one-shot
    /// migration writes in store inits.
    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't save \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Fire-and-forget encode + atomic write for the `@MainActor` stores. All writes
    /// go through one serial `Writer` actor, so two quick saves of the same file
    /// land in order (independent detached tasks could finish out of order and let
    /// the older snapshot win).
    static func saveLater<T: Encodable & Sendable>(_ value: T, to url: URL) {
        Task { await Writer.shared.save(value, to: url) }
    }

    private actor Writer {
        static let shared = Writer()

        func save<T: Encodable & Sendable>(_ value: T, to url: URL) {
            JSONStore.save(value, to: url)
        }
    }
}

// MARK: - Per-device remote slices

/// The part of the sync model every progress store shares: other devices' slices
/// keyed by device id, cached on disk so merged totals are right offline, and
/// merged into the store's exposed values by `recompute()`. `SyncCoordinator` routes
/// each fetched `DeviceSnapshot` to the stores through `applyRemoteSlice`.
@MainActor
protocol RemoteSliceStore: AnyObject {
    associatedtype Slice: Codable & Sendable
    var remote: [String: Slice] { get set }
    var remoteURL: URL { get }
    /// Rebuilds the merged values from this device's slice plus `remote`.
    func recompute()
}

extension RemoteSliceStore {
    func applyRemoteSlice(deviceID: String, slice: Slice) {
        remote[deviceID] = slice
        recompute()
        persistRemote()
    }

    func removeRemoteSlice(deviceID: String) {
        remote.removeValue(forKey: deviceID)
        recompute()
        persistRemote()
    }

    /// Drops every cached remote slice (iCloud sign-out); this device's own slice is untouched.
    func clearRemoteSlices() {
        remote.removeAll()
        recompute()
        persistRemote()
    }

    /// Device IDs whose slices this device has merged in (for the sync status UI).
    func knownRemoteDeviceIDs() -> [String] {
        Array(remote.keys)
    }

    func persistRemote() {
        JSONStore.saveLater(remote, to: remoteURL)
    }
}

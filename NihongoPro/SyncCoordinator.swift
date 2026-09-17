import CloudKit
import Foundation
import os

// MARK: - Observable sync status (for the Settings diagnostics UI)

/// Lightweight, UI-readable view of sync health. Updated by `SyncCoordinator` on the
/// main actor; read in `SettingsView`'s iCloud Sync section.
@MainActor
@Observable
final class SyncStatus {
    static let shared = SyncStatus()
    private init() {}

    var accountAvailable = true
    var isSyncing = false
    var lastSyncDate: Date?
    var lastError: String?
    /// Number of *other* devices whose data this device has merged in.
    var remoteDeviceCount = 0
}

// MARK: - Slice payload models
//
// Sync model: each device owns ONE CloudKit record (recordType "DeviceData",
// recordName == this device's stable UUID) in a custom zone of the user's PRIVATE
// database. The record's `payload` CKAsset is the JSON of this device's own
// contribution to every store (a `DeviceSnapshot`). Because no two devices ever
// write the same record, there are zero write conflicts. The app reconstructs the
// displayed values by MERGING all devices' snapshots:
//   - counters (frequencies, activity)  -> SUM per key across devices
//   - familiarity                        -> newest `modifiedAt` per key wins (.unknown = tombstone)
//   - saved sentences                    -> union by text, newest of savedAt/deletedAt wins
// See each store's `recompute…()` for the exact merge.

/// One familiarity rating with the time this device set it. `.unknown` is retained
/// as a tombstone (not removed) so a clear on one device can out-rank an older set
/// on another device during the merge.
struct FamiliaritySliceEntry: Codable {
    var level: String      // FamiliarityStore.Level.rawValue, including "unknown"
    var modifiedAt: Date
}

/// One saved sentence as this device knows it. `deletedAt != nil` is a tombstone.
struct SavedSliceEntry: Codable {
    var id: UUID
    var text: String
    var words: [Word]
    var englishTranslation: String
    var literalTranslation: String?
    var savedAt: Date
    var deletedAt: Date?

    /// The time of this entry's most recent event — used to pick a winner per text.
    var eventTime: Date { max(savedAt, deletedAt ?? .distantPast) }
}

struct DeviceFreqSlice: Codable {
    var word: [String: Int] = [:]
    var kanji: [String: Int] = [:]
}

struct DeviceActivitySlice: Codable {
    var daily: [String: Int] = [:]
    var sessions: [String: Int] = [:]
}

struct DeviceFamiliaritySlice: Codable {
    var word: [String: FamiliaritySliceEntry] = [:]
    var kanji: [String: FamiliaritySliceEntry] = [:]
}

struct DeviceSavedSlice: Codable {
    var entries: [SavedSliceEntry] = []
}

/// Everything this device contributes, serialized into its single CloudKit record.
struct DeviceSnapshot: Codable {
    var freq = DeviceFreqSlice()
    var activity = DeviceActivitySlice()
    var familiarity = DeviceFamiliaritySlice()
    var saved = DeviceSavedSlice()
    /// The shared kanji-info cache (meanings/readings/mnemonics), keyed by kanji.
    /// Optional so records written by older installs (and the kanji-study app before
    /// it published the slice) still decode. Merge is newest-`fetchedAt`-wins,
    /// straight into `DefinitionCache` — a union, not per-device slices, since cache
    /// entries are content anyone may re-publish.
    var kanjiInfo: [String: KanjiInfo]?
}

// MARK: - SyncCoordinator

/// Drives CloudKit sync of the four progress stores via `CKSyncEngine`. A single
/// shared instance is started once at app launch. Stores call `markDirty()` after a
/// local mutation; the coordinator gathers the current per-device snapshot and lets
/// the sync engine upload it, and routes fetched remote snapshots back to the stores.
///
/// `@MainActor`: the engine is created once, both delegate requirements are `async`
/// (so the engine simply awaits a hop onto main), and three of the four stores plus
/// `SyncStatus` already live on the main actor — so applying a fetched snapshot and
/// gathering this device's snapshot are straight-line, atomic code here, and
/// `markDirty()` / `engine` / `deferredDirty` are provably single-threaded. The two
/// actor-isolated stores (`FrequencyTracker`, `DefinitionCache`) call `markDirty()`
/// via `Task { @MainActor in … }`.
@MainActor
final class SyncCoordinator: NSObject, CKSyncEngineDelegate {
    static let shared = SyncCoordinator()

    private let containerID = "iCloud.com.terrydonaghe.NihongoPro"
    private let zoneID = CKRecordZone.ID(zoneName: "NihongoProSync")
    private let recordType = "DeviceData"

    private var engine: CKSyncEngine?
    private var started = false
    /// A mutation arrived before the engine finished starting; remember to push.
    private var deferredDirty = false

    private static let log = Logger(subsystem: "com.terrydonaghe.NihongoPro", category: "sync")

    /// Short form of this device's id, shown in Settings to match against the
    /// records in CloudKit Dashboard.
    static var shortDeviceID: String { String(deviceID.prefix(8)) }

    /// Stable per-install identifier; also the recordName of this device's record.
    static let deviceID: String = {
        let key = "syncDeviceID"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) { return existing }
        let new = UUID().uuidString
        defaults.set(new, forKey: key)
        return new
    }()

    private var myRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.deviceID, zoneID: zoneID)
    }

    private override init() { super.init() }

    // MARK: Start

    /// Builds the engine, ensures the zone exists, and runs an initial fetch + push.
    /// Safe to call once; no-ops on a second call. If iCloud is unavailable the
    /// engine simply stays idle and the app keeps working on local data.
    func start() async {
        guard !started else { return }
        started = true

        let container = CKContainer(identifier: containerID)
        await refreshAccountStatus(container)

        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: Self.loadState(),
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        Self.log.info("Sync engine started (device \(Self.shortDeviceID, privacy: .public))")

        // Make sure our zone exists and our record gets uploaded at least once
        // (this carries the migrated local data up on first launch).
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(myRecordID)])
        deferredDirty = false

        await refreshRemoteCount()
        await syncNow()
    }

    /// Forces a fetch + push and updates `SyncStatus`. Wired to the Settings
    /// "Sync now" button and run once on launch.
    func syncNow() async {
        guard let engine else { return }
        SyncStatus.shared.isSyncing = true
        SyncStatus.shared.lastError = nil
        do {
            try await engine.fetchChanges()
            do {
                try await engine.sendChanges()
            } catch {
                // A first send can fail with serverRecordChanged; the event handler
                // adopts the server record's change tag and re-queues, so one retry
                // typically succeeds.
                Self.log.warning("First send failed, retrying: \(Self.describe(error), privacy: .public)")
                try await engine.sendChanges()
            }
            Self.log.info("Sync completed")
            await refreshRemoteCount()
            SyncStatus.shared.isSyncing = false
            SyncStatus.shared.lastSyncDate = Date()
        } catch {
            let detail = Self.describe(error)
            Self.log.error("Sync failed: \(detail, privacy: .public)")
            SyncStatus.shared.isSyncing = false
            SyncStatus.shared.lastError = detail
        }
    }

    /// Unwraps a CloudKit error into a human-readable, diagnosable string — the bare
    /// `localizedDescription` of a sync failure is too generic ("Failed to send
    /// changes"); the real cause lives in the code / partial errors / underlying error.
    static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }
        var parts = ["CKError \(ckError.errorCode) (\(ckError.code)): \(ckError.localizedDescription)"]
        if let partial = ckError.partialErrorsByItemID, !partial.isEmpty {
            for (id, sub) in partial {
                let subDetail = (sub as? CKError).map { "\($0.code) — \($0.localizedDescription)" } ?? sub.localizedDescription
                parts.append("• \(id): \(subDetail)")
            }
        }
        if let underlying = ckError.userInfo[NSUnderlyingErrorKey] as? Error {
            parts.append("underlying: \(underlying.localizedDescription)")
        }
        if let retry = ckError.retryAfterSeconds {
            parts.append("retry after \(retry)s")
        }
        return parts.joined(separator: "\n")
    }

    /// Called by a store after it mutates its local slice. Queues this device's
    /// record for upload; the engine coalesces rapid calls.
    func markDirty() {
        guard let engine else { deferredDirty = true; return }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(myRecordID)])
    }

    private func refreshAccountStatus(_ container: CKContainer) async {
        let status = (try? await container.accountStatus()) ?? .couldNotDetermine
        let available = (status == .available)
        if !available {
            Self.log.warning("iCloud account not available: \(String(describing: status), privacy: .public)")
        }
        SyncStatus.shared.accountAvailable = available
    }

    private func refreshRemoteCount() async {
        SyncStatus.shared.remoteDeviceCount = await FrequencyTracker.shared.knownRemoteDeviceIDs().count
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            Self.saveState(update.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                if modification.record.recordID.recordName == Self.deviceID {
                    // Our own record came back — capture its change tag for future saves.
                    cacheRecordMetadata(modification.record)
                } else {
                    await applyFetched(modification.record)
                }
            }
            for deletion in changes.deletions {
                await applyDeletion(recordName: deletion.recordID.recordName)
            }
            if !changes.modifications.isEmpty || !changes.deletions.isEmpty {
                Self.log.info("Fetched \(changes.modifications.count) record(s), \(changes.deletions.count) deletion(s)")
                await refreshRemoteCount()
                SyncStatus.shared.lastSyncDate = Date()
            }

        case .sentRecordZoneChanges(let sent):
            // Capture change tags from successful saves so the next save is an update.
            for saved in sent.savedRecords where saved.recordID.recordName == Self.deviceID {
                cacheRecordMetadata(saved)
            }
            for failure in sent.failedRecordSaves {
                let recordID = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // The record already exists with a newer tag. Adopt the server's
                    // record metadata (carries the right change tag), then re-queue —
                    // the next save updates it instead of trying to re-insert.
                    if let serverRecord = failure.error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                        cacheRecordMetadata(serverRecord)
                    }
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                case .zoneNotFound, .userDeletedZone:
                    // Recreate the zone, then re-queue the record.
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                default:
                    let detail = Self.describe(failure.error)
                    Self.log.error("Record save failed: \(detail, privacy: .public)")
                    SyncStatus.shared.lastError = detail
                }
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        // Snapshot this device's current state once, then hand records to the engine.
        let snapshot = await gatherSnapshot()
        let myID = myRecordID

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard recordID == myID else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return await self.makeRecord(snapshot: snapshot)
        }
    }

    // MARK: Apply remote

    private func applyFetched(_ record: CKRecord) async {
        // Ignore our own record echoed back.
        guard record.recordID.recordName != Self.deviceID else { return }
        guard
            let asset = record["payload"] as? CKAsset,
            let url = asset.fileURL,
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(DeviceSnapshot.self, from: data)
        else { return }

        let remoteID = record.recordID.recordName
        let freqSlice = snapshot.freq
        await FrequencyTracker.shared.applyRemoteSlice(deviceID: remoteID, slice: freqSlice)
        if let kanjiInfo = snapshot.kanjiInfo, !kanjiInfo.isEmpty {
            await DefinitionCache.shared.applyRemoteKanjiInfo(kanjiInfo)
        }
        ActivityTracker.shared.applyRemoteSlice(deviceID: remoteID, slice: snapshot.activity)
        FamiliarityStore.shared.applyRemoteSlice(deviceID: remoteID, slice: snapshot.familiarity)
        SavedSentenceStore.shared.applyRemoteSlice(deviceID: remoteID, slice: snapshot.saved)
    }

    private func applyDeletion(recordName: String) async {
        guard recordName != Self.deviceID else { return }
        await FrequencyTracker.shared.removeRemoteSlice(deviceID: recordName)
        ActivityTracker.shared.removeRemoteSlice(deviceID: recordName)
        FamiliarityStore.shared.removeRemoteSlice(deviceID: recordName)
        SavedSentenceStore.shared.removeRemoteSlice(deviceID: recordName)
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signIn:
            markDirty()
        case .signOut, .switchAccounts:
            // Drop cached remote data; keep this device's own slices intact.
            await FrequencyTracker.shared.clearRemoteSlices()
            ActivityTracker.shared.clearRemoteSlices()
            FamiliarityStore.shared.clearRemoteSlices()
            SavedSentenceStore.shared.clearRemoteSlices()
        @unknown default:
            break
        }
    }

    // MARK: Snapshot assembly

    private func gatherSnapshot() async -> DeviceSnapshot {
        var snapshot = DeviceSnapshot()
        snapshot.freq = await FrequencyTracker.shared.localSlice()
        snapshot.kanjiInfo = await DefinitionCache.shared.kanjiInfoSlice()
        snapshot.activity = ActivityTracker.shared.localSlice()
        snapshot.familiarity = FamiliarityStore.shared.localSlice()
        snapshot.saved = SavedSentenceStore.shared.localSlice()
        return snapshot
    }

    /// Builds this device's record for upload. Crucially it reuses the cached record
    /// (carrying the server change tag) when we have one, so CloudKit treats the save
    /// as an UPDATE rather than an insert — a fresh `CKRecord` every time gets
    /// rejected with serverRecordChanged ("record to insert already exists").
    private func makeRecord(snapshot: DeviceSnapshot) -> CKRecord? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-\(Self.deviceID).json")
        do { try data.write(to: tmp, options: .atomic) } catch { return nil }
        let record = loadCachedRecord() ?? CKRecord(recordType: recordType, recordID: myRecordID)
        record["payload"] = CKAsset(fileURL: tmp)
        return record
    }

    // MARK: This device's record metadata (system fields / change tag)

    private static func myRecordURL() -> URL {
        AppDataDirectory.url().appendingPathComponent("sync_my_record.bin")
    }

    private func loadCachedRecord() -> CKRecord? {
        guard
            let data = try? Data(contentsOf: Self.myRecordURL()),
            let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    /// Persists a record's system fields (recordID + change tag) so the next save
    /// updates the existing server record instead of trying to re-insert it.
    private func cacheRecordMetadata(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        try? coder.encodedData.write(to: Self.myRecordURL(), options: .atomic)
    }

    // MARK: Engine state persistence

    private static func stateURL() -> URL {
        AppDataDirectory.url().appendingPathComponent("sync_engine_state.json")
    }

    private static func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL()) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL(), options: .atomic)
    }
}

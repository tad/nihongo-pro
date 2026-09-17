import Foundation
import SwiftUI

/// `@MainActor @Observable` per-day record of sentences parsed and pomodoro work
/// blocks completed, driving the streak counter and recent-activity charts in
/// `StatsView`. Counts are **additive across devices**: this device tracks only its
/// OWN per-day counts (`my…`), and the exposed `dailyCounts` / `dailySessions` are
/// the SUM of this device plus every other device's slice fetched via iCloud
/// (`remote`). Summing per-device slices means a day's count is never lost even if
/// the user studies on both devices (see [SyncCoordinator]). Keyed by local-day
/// string `yyyy-MM-dd` in the user's current calendar/timezone.
@MainActor
@Observable
final class ActivityTracker: RemoteSliceStore {
    static let shared = ActivityTracker()

    /// Merged (this device + all remote devices) totals. Read by `StatsView` /
    /// `ExportService`; recomputed whenever a slice changes.
    private(set) var dailyCounts: [String: Int] = [:]
    private(set) var dailySessions: [String: Int] = [:]

    /// This device's own counts.
    private var myDaily: [String: Int] = [:]
    private var mySessions: [String: Int] = [:]
    /// Other devices' slices, keyed by deviceID.
    var remote: [String: DeviceActivitySlice] = [:]

    private let sliceURL: URL
    let remoteURL: URL
    private let calendar = Calendar.current

    /// `DateFormatter` is thread-safe (and `Sendable` on the iOS 26 SDK), so one
    /// shared instance serves the nonisolated `dayKey(for:)`.
    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The local-day key a date falls on (`yyyy-MM-dd`, user's calendar/timezone).
    /// These strings are persisted, so the format is a contract.
    nonisolated static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private init() {
        let dir = AppDataDirectory.url()
        self.sliceURL = dir.appendingPathComponent("activity_slice.json")
        self.remoteURL = dir.appendingPathComponent("activity_remote.json")

        if let decoded = JSONStore.load(DeviceActivitySlice.self, from: sliceURL) {
            myDaily = decoded.daily
            mySessions = decoded.sessions
        } else {
            // Migrate from the pre-sync files on first run.
            myDaily = JSONStore.load([String: Int].self, from: dir.appendingPathComponent("daily_activity.json")) ?? [:]
            mySessions = JSONStore.load([String: Int].self, from: dir.appendingPathComponent("daily_sessions.json")) ?? [:]
        }
        remote = JSONStore.load([String: DeviceActivitySlice].self, from: remoteURL) ?? [:]

        recompute()
    }

    /// Called once per successfully parsed sentence.
    func recordParse(on date: Date = Date()) {
        let key = Self.dayFormatter.string(from: date)
        myDaily[key, default: 0] += 1
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
    }

    /// Called when a pomodoro 25-minute work block completes.
    func recordStudySession(on date: Date = Date()) {
        let key = Self.dayFormatter.string(from: date)
        mySessions[key, default: 0] += 1
        recompute()
        persistSlice()
        SyncCoordinator.shared.markDirty()
    }

    /// Sentences parsed today.
    var todayCount: Int {
        dailyCounts[Self.dayFormatter.string(from: Date())] ?? 0
    }

    /// Total pomodoro work blocks completed, all time.
    var totalStudySessions: Int {
        dailySessions.values.reduce(0, +)
    }

    /// Pomodoro work blocks completed today.
    var todayStudySessions: Int {
        dailySessions[Self.dayFormatter.string(from: Date())] ?? 0
    }

    /// Number of distinct days with at least one parse.
    var daysStudied: Int {
        dailyCounts.values.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
    }

    /// Consecutive days (ending today, or yesterday if nothing yet today) that have
    /// at least one parse. Today not yet counting doesn't break a streak earned
    /// through yesterday.
    var currentStreak: Int {
        Self.streak(in: dailyCounts, today: Date(), calendar: calendar)
    }

    /// Pure streak rule over per-day counts (see `currentStreak`).
    nonisolated static func streak(in counts: [String: Int], today now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        var streak = 0
        var cursor = today

        // If today has no activity yet, start counting from yesterday.
        if (counts[dayKey(for: today)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }

        while (counts[dayKey(for: cursor)] ?? 0) > 0 {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Parse counts for the last `days` days, oldest first, as `(date, count)` pairs
    /// — drives the recent-activity bar chart. Days with no activity yield 0.
    func recentDays(_ days: Int) -> [(date: Date, count: Int)] {
        recent(days, in: dailyCounts)
    }

    /// Completed-study-session counts for the last `days` days, oldest first.
    func recentStudySessions(_ days: Int) -> [(date: Date, count: Int)] {
        recent(days, in: dailySessions)
    }

    private func recent(_ days: Int, in dict: [String: Int]) -> [(date: Date, count: Int)] {
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = dict[Self.dayFormatter.string(from: day)] ?? 0
            return (date: day, count: count)
        }
    }

    // MARK: Sync

    func localSlice() -> DeviceActivitySlice {
        DeviceActivitySlice(daily: myDaily, sessions: mySessions)
    }

    func recompute() {
        var daily = myDaily
        var sessions = mySessions
        for slice in remote.values {
            for (k, v) in slice.daily { daily[k, default: 0] += v }
            for (k, v) in slice.sessions { sessions[k, default: 0] += v }
        }
        dailyCounts = daily
        dailySessions = sessions
    }

    private func persistSlice() {
        JSONStore.saveLater(localSlice(), to: sliceURL)
    }
}

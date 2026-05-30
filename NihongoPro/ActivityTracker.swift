import Foundation
import SwiftUI

/// `@MainActor @Observable` disk-backed record of how many sentences were parsed
/// each calendar day, used to drive the streak counter and the recent-activity
/// chart in `StatsView`. Mirrors the `FamiliarityStore` pattern (read synchronously
/// in SwiftUI bodies; writes dispatched via `Task.detached`). Persists to
/// `applicationSupportDirectory/NihongoPro/daily_activity.json` as `[yyyy-MM-dd: Int]`
/// keyed in the user's current calendar/timezone.
@MainActor
@Observable
final class ActivityTracker {
    static let shared = ActivityTracker()

    /// Keyed by local-day string `yyyy-MM-dd` → number of sentences parsed that day.
    private(set) var dailyCounts: [String: Int] = [:]
    /// Keyed by local-day string `yyyy-MM-dd` → number of pomodoro work blocks
    /// completed that day (counted when the 25-minute work timer finishes).
    private(set) var dailySessions: [String: Int] = [:]

    private let storeURL: URL
    private let sessionsURL: URL
    private let calendar = Calendar.current

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        let dir = Self.storeDirectory()
        self.storeURL = dir.appendingPathComponent("daily_activity.json")
        self.sessionsURL = dir.appendingPathComponent("daily_sessions.json")

        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.dailyCounts = decoded
        }
        if let data = try? Data(contentsOf: sessionsURL),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            self.dailySessions = decoded
        }
    }

    /// Called once per successfully parsed sentence.
    func recordParse(on date: Date = Date()) {
        let key = Self.dayFormatter.string(from: date)
        dailyCounts[key, default: 0] += 1
        persist()
    }

    /// Called when a pomodoro 25-minute work block completes.
    func recordStudySession(on date: Date = Date()) {
        let key = Self.dayFormatter.string(from: date)
        dailySessions[key, default: 0] += 1
        persistSessions()
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
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var cursor = today

        // If today has no activity yet, start counting from yesterday.
        if (dailyCounts[Self.dayFormatter.string(from: today)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }

        while (dailyCounts[Self.dayFormatter.string(from: cursor)] ?? 0) > 0 {
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

    private func persist() {
        let snapshot = dailyCounts
        let url = storeURL
        Task.detached {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistSessions() {
        let snapshot = dailySessions
        let url = sessionsURL
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

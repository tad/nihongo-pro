import Foundation
import Testing
@testable import NihongoPro

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func makeInfo(_ character: String = "展", fetchedAt: Date? = t0, pinned: Bool? = nil) -> KanjiInfo {
    KanjiInfo(character: character, meanings: ["display"], onyomi: ["テン"], kunyomi: [],
              note: nil, jlpt: 3, components: ["尸 flag"], mnemonic: "a story",
              example: nil, fetchedAt: fetchedAt, pinned: pinned)
}

/// Same rule as kanji-study's `KanjiInfoService.shouldAdopt`; the cases mirror its tests
/// so a pin set in either app keeps holding in both.
struct KanjiInfoMergeTests {
    @Test func adoptsWhenNothingCached() {
        #expect(DefinitionCache.shouldAdopt(remote: makeInfo(), over: nil))
    }

    @Test func newerRemoteReplacesUnpinnedLocal() {
        #expect(DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: t0 + 60), over: makeInfo(fetchedAt: t0)))
    }

    @Test func newerUnpinnedRemoteLosesToPinnedLocal() {
        #expect(!DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: t0 + 60),
                                             over: makeInfo(fetchedAt: t0, pinned: true)))
    }

    @Test func newerPinnedRemoteReplacesPinnedLocal() {
        #expect(DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: t0 + 60, pinned: true),
                                            over: makeInfo(fetchedAt: t0, pinned: true)))
    }

    @Test func equalTimestampsKeepLocal() {
        #expect(!DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: t0), over: makeInfo(fetchedAt: t0, pinned: true)))
        #expect(!DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: t0), over: makeInfo(fetchedAt: t0)))
    }

    @Test func legacyEntriesLoseToStampedOnes() {
        #expect(!DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: nil), over: makeInfo(fetchedAt: t0)))
        #expect(DefinitionCache.shouldAdopt(remote: makeInfo(fetchedAt: t0), over: makeInfo(fetchedAt: nil)))
    }
}

struct FamiliarityMergeTests {
    private func entry(_ level: FamiliarityStore.Level, _ at: Date) -> FamiliaritySliceEntry {
        FamiliaritySliceEntry(level: level.rawValue, modifiedAt: at)
    }

    @Test func newestWinsAndTombstonesDrop() {
        let my: [String: FamiliaritySliceEntry] = [
            "猫": entry(.known, t0),            // cleared later on another device
            "犬": entry(.known, t0 + 60),       // newer than the remote rating
        ]
        let remote: [[String: FamiliaritySliceEntry]] = [[
            "猫": entry(.unknown, t0 + 60),
            "犬": entry(.familiar, t0),
            "鳥": entry(.familiar, t0),
        ]]
        let merged = FamiliarityStore.merge(my: my, remote: remote)
        #expect(merged["猫"] == nil)
        #expect(merged["犬"] == .known)
        #expect(merged["鳥"] == .familiar)
    }

    @Test func mergeNewerReportsWhetherAnythingChanged() {
        var target: [String: FamiliaritySliceEntry] = ["猫": entry(.known, t0 + 60)]
        #expect(!FamiliarityStore.mergeNewer(["猫": entry(.familiar, t0)], into: &target))
        #expect(target["猫"]?.level == "known")
        #expect(FamiliarityStore.mergeNewer(["猫": entry(.familiar, t0 + 120)], into: &target))
        #expect(target["猫"]?.level == "familiar")
    }
}

struct SavedSentenceMergeTests {
    private func saved(_ text: String, at: Date, deletedAt: Date? = nil) -> SavedSliceEntry {
        SavedSliceEntry(id: UUID(), text: text, words: [], englishTranslation: "t",
                        literalTranslation: nil, savedAt: at, deletedAt: deletedAt)
    }

    @Test func unionByTextNewestEventWinsAndTombstonesHide() {
        let my = [saved("A", at: t0), saved("B", at: t0 + 20), saved("C", at: t0 + 5)]
        let remote = [[saved("A", at: t0, deletedAt: t0 + 60), saved("B", at: t0 + 10)]]
        let merged = SavedSentenceStore.merge(my: my, remote: remote)
        #expect(merged.map(\.text) == ["B", "C"])
        #expect(merged.first?.savedAt == t0 + 20)
    }

    @Test func aLaterSaveResurrectsADeletedSentence() {
        let my = [saved("A", at: t0 + 120)]
        let remote = [[saved("A", at: t0, deletedAt: t0 + 60)]]
        #expect(SavedSentenceStore.merge(my: my, remote: remote).map(\.text) == ["A"])
    }
}

struct DayKeyTests {
    /// The persisted-key contract: the new `Date.ISO8601FormatStyle` day key must equal
    /// what the original `en_US_POSIX` `yyyy-MM-dd` `DateFormatter` produced, across
    /// ~3000 consecutive local days (DST changes and year boundaries included).
    @Test func matchesTheLegacyDateFormatterForEveryDay() {
        let legacy = DateFormatter()
        legacy.locale = Locale(identifier: "en_US_POSIX")
        legacy.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: -1500, to: calendar.startOfDay(for: Date()))!
        var mismatches: [String] = []
        for _ in 0..<3000 {
            // Sample the start of the day and a moment late in it.
            for offset: TimeInterval in [0, 23 * 3600 + 59 * 60 + 30] {
                let sample = day.addingTimeInterval(offset)
                let expected = legacy.string(from: sample)
                let actual = ActivityTracker.dayKey(for: sample)
                if expected != actual { mismatches.append("\(expected) vs \(actual)") }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5))")
        #expect(ActivityTracker.dayKey(for: Date(timeIntervalSinceReferenceDate: 0)).count == 10)
    }
}

struct StreakTests {
    private let calendar = Calendar.current

    private func key(daysAgo: Int, from now: Date) -> String {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return ActivityTracker.dayKey(for: day)
    }

    @Test func countsBackFromToday() {
        let now = Date()
        let counts = [key(daysAgo: 0, from: now): 2, key(daysAgo: 1, from: now): 1, key(daysAgo: 2, from: now): 1]
        #expect(ActivityTracker.streak(in: counts, today: now, calendar: calendar) == 3)
    }

    @Test func todayNotYetStudiedDoesNotBreakTheStreak() {
        let now = Date()
        let counts = [key(daysAgo: 1, from: now): 1, key(daysAgo: 2, from: now): 3]
        #expect(ActivityTracker.streak(in: counts, today: now, calendar: calendar) == 2)
    }

    @Test func aGapEndsTheStreak() {
        let now = Date()
        let counts = [key(daysAgo: 0, from: now): 1, key(daysAgo: 2, from: now): 1]
        #expect(ActivityTracker.streak(in: counts, today: now, calendar: calendar) == 1)
        #expect(ActivityTracker.streak(in: [:], today: now, calendar: calendar) == 0)
    }
}

import SwiftUI

struct StatsView: View {
    let translator: TranslationService
    let speechService: SpeechService
    @Environment(\.dismiss) private var dismiss

    @State private var wordCounts: [String: Int] = [:]
    @State private var kanjiCounts: [String: Int] = [:]
    @State private var isLoading: Bool = true

    @State private var selectedWord: WordSelection?
    @State private var selectedKanji: KanjiSelection?
    @State private var exportItem: ExportItem?

    private let topListLimit = 25
    private let familiarity = FamiliarityStore.shared
    private let activity = ActivityTracker.shared

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    // 2-across on iPhone (a 4-column grid is far too cramped), 4-across on iPad.
    private var summaryColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: isPhone ? 2 : 4)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                ScrollView {
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.large)
                                .padding(.top, 80)
                        } else if wordCounts.isEmpty && kanjiCounts.isEmpty {
                            emptyState
                        } else {
                            content
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            if let url = await ExportService.makeExportFile() {
                                exportItem = ExportItem(url: url)
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export progress")
                    .disabled(wordCounts.isEmpty && kanjiCounts.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let snap = await FrequencyTracker.shared.snapshot()
                wordCounts = snap.words
                kanjiCounts = snap.kanji
                isLoading = false
            }
            .sheet(item: $selectedWord) { selection in
                WordDefinitionView(word: selection.word, translator: translator, speechService: speechService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedKanji) { selection in
                KanjiDetailView(kanji: selection.character, translator: translator)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(url: item.url)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            summaryCards
            activitySection
            kanjiSection
            wordsSection
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: summaryColumns, spacing: 12) {
                SummaryCard(label: "Day streak", value: activity.currentStreak, icon: "flame.fill", accent: .vermillion)
                SummaryCard(label: "Sessions", value: activity.totalStudySessions, icon: "timer")
                SummaryCard(label: "Days studied", value: activity.daysStudied, icon: "calendar")
                SummaryCard(label: "Today", value: activity.todayCount, icon: "sun.max.fill")
            }

            Divider()

            Text("Study sessions · last 14 days")
                .font(.headline)
                .foregroundStyle(.secondary)

            ActivityChart(days: activity.recentStudySessions(14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.55))
            Text("No data yet")
                .font(.title3)
            Text("Parse a sentence on the main screen and your progress will show up here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.top, 80)
    }

    private var summaryCards: some View {
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            SummaryCard(
                label: "Unique words",
                value: wordCounts.count,
                icon: "textformat",
                textIcon: "単語"
            )
            SummaryCard(
                label: "Unique kanji",
                value: kanjiCounts.count,
                icon: "character",
                textIcon: "漢字"
            )
            SummaryCard(
                label: "Known kanji",
                value: knownKanjiCount,
                icon: "checkmark.seal.fill",
                accent: .vermillion
            )
            SummaryCard(
                label: "Known words",
                value: knownWordCount,
                icon: "checkmark.seal.fill",
                accent: .vermillion
            )
        }
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Words")
                .font(.title3.weight(.semibold))

            DistributionBar(
                unknown: unknownWordCount,
                familiar: familiarWordCount,
                known: knownWordCount
            )

            Divider()

            Text("Most seen")
                .font(.headline)
                .foregroundStyle(.secondary)

            if topWords.isEmpty {
                Text("No words yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topWords.enumerated()), id: \.offset) { index, entry in
                        WordRow(
                            text: entry.key,
                            count: entry.value,
                            level: familiarity.wordLevels[entry.key] ?? .unknown,
                            onTap: { openWord(entry.key) }
                        )
                        if index < topWords.count - 1 {
                            Divider()
                        }
                    }
                }

                if wordCounts.count > topListLimit {
                    Text("+ \(wordCounts.count - topListLimit) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }

    private var kanjiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kanji")
                .font(.title3.weight(.semibold))

            DistributionBar(
                unknown: unknownKanjiCount,
                familiar: familiarKanjiCount,
                known: knownKanjiCount
            )

            Divider()

            Text("Most seen")
                .font(.headline)
                .foregroundStyle(.secondary)

            if topKanji.isEmpty {
                Text("No kanji yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topKanji.enumerated()), id: \.offset) { index, entry in
                        KanjiRow(
                            text: entry.key,
                            count: entry.value,
                            level: familiarity.kanjiLevels[entry.key] ?? .unknown,
                            onTap: {
                                if let ch = entry.key.first {
                                    selectedKanji = KanjiSelection(character: ch)
                                }
                            }
                        )
                        if index < topKanji.count - 1 {
                            Divider()
                        }
                    }
                }

                if kanjiCounts.count > topListLimit {
                    Text("+ \(kanjiCounts.count - topListLimit) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome()
    }

    /// Top-N entries by count (descending), ties broken by key so the order is stable.
    private func topEntries(in counts: [String: Int]) -> [(key: String, value: Int)] {
        Array(counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(topListLimit))
    }

    /// How many keys in `counts` are rated `level` — membership in `counts` filters
    /// out any hypothetical orphan rating so it can't inflate the tally.
    private func tally(_ level: FamiliarityStore.Level, in levels: [String: FamiliarityStore.Level], seenIn counts: [String: Int]) -> Int {
        levels.reduce(0) { total, entry in
            entry.value == level && counts[entry.key] != nil ? total + 1 : total
        }
    }

    private var topWords: [(key: String, value: Int)] { topEntries(in: wordCounts) }
    private var topKanji: [(key: String, value: Int)] { topEntries(in: kanjiCounts) }

    private var knownWordCount: Int { tally(.known, in: familiarity.wordLevels, seenIn: wordCounts) }
    private var familiarWordCount: Int { tally(.familiar, in: familiarity.wordLevels, seenIn: wordCounts) }
    private var unknownWordCount: Int {
        max(0, wordCounts.count - knownWordCount - familiarWordCount)
    }

    private var knownKanjiCount: Int { tally(.known, in: familiarity.kanjiLevels, seenIn: kanjiCounts) }
    private var familiarKanjiCount: Int { tally(.familiar, in: familiarity.kanjiLevels, seenIn: kanjiCounts) }
    private var unknownKanjiCount: Int {
        max(0, kanjiCounts.count - knownKanjiCount - familiarKanjiCount)
    }

    private func openWord(_ text: String) {
        Task {
            let definition = await DefinitionCache.shared.definition(for: text)
            let word = Word(
                text: text,
                reading: text,
                furigana: [FuriganaSegment(text: text, reading: nil)],
                definition: definition
            )
            selectedWord = WordSelection(word: word)
        }
    }
}

private struct WordSelection: Identifiable {
    let id = UUID()
    let word: Word
}

private struct KanjiSelection: Identifiable {
    let id = UUID()
    let character: Character
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// A compact bar chart of the last N days of parsing activity. Bars grow upward from
/// a shared baseline above narrow weekday labels; today's bar is vermillion-accented.
private struct ActivityChart: View {
    let days: [(date: Date, count: Int)]

    /// Drives the appear animation: bars grow up from the baseline with a
    /// slight left-to-right stagger the first time the chart is shown.
    @State private var appeared = false

    private var maxCount: Int { max(days.map(\.count).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isToday(day.date) ? Color.vermillion : Color.accentColor.opacity(day.count > 0 ? 0.7 : 0.15))
                        .frame(height: barHeight(day.count))
                        .scaleEffect(y: appeared ? 1 : 0.05, anchor: .bottom)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.03),
                            value: appeared
                        )
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .foregroundStyle(isToday(day.date) ? Color.vermillion : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96)
        .onAppear { appeared = true }
    }

    private func barHeight(_ count: Int) -> CGFloat {
        let maxBar: CGFloat = 64
        guard count > 0 else { return 3 }
        return max(6, maxBar * CGFloat(count) / CGFloat(maxCount))
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

private struct SummaryCard: View {
    let label: String
    let value: Int
    let icon: String
    var textIcon: String? = nil
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let textIcon {
                Text(textIcon)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(accent)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
            }
            Text("\(value)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: value)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 1)
    }
}

private struct DistributionBar: View {
    let unknown: Int
    let familiar: Int
    let known: Int

    /// Drives the appear animation: segments sweep in from the left.
    @State private var appeared = false

    private var total: Int { unknown + familiar + known }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(count: unknown, width: width(for: unknown, in: geo.size.width), color: Color.secondary.opacity(0.35))
                    segment(count: familiar, width: width(for: familiar, in: geo.size.width), color: Color.accentColor)
                    segment(count: known, width: width(for: known, in: geo.size.width), color: Color.vermillion)
                }
                // Sweep in from the left on appear; also animate when the
                // counts shift live (e.g. rating a word in a nested modal).
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: appeared)
                .animation(.smooth(duration: 0.35), value: [unknown, familiar, known])
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .onAppear { appeared = true }

            HStack(spacing: 18) {
                LegendChip(color: Color.secondary.opacity(0.35), label: "Unknown", count: unknown)
                LegendChip(color: Color.accentColor, label: "Familiar", count: familiar)
                LegendChip(color: Color.vermillion, label: "Known", count: known)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func segment(count: Int, width: CGFloat, color: Color) -> some View {
        if count > 0 {
            Rectangle()
                .fill(color)
                .frame(width: width)
        }
    }

    private func width(for count: Int, in totalWidth: CGFloat) -> CGFloat {
        guard total > 0, count > 0, appeared else { return 0 }
        return max(2, totalWidth * CGFloat(count) / CGFloat(total))
    }
}

private struct LegendChip: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct WordRow: View {
    let text: String
    let count: Int
    let level: FamiliarityStore.Level
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(text)
                    .font(.system(size: 26, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                LevelDot(level: level)

                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct KanjiRow: View {
    let text: String
    let count: Int
    let level: FamiliarityStore.Level
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(text)
                    .font(.system(size: 36, design: .serif))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 48, alignment: .leading)

                Spacer(minLength: 8)

                LevelDot(level: level)

                Text("\(count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LevelDot: View {
    let level: FamiliarityStore.Level

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(level.label)
    }

    private var color: Color {
        switch level {
        case .unknown: return Color.secondary.opacity(0.35)
        case .familiar: return Color.accentColor
        case .known: return Color.vermillion
        }
    }
}

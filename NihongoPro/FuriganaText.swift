import SwiftUI

struct FuriganaText: View {
    let words: [Word]
    var showFurigana: Bool = false
    /// Reading-drill mode: all furigana is hidden and tapping a word reveals just
    /// its reading inline (instead of opening the definition modal).
    var drillMode: Bool = false
    var baseFont: Font = .system(size: 44, weight: .regular, design: .serif)
    var rubyFont: Font = .system(size: 18, weight: .regular, design: .serif)
    var rubyColor: Color = .secondary
    var wordSpacing: CGFloat = 4
    var lineSpacing: CGFloat = 14
    var onWordTap: (Word) -> Void = { _ in }

    /// Indices whose reading has been revealed in drill mode. Reset whenever the
    /// sentence changes so reveals never leak across parses.
    @State private var revealedIndices: Set<Int> = []

    var body: some View {
        let store = FamiliarityStore.shared
        FuriganaFlowLayout(spacing: wordSpacing, lineSpacing: lineSpacing) {
            ForEach(words.indices, id: \.self) { index in
                let word = words[index]
                if drillMode {
                    let revealable = Self.hasReading(word)
                    Button {
                        guard revealable else { return }
                        withAnimation(.smooth(duration: 0.2)) {
                            if revealedIndices.contains(index) {
                                revealedIndices.remove(index)
                            } else {
                                revealedIndices.insert(index)
                            }
                        }
                    } label: {
                        WordView(
                            word: word,
                            baseFont: baseFont,
                            rubyFont: rubyFont,
                            rubyColor: rubyColor,
                            hideFurigana: !revealedIndices.contains(index),
                            underline: revealable
                        )
                    }
                    .buttonStyle(WordTapStyle())
                    .disabled(!revealable)
                } else {
                    Button {
                        onWordTap(word)
                    } label: {
                        WordView(
                            word: word,
                            baseFont: baseFont,
                            rubyFont: rubyFont,
                            rubyColor: rubyColor,
                            hideFurigana: !showFurigana || Self.shouldHideFurigana(for: word, store: store),
                            underline: word.definition != nil
                        )
                    }
                    .buttonStyle(WordTapStyle())
                    .disabled(word.definition == nil)
                }
            }
        }
        .onChange(of: words.map(\.text).joined()) { _, _ in
            revealedIndices = []
        }
    }

    /// A word can be drilled if it has at least one furigana segment with a reading
    /// to reveal (i.e. it contains kanji). Pure-kana words have nothing to test.
    private static func hasReading(_ word: Word) -> Bool {
        word.furigana.contains { $0.reading != nil }
    }

    private static func shouldHideFurigana(for word: Word, store: FamiliarityStore) -> Bool {
        if store.wordLevel(for: word.text) == .known { return true }
        let kanjiChars = word.text.filter { $0.isKanji }
        guard !kanjiChars.isEmpty else { return false }
        return kanjiChars.allSatisfy { store.kanjiLevel(for: $0) == .known }
    }
}

/// Subtle pressed-state feedback for the tappable words in the sentence display:
/// a small scale-down plus dimming while the finger is down. Replaces `.plain`,
/// which gives no touch feedback at all.
private struct WordTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

private struct WordView: View {
    let word: Word
    let baseFont: Font
    let rubyFont: Font
    let rubyColor: Color
    let hideFurigana: Bool
    /// Whether to draw the accent underline that marks the word as tappable.
    let underline: Bool

    var body: some View {
        let store = FamiliarityStore.shared
        HStack(spacing: 0) {
            ForEach(word.furigana.indices, id: \.self) { i in
                let seg = word.furigana[i]
                VStack(spacing: 2) {
                    Text(seg.reading ?? " ")
                        .font(rubyFont)
                        .foregroundStyle(rubyColor)
                        .opacity((hideFurigana || seg.reading == nil) ? 0 : 1)
                    Self.markedUpText(seg.text, store: store)
                        .font(baseFont)
                }
                .fixedSize()
            }
        }
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            if underline {
                Capsule()
                    .fill(underlineStyle(store: store))
                    .frame(height: 3)
            }
        }
        .contentShape(Rectangle())
    }

    /// Segment text with each kanji tinted by its familiarity level (green for
    /// Known, amber for Familiar); kana and unrated kanji keep the default color.
    private static func markedUpText(_ text: String, store: FamiliarityStore) -> Text {
        text.reduce(Text(verbatim: "")) { result, char in
            var t = Text(String(char))
            if char.isKanji, let color = store.kanjiLevel(for: char).markupColor {
                t = t.foregroundStyle(color)
            }
            return result + t
        }
    }

    /// Underline color follows the word-level familiarity; unrated words keep the
    /// accent tint so the tappable cue is unchanged for them.
    private func underlineStyle(store: FamiliarityStore) -> AnyShapeStyle {
        if let color = store.wordLevel(for: word.text).markupColor {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(.tint)
    }
}

struct FuriganaFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + max(0, CGFloat(rows.count - 1) * lineSpacing)
        let width = rows.map { $0.width }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let yOffset = row.height - item.size.height
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let extraSpacing = current.items.isEmpty ? 0 : spacing
            if current.width + extraSpacing + size.width > maxWidth && !current.items.isEmpty {
                rows.append(current)
                current = Row()
                current.items.append(RowItem(index: index, size: size))
                current.width = size.width
                current.height = size.height
            } else {
                current.items.append(RowItem(index: index, size: size))
                current.width += extraSpacing + size.width
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

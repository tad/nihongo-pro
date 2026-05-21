import SwiftUI

struct FuriganaText: View {
    let words: [Word]
    var baseFont: Font = .system(size: 44, weight: .regular, design: .serif)
    var rubyFont: Font = .system(size: 18, weight: .regular, design: .serif)
    var rubyColor: Color = .secondary
    var wordSpacing: CGFloat = 4
    var lineSpacing: CGFloat = 14
    var onWordTap: (Word) -> Void = { _ in }

    var body: some View {
        FuriganaFlowLayout(spacing: wordSpacing, lineSpacing: lineSpacing) {
            ForEach(words.indices, id: \.self) { index in
                let word = words[index]
                Button {
                    onWordTap(word)
                } label: {
                    WordView(word: word, baseFont: baseFont, rubyFont: rubyFont, rubyColor: rubyColor)
                }
                .buttonStyle(.plain)
                .disabled(word.definition == nil)
            }
        }
    }
}

private struct WordView: View {
    let word: Word
    let baseFont: Font
    let rubyFont: Font
    let rubyColor: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(word.furigana.indices, id: \.self) { i in
                let seg = word.furigana[i]
                VStack(spacing: 2) {
                    Text(seg.reading ?? " ")
                        .font(rubyFont)
                        .foregroundStyle(rubyColor)
                        .opacity(seg.reading == nil ? 0 : 1)
                    Text(seg.text)
                        .font(baseFont)
                }
                .fixedSize()
            }
        }
        .contentShape(Rectangle())
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

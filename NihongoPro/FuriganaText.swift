import SwiftUI

struct FuriganaText: View {
    let segments: [FuriganaSegment]
    var baseFont: Font = .system(size: 44, weight: .regular, design: .serif)
    var rubyFont: Font = .system(size: 18, weight: .regular, design: .serif)
    var rubyColor: Color = .secondary
    var segmentSpacing: CGFloat = 1
    var lineSpacing: CGFloat = 14

    var body: some View {
        FuriganaFlowLayout(spacing: segmentSpacing, lineSpacing: lineSpacing) {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                VStack(spacing: 2) {
                    Text(segment.reading ?? " ")
                        .font(rubyFont)
                        .foregroundStyle(rubyColor)
                        .opacity(segment.reading == nil ? 0 : 1)
                    Text(segment.text)
                        .font(baseFont)
                        .textSelection(.enabled)
                }
                .fixedSize()
            }
        }
    }
}

struct FuriganaFlowLayout: Layout {
    var spacing: CGFloat = 1
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

import SwiftUI

struct BreakdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(parseBlocks(from: markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(attributed(text))
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .padding(.top, level <= 2 ? 12 : 4)
        case .paragraph(let text):
            Text(attributed(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(attributed(text))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.semibold)
        case 2: return .title2.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

private enum Block {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String)
}

private func parseBlocks(from markdown: String) -> [Block] {
    var blocks: [Block] = []
    var paragraphBuffer: [String] = []

    func flushParagraph() {
        if !paragraphBuffer.isEmpty {
            let text = paragraphBuffer.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text: text))
            }
            paragraphBuffer.removeAll()
        }
    }

    for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            flushParagraph()
            continue
        }

        if let heading = parseHeading(trimmed) {
            flushParagraph()
            blocks.append(heading)
            continue
        }

        if let bullet = parseBullet(trimmed) {
            flushParagraph()
            blocks.append(bullet)
            continue
        }

        paragraphBuffer.append(trimmed)
    }
    flushParagraph()
    return blocks
}

private func parseHeading(_ text: String) -> Block? {
    var hashes = 0
    var index = text.startIndex
    while index < text.endIndex, text[index] == "#", hashes < 6 {
        hashes += 1
        index = text.index(after: index)
    }
    guard hashes > 0, index < text.endIndex, text[index] == " " else { return nil }
    let content = String(text[text.index(after: index)...]).trimmingCharacters(in: .whitespaces)
    return .heading(level: hashes, text: content)
}

private func parseBullet(_ text: String) -> Block? {
    if text.hasPrefix("- ") || text.hasPrefix("* ") {
        let content = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return .bullet(text: content)
    }
    return nil
}

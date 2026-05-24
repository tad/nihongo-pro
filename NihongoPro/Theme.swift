import SwiftUI

extension Font {
    static let displayKanji = Font.system(size: 96, weight: .regular, design: .serif)
    static let displayWord = Font.system(size: 72, weight: .regular, design: .serif)
    static let sentenceLarge = Font.system(size: 32, weight: .regular, design: .serif)
}

extension View {
    func cardChrome(cornerRadius: CGFloat = 20, padding: CGFloat = 24) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 2)
    }
}

struct NihongoLookupLink: View {
    enum Kind {
        case word
        case kanji

        var pathSegment: String {
            switch self {
            case .word: return "word"
            case .kanji: return "kanji"
            }
        }
    }

    let kind: Kind
    let query: String

    private var url: URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://nihongo-app.com/dictionary/\(kind.pathSegment)/\(encoded)")
    }

    var body: some View {
        if let url {
            Link(destination: url) {
                Label("Look up in Nihongo", systemImage: "arrow.up.forward.app")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct JishoLookupLink: View {
    enum Kind {
        case word
        case kanji
    }

    let kind: Kind
    let query: String

    private var url: URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let queryString: String
        switch kind {
        case .word: queryString = trimmed
        case .kanji: queryString = "\(trimmed) #kanji"
        }
        guard let encoded = queryString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://jisho.org/search/\(encoded)")
    }

    var body: some View {
        if let url {
            Link(destination: url) {
                Label("Look up in Jisho", systemImage: "arrow.up.forward.app")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

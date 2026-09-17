import SwiftUI

extension Font {
    static let displayKanji = Font.system(size: 96, weight: .regular, design: .serif)
}

extension FamiliarityStore.Level {
    /// Knowledge-markup color for the sentence display: Known is green, Familiar
    /// is amber, Unknown is nil (default text color / accent underline).
    var markupColor: Color? {
        switch self {
        case .known: return .knownGreen
        case .familiar: return .learningYellow
        case .unknown: return nil
        }
    }
}

extension PronunciationScorer.Outcome {
    /// Pronunciation-practice markup: a word you read correctly is green, a
    /// partly-recognized word amber, a missed word red — overriding the familiarity
    /// colors while a result is shown.
    var markupColor: Color {
        switch self {
        case .matched: return .knownGreen
        case .partial: return .learningYellow
        case .missed: return .red
        }
    }
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

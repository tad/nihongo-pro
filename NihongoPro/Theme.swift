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

/// The dimming level for selectable text — see `View.selectableLabel(_:)`.
enum LabelLevel {
    case secondary
    case tertiary

    /// `secondaryLabel` / `tertiaryLabel` are the label color at 60 % / 30 % alpha in
    /// both appearances, so the same opacity on primary text reads identically.
    var opacity: Double {
        switch self {
        case .secondary: return 0.6
        case .tertiary: return 0.3
        }
    }
}

extension View {
    /// `.textSelection(.enabled)` plus secondary/tertiary dimming for a `Text`.
    ///
    /// iOS 27 draws **nothing** for a selectable `Text` that carries any foreground
    /// style — `.foregroundStyle(.secondary)` on the text itself, a style inherited
    /// from a container, or a `foregroundColor` run inside its `AttributedString` —
    /// when it sits on a material background, i.e. inside every `cardChrome` card
    /// (verified on the iOS 27.0 simulator; on a plain background it still draws,
    /// and iOS 26 is unaffected). The definition sheet's reading line and the
    /// revealed translation vanished this way. Opacity is applied after selection
    /// instead, which renders everywhere and looks the same as the hierarchical
    /// styles. Use this, never `.foregroundStyle`, on anything selectable —
    /// `SelectableTextTests` renders the pattern on a card and enforces the rule.
    func selectableLabel(_ level: LabelLevel) -> some View {
        self
            .textSelection(.enabled)
            .opacity(level.opacity)
    }

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

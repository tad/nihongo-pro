import Testing
@testable import NihongoPro

/// Mirrored from the kanji-study app's `KradTests` — both apps ship byte-identical
/// `Krad.swift` / `KradKeywords.swift` / `krad_decompositions.json`, and both now
/// enforce the keyword-completeness invariant.
struct KradTests {
    @Test func decompositionsLoadFromTheBundle() {
        #expect(Krad.decompositions.count >= 12_000)
        #expect(Krad.parts(for: "亜") == ["｜", "一", "口"])
        #expect(Krad.parts(for: "\u{1F600}").isEmpty)
    }

    /// The keyword table is hand-authored; this is what keeps it honest when the
    /// KRAD data is ever regenerated.
    @Test func everyComponentHasAKeyword() {
        var missing: Set<String> = []
        for parts in Krad.decompositions.values {
            for part in parts where KradKeywords.keywords[part] == nil {
                missing.insert(part)
            }
        }
        #expect(missing.isEmpty, "components without a keyword: \(missing.sorted().joined())")
    }

    /// KRADFILE substitutes a containing kanji where JIS X 0208 lacks the radical
    /// form; the picker and the prompt must show the real glyph instead.
    @Test func standInsResolveToTheVisibleGlyph() {
        #expect(Krad.glyph(for: "汁") == "氵")
        #expect(Krad.glyph(for: "艾") == "艹")
        #expect(Krad.glyph(for: "口") == "口")
        #expect(Krad.label(for: "汁") == "氵 water")
        #expect(Krad.label(for: "尸") == "尸 flag")
    }

    @Test func labelFallsBackToTheBareGlyph() {
        #expect(Krad.label(for: "\u{1F600}") == "\u{1F600}")
    }

    /// The two 阝 forms share a glyph but must stay distinguishable by keyword.
    @Test func leftAndRightMoundKeepDistinctKeywords() {
        #expect(Krad.glyph(for: "邦") == Krad.glyph(for: "阡"))
        #expect(Krad.label(for: "邦") != Krad.label(for: "阡"))
    }
}

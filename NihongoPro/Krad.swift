import Foundation

/// Kanji → visible-component decompositions, bundled as `krad_decompositions.json`.
///
/// Converted once from EDRDG's KRADFILE and KRADFILE2 (© Electronic Dictionary
/// Research and Development Group, EDRDG licence / CC BY-SA — attribution shows in
/// the mnemonic editor and the README, alongside KanjiVG's). 12,156 kanji over 253
/// distinct components. The source files are EUC-JP `亜 : ｜ 一 口` lines; the
/// committed JSON is the UTF-8 result.
///
/// KRADFILE is built for radical *lookup*, not for teaching, so it decomposes more
/// aggressively than a mnemonic wants — 漢 lists six parts, including sub-parts of
/// parts. That is fine here: the editor shows the parts as candidates and the user
/// picks the subset the story should use.
///
/// MIRRORED with the kanji-study app's `Krad.swift`; keep the two in step.
enum Krad {
    /// Decoded lazily on first use (first time the mnemonic editor opens), off the
    /// kanji-modal load path. A missing or unreadable resource degrades to no
    /// candidates rather than failing — the editor then falls back to the
    /// components the model itself listed.
    static let decompositions: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "krad_decompositions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// Raw KRADFILE component characters for a kanji, in file order. Empty when the
    /// kanji isn't in the data.
    static func parts(for kanji: String) -> [String] {
        decompositions[kanji] ?? []
    }

    /// The glyph the learner actually sees for a component — the KRADFILE stand-in
    /// resolved to its real form (汁 → 氵, 艾 → 艹). Unmapped parts are themselves.
    static func glyph(for part: String) -> String {
        KradKeywords.displayGlyphs[part] ?? part
    }

    /// "氵 water"-style label in the same shape as `KanjiInfo.components`, ready to
    /// display and to hand to the model. Falls back to the bare glyph when a
    /// component somehow has no keyword.
    static func label(for part: String) -> String {
        let glyph = glyph(for: part)
        guard let keyword = KradKeywords.keywords[part] else { return glyph }
        return "\(glyph) \(keyword)"
    }
}

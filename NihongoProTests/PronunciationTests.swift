import Testing
@testable import NihongoPro

private func word(_ text: String, _ reading: String) -> Word {
    Word(text: text, reading: reading, furigana: [FuriganaSegment(text: text, reading: reading == text ? nil : reading)])
}

private let sentence: [Word] = [
    word("猫", "ねこ"), word("は", "は"), word("窓", "まど"), word("の", "の"), word("外", "そと"),
    word("の", "の"), word("雨", "あめ"), word("を", "を"), word("じっと", "じっと"), word("見ていた", "みていた"),
    word("。", "。"),
]

struct PronunciationNormalizeTests {
    @Test func katakanaBecomesHiraganaAndLengthMarksDrop() {
        #expect(PronunciationScorer.normalize("キョウ") == "きょう")
        #expect(PronunciationScorer.normalize("コーヒー") == "こひ")
        #expect(PronunciationScorer.normalize("がっこう") == "がこう")
    }

    @Test func particlesCollapseOntoTheirSpokenSound() {
        #expect(PronunciationScorer.normalize("は") == "わ")
        #expect(PronunciationScorer.normalize("を") == "お")
        #expect(PronunciationScorer.normalize("へ") == "え")
    }

    @Test func punctuationSpacesAndKanjiAreDropped() {
        #expect(PronunciationScorer.normalize("ねこ、 は 猫。") == "ねこわ")
        #expect(PronunciationScorer.normalize("きゃ").count == 2) // small ゃ is kept
    }
}

struct PronunciationScoreTests {
    @Test func aFullReadingMatchesEveryWord() {
        let result = PronunciationScorer.score(expected: sentence, transcript: "ねこはまどのそとのあめをじっとみていた")
        #expect(result.total == 10) // the 。 is not scored
        #expect(result.matched == 10)
        #expect(result.outcomes[10] == nil)
        #expect(result.outcomes[0] == .matched)
        #expect(result.outcomes[9] == .matched)
    }

    @Test func aSkippedWordIsMissedAndTheRestStillMatch() {
        let result = PronunciationScorer.score(expected: sentence, transcript: "ねこはまどのそとのあめをみていた")
        #expect(result.outcomes[8] == .missed)   // じっと
        #expect(result.outcomes[9] == .matched)  // 見ていた, after the gap
        #expect(result.matched == 9)
    }

    @Test func aGarbledWordIsPartial() {
        // 見ていた read as みてた: 3 of 4 kana align → partial, not missed.
        let result = PronunciationScorer.score(expected: sentence, transcript: "ねこはまどのそとのあめをじっとみてた")
        #expect(result.outcomes[9] == .partial)
    }

    @Test func silenceMissesEverything() {
        let result = PronunciationScorer.score(expected: sentence, transcript: "")
        #expect(result.matched == 0)
        #expect(result.outcomes.values.allSatisfy { $0 == .missed })
    }

    @Test func kanjiMixedTranscriptsAreReadAsKana() {
        // What the transcriber actually returns: kanji-mixed text.
        let result = PronunciationScorer.score(expected: sentence, transcript: "猫は窓の外の雨をじっと見ていた")
        #expect(result.matched >= 8, "\(result)")
    }

    @Test func alignmentMarksTheCommonSubsequence() {
        let used = PronunciationScorer.alignment(of: Array("abcde"), in: Array("axcxe"))
        #expect(used == [true, false, true, false, true])
    }
}

struct KanaReadingTests {
    @Test func transliteratesKanjiToHiragana() throws {
        let kana = try #require(KanaReading.hiragana(of: "今日は天気"))
        #expect(kana.contains("きょう"))
        #expect(kana.contains("てんき"))
    }

    @Test func emptyTextHasNoReading() {
        #expect(KanaReading.hiragana(of: "") == nil)
    }
}

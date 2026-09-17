import Testing
@testable import NihongoPro

struct JapaneseWordFilterTests {
    @Test func japanesePunctuationAndWhitespaceArePure() {
        for text in ["。", "、", "「", "」", "！", "？", "…", "・", "〜", "\u{3000}", " ", "\n", "。」", "?!"] {
            #expect(JapaneseWordFilter.isPurePunctuation(text), "\(text.debugDescription) should be pure punctuation")
        }
    }

    @Test func wordsAndLongVowelMarksAreNot() {
        for text in ["ー", "今日", "じっと", "猫。", ""] {
            #expect(!JapaneseWordFilter.isPurePunctuation(text), "\(text.debugDescription) should not be pure punctuation")
        }
    }

    @Test func particlesAndPunctuationAreNotCounted() {
        #expect(!JapaneseWordFilter.shouldCount("は"))
        #expect(!JapaneseWordFilter.shouldCount("って"))
        #expect(!JapaneseWordFilter.shouldCount("。"))
        #expect(!JapaneseWordFilter.shouldCount(""))
        #expect(JapaneseWordFilter.shouldCount("猫"))
        #expect(JapaneseWordFilter.shouldCount("見ていた"))
    }
}

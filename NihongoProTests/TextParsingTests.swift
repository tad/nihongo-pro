import Testing
@testable import NihongoPro

struct JSONExtractionTests {
    @Test func slicesFromFirstToLastBrace() {
        let raw = "Sure! Here you go:\n{\"words\": [{\"text\": \"猫\"}], \"translation\": \"cat\"}\nHope that helps."
        #expect(TranslationService.extractJSON(from: raw) == "{\"words\": [{\"text\": \"猫\"}], \"translation\": \"cat\"}")
    }

    @Test func stripsCodeFences() {
        #expect(TranslationService.stripCodeFences(from: "```json\n{\"x\":1}\n```") == "{\"x\":1}")
        #expect(TranslationService.stripCodeFences(from: "```markdown\n## Vocabulary\n```") == "## Vocabulary")
        #expect(TranslationService.stripCodeFences(from: "```\nplain\n```") == "plain")
        #expect(TranslationService.stripCodeFences(from: "  no fences  ") == "no fences")
    }

    @Test func fencedJSONWithProseAroundItStillExtracts() {
        let raw = "Here:\n```json\n{\"a\": {\"b\": 1}}\n```\nDone."
        #expect(TranslationService.extractJSON(from: raw) == "{\"a\": {\"b\": 1}}")
    }

    @Test func textWithoutBracesIsReturnedTrimmed() {
        #expect(TranslationService.extractJSON(from: "  nothing here  ") == "nothing here")
    }

    @Test func sanitizeStripsEveryQuoteVariantAndBackslashes() {
        let input = "He said “hi” and ‘yo’ and \"q\" and 'a' «b» 〝c〟 ″d′ C:\\path"
        let out = TranslationService.sanitizeForJSON(input)
        for quote in ["\"", "'", "“", "”", "‘", "’", "«", "»", "〝", "〟", "″", "′", "\\"] {
            #expect(!out.contains(quote), "still contains \(quote)")
        }
        #expect(out.contains("C:／path"))
        #expect(out.contains("He said hi and yo"))
    }
}

struct BreakdownMarkdownTests {
    @Test func parsesHeadingsBulletsAndParagraphs() {
        let markdown = """
        ## Vocabulary

        - 猫 — cat
        * 窓 — window

        A paragraph that
        spans two lines.

        ### Notes
        #not a heading
        """
        #expect(parseBlocks(from: markdown) == [
            .heading(level: 2, text: "Vocabulary"),
            .bullet(text: "猫 — cat"),
            .bullet(text: "窓 — window"),
            .paragraph(text: "A paragraph that spans two lines."),
            .heading(level: 3, text: "Notes"),
            .paragraph(text: "#not a heading"),
        ])
    }

    @Test func headingLevelIsCappedAtSix() {
        #expect(parseBlocks(from: "###### six") == [.heading(level: 6, text: "six")])
        #expect(parseBlocks(from: "####### seven") == [.paragraph(text: "####### seven")])
    }

    @Test func blankInputYieldsNoBlocks() {
        #expect(parseBlocks(from: "\n\n  \n").isEmpty)
    }
}

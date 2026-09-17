import CoreGraphics
import SwiftUI
import Testing
@testable import NihongoPro

struct SVGPathParserTests {
    @Test func parsesMoveAndCubic() throws {
        // Stroke 1 of 窓, straight from KanjiVG.
        let parsed = try #require(SVGPathParser.parse(
            "M52.76,10.25c0.99,0.99,1.58,2.25,1.58,3.7c0,3.05-0.09,4.49-0.09,7.27"))
        #expect(abs(parsed.start.x - 52.76) < 0.001)
        #expect(abs(parsed.start.y - 10.25) < 0.001)
        let box = parsed.path.boundingRect
        #expect(!box.isEmpty)
        #expect(abs(box.minY - 10.25) < 0.001)
        #expect(box.maxY > 20)
    }

    @Test func relativeCommandsAccumulate() throws {
        let parsed = try #require(SVGPathParser.parse("m10,10 l5,0 5,0 L30,10"))
        let end = try #require(parsed.path.currentPoint)
        #expect(end == CGPoint(x: 30, y: 10))
        #expect(parsed.start == CGPoint(x: 10, y: 10))
    }

    @Test func tokenizeSplitsPackedNumbers() {
        let tokens = SVGPathParser.tokenize("M10-20c1.5.5,2e1 3")
        #expect(tokens == [
            .command("M"), .number(10), .number(-20),
            .command("c"), .number(1.5), .number(0.5), .number(20), .number(3),
        ])
    }

    @Test func rejectsGarbage() {
        #expect(SVGPathParser.parse("") == nil)
        #expect(SVGPathParser.parse("10 20") == nil)       // no leading command
        #expect(SVGPathParser.parse("hello") == nil)       // unknown command
        #expect(SVGPathParser.parse("M1,2 Q3,4 5,6") == nil) // quadratics unsupported
    }

    @Test func extractStrokesIgnoresTheStrokeNumbersSection() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 109 109">
        <g id="kvg:StrokePaths_07a93" style="fill:none;stroke:#000000;">
        <path id="kvg:07a93-s1" kvg:type="㇔" d="M10,10 L20,20"/>
        <path id="kvg:07a93-s2" d="M30,30 L40,40"/>
        </g>
        <g id="kvg:StrokeNumbers_07a93"><path d="M0,0 L1,1"/><text transform="matrix(1 0 0 1 50 12)">1</text></g>
        </svg>
        """
        let strokes = KanjiStrokeView.extractStrokes(from: svg)
        #expect(strokes.count == 2)
        #expect(strokes.map(\.start) == [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)])
    }
}

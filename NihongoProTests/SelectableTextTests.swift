import Testing
import SwiftUI
import UIKit
@testable import NihongoPro

// iOS 27 draws nothing for a selectable `Text` that carries a foreground style
// when it sits on a material background — the app's `cardChrome` cards, which is
// where every affected line lives (see `View.selectableLabel(_:)` in Theme.swift).
// These tests pin the workaround from three sides: the rendering tests draw the
// app's selectable-text chains inside a card through a real window and check
// that ink lands, the definition card itself is rendered with and without a
// reading and must differ, and the source tests fail if a foreground style is
// ever put back on selectable text.
//
// Run them on an iOS 27 simulator as well as iOS 26 — only iOS 27 exhibits the
// bug, and `styledSelectableTextIsBlankOnIOS27` is the canary that says when the
// workaround can be retired.

// MARK: - Rendering

/// What a rendered region looks like: how many pixels are darker than the white
/// background, and the darkest of them (0 = black, 255 = white).
private struct Ink {
    var pixels = 0
    var darkest = 255
}

private let sampleWidth: CGFloat = 260
private let rowHeight: CGFloat = 80

/// Draws `view` through a real window — the same on-screen path the app's sheets
/// take — and returns the bitmap. `ImageRenderer` is deliberately not used: the
/// iOS 27 bug lives in the on-screen selectable-text path, which only
/// `drawHierarchy(afterScreenUpdates:)` captures.
@MainActor
private func render<V: View>(_ view: V, rows: Int) -> UIImage {
    let size = CGSize(width: sampleWidth, height: rowHeight * CGFloat(rows))
    let host = UIHostingController(
        rootView: view
            .font(.system(size: 32))
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .ignoresSafeArea()
    )
    // The status-bar inset would otherwise push the rows down and let row 0's
    // glyphs bleed into the row being measured.
    host.safeAreaRegions = []
    let window: UIWindow
    if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
        window = UIWindow(windowScene: scene)
    } else {
        window = UIWindow()
    }
    window.frame = CGRect(origin: .zero, size: size)
    window.overrideUserInterfaceStyle = .light
    window.rootViewController = host
    window.isHidden = false
    host.view.layoutIfNeeded()
    // Let SwiftUI commit its frames, then capture twice and keep the settled
    // one: selectable text swaps in its backing view after the first commit.
    func capture() -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    _ = capture()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let image = capture()
    window.isHidden = true
    window.rootViewController = nil
    return image
}

/// Ink in one `rowHeight`-tall row of a rendered image (row 0 at the top).
private func ink(_ image: UIImage, row: Int) -> Ink {
    guard let cg = image.cgImage else { return Ink() }
    let width = cg.width, height = cg.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return Ink() }
    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    let scale = CGFloat(height) / (CGFloat(image.size.height))
    let rowStart = Int(CGFloat(row) * rowHeight * scale)
    let rowEnd = min(height, Int(CGFloat(row + 1) * rowHeight * scale))
    var result = Ink()
    for y in rowStart..<rowEnd {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let brightness = (Int(rgba[i]) + Int(rgba[i + 1]) + Int(rgba[i + 2])) / 3
            if brightness < 235 {
                result.pixels += 1
                result.darkest = min(result.darkest, brightness)
            }
        }
    }
    return result
}

/// Every affected line sits on a `cardChrome` card, and the material background is
/// what triggers the bug — the same styled text draws fine on a plain background —
/// so the samples are rendered inside one.
@MainActor
private func inkInCard<V: View>(_ view: V) -> Ink {
    let image = render(
        VStack(spacing: 0) { view.frame(height: rowHeight) }
            .cardChrome(padding: 0)
            .frame(height: rowHeight),
        rows: 1
    )
    return ink(image, row: 0)
}

private func totalInk(_ image: UIImage, rows: Int) -> Int {
    (0..<rows).reduce(0) { $0 + ink(image, row: $1).pixels }
}

// Serialized: `render` pumps the main run loop, which would otherwise let the
// next main-actor test start mid-render and race the capture.
@Suite(.serialized)
@MainActor
struct SelectableTextRenderingTests {
    @Test func plainSelectableTextDrawsInkOnACard() {
        let sample = inkInCard(Text("ちょうしょく").textSelection(.enabled))
        #expect(sample.pixels > 0)
        #expect(sample.darkest < 40, "primary text should reach full black")
    }

    /// The exact chains the reading line, the translations, the kanji example
    /// reading and the mnemonic use. Before the fix these were
    /// `.foregroundStyle(.secondary)` + `.textSelection(.enabled)`, which iOS 27
    /// draws as nothing at all on a card.
    @Test func secondarySelectableLabelDrawsDimmedInkOnACard() {
        let sample = inkInCard(Text("ちょうしょく").selectableLabel(.secondary))
        #expect(sample.pixels > 0)
        #expect((70...140).contains(sample.darkest), "expected ~60 % black, got \(sample.darkest)")
    }

    @Test func tertiarySelectableLabelDrawsDimmedInkOnACard() {
        let sample = inkInCard(Text("literal").selectableLabel(.tertiary))
        #expect(sample.pixels > 0)
        #expect((150...215).contains(sample.darkest), "expected ~30 % black, got \(sample.darkest)")
    }

    /// The canary. On iOS 26 this renders like any other text; on iOS 27 it is the
    /// bug itself and is recorded as a known issue. When it stops failing there,
    /// the OS has fixed it and `selectableLabel` can go back to `.foregroundStyle`.
    @Test func styledSelectableTextIsBlankOnACardOnIOS27() {
        let onIOS27 = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        // Control: the harness draws plain selectable text on the same card right
        // now, so a blank below is the bug, not the harness.
        #expect(inkInCard(Text("ちょうしょく").textSelection(.enabled)).pixels > 0)
        withKnownIssue("iOS 27 draws nothing for selectable text that carries a foreground style on a material card — the reason `selectableLabel` exists") {
            #expect(inkInCard(Text("ちょうしょく").foregroundStyle(.secondary).textSelection(.enabled)).pixels > 0)
        } when: {
            onIOS27
        }
    }

    /// The bug as Terry saw it: the definition card with a reading must draw more
    /// than the same card without one. Before the fix the two were identical on
    /// iOS 27 — the reading's row was laid out but empty.
    @Test func definitionCardDrawsTheReading() {
        let speech = SpeechService()
        func card(reading: String) -> UIImage {
            let word = Word(
                text: "朝食", reading: reading,
                furigana: [FuriganaSegment(text: "朝食", reading: reading == "朝食" ? nil : reading)],
                definition: "breakfast"
            )
            return render(WordDefinitionView(word: word, translator: TranslationService(), speechService: speech), rows: 8)
        }
        let withReading = totalInk(card(reading: "ちょうしょく"), rows: 8)
        let withoutReading = totalInk(card(reading: "朝食"), rows: 8)
        #expect(withReading - withoutReading > 500,
                "the reading line adds no ink (with \(withReading), without \(withoutReading))")
    }
}

// MARK: - Source guard

/// Fails if any selectable text in the app carries a foreground style again.
/// Reads the checkout the test file lives in — the simulator sees the Mac's file
/// system — so it runs anywhere the unit tests run, on any OS.
struct SelectableTextSourceTests {
    private static let forbidden = [".foregroundStyle(", ".foregroundColor("]
    private static let selectable = [".textSelection(.enabled)", ".selectableLabel("]

    /// The modifier chain a line belongs to: the view line it hangs off plus every
    /// following line that starts with `.` — the way modifiers are written in this
    /// codebase, one per line.
    nonisolated static func modifierChain(around index: Int, in lines: [String]) -> [String] {
        func isModifier(_ line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix(".")
        }
        var start = index
        while start > 0, isModifier(lines[start - 1]) { start -= 1 }
        if start > 0 { start -= 1 } // the view the chain hangs off
        var end = index
        while end + 1 < lines.count, isModifier(lines[end + 1]) { end += 1 }
        return Array(lines[start...end])
    }

    private static func appSources() throws -> [(name: String, lines: [String])] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NihongoPro")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                (url.lastPathComponent, try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n"))
            }
    }

    @Test func chainDetectionSpansStylesBeforeAndAfterSelection() {
        let lines = """
        VStack {
            Text(x)
                .font(.title2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize()
        }
        """.components(separatedBy: "\n")
        let chain = Self.modifierChain(around: 4, in: lines)
        #expect(chain.count == 5)
        #expect(chain.first?.contains("Text(x)") == true)
        #expect(chain.last?.contains(".fixedSize()") == true)
    }

    @Test func selectableTextNeverCarriesAForegroundStyle() throws {
        var sites = 0
        for (name, lines) in try Self.appSources() {
            for (index, line) in lines.enumerated() where Self.selectable.contains(where: line.contains) {
                sites += 1
                let chain = Self.modifierChain(around: index, in: lines)
                let offending = chain.filter { l in Self.forbidden.contains(where: l.contains) }
                #expect(offending.isEmpty,
                        "\(name):\(index + 1) styles selectable text — iOS 27 draws it blank; use selectableLabel(_:) instead")
            }
        }
        // If the sources can't be found the loop above proves nothing.
        #expect(sites >= 10, "expected to scan the app's selectable-text sites, found \(sites)")
    }

    /// `BreakdownView` is made selectable as a whole from `ContentView`, so an
    /// inherited style would blank every `Text` inside it.
    @Test func breakdownRendererCarriesNoForegroundStyle() throws {
        let breakdown = try #require(Self.appSources().first { $0.name == "BreakdownView.swift" })
        let styled = breakdown.lines.enumerated().filter { _, l in Self.forbidden.contains(where: l.contains) }
        #expect(styled.isEmpty, "BreakdownView.swift lines \(styled.map { $0.offset + 1 }) — use opacity, the view is selectable as a whole")
    }
}


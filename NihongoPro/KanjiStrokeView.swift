import SwiftUI

// Native KanjiVG stroke renderer adapted from Terry's sibling kanji-concept project.
// Parses the raw KanjiVG SVG into [Stroke] (path + start point), then animates each
// stroke trim-by-trim on a 109-unit canvas with a grid background and numbered badges.

struct KanjiStrokeView: View {
    let svg: String

    @StateObject private var animator = StrokeAnimator()
    @State private var strokes: [Stroke] = []
    @State private var parseError: Bool = false

    var body: some View {
        Group {
            if parseError {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Couldn't parse stroke data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if strokes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StrokeCanvas(strokes: strokes, animator: animator)
            }
        }
        .onAppear {
            let parsed = Self.extractStrokes(from: svg)
            if parsed.isEmpty {
                parseError = true
            } else {
                strokes = parsed
                animator.play(strokes: parsed)
            }
        }
    }

    static func extractStrokes(from svg: String) -> [Stroke] {
        let strokePathsAnchor = "kvg:StrokePaths"
        let strokeNumbersAnchor = "kvg:StrokeNumbers"

        let lowerBound: String.Index
        if let r = svg.range(of: strokePathsAnchor) {
            lowerBound = r.lowerBound
        } else {
            lowerBound = svg.startIndex
        }
        let upperBound = svg.range(of: strokeNumbersAnchor, range: lowerBound..<svg.endIndex)?.lowerBound ?? svg.endIndex
        let section = svg[lowerBound..<upperBound]

        var strokes: [Stroke] = []
        let pattern = /<path[^>]*\bd="([^"]+)"/
        for match in section.matches(of: pattern) {
            let d = String(match.output.1)
            if let parsed = SVGPathParser.parse(d) {
                strokes.append(Stroke(path: parsed.path, start: parsed.start))
            }
        }
        return strokes
    }
}

struct Stroke {
    let path: Path
    let start: CGPoint
}

@MainActor
final class StrokeAnimator: ObservableObject {
    @Published private(set) var progress: [CGFloat] = []
    @Published private(set) var currentStrokeIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false

    private var strokes: [Stroke] = []
    private var task: Task<Void, Never>?

    func play(strokes: [Stroke]) {
        cancel()
        self.strokes = strokes
        progress = Array(repeating: 0, count: strokes.count)
        currentStrokeIndex = 0
        startTask()
    }

    func replay() {
        guard !strokes.isEmpty else { return }
        cancel()
        progress = Array(repeating: 0, count: strokes.count)
        currentStrokeIndex = 0
        startTask()
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPlaying = false
    }

    private func startTask() {
        isPlaying = true
        task = Task { [weak self] in
            guard let self else { return }
            let count = self.strokes.count
            for index in 0..<count {
                if Task.isCancelled { return }
                self.currentStrokeIndex = index
                let duration = self.duration(for: self.strokes[index].path)
                withAnimation(.linear(duration: duration)) {
                    self.progress[index] = 1.0
                }
                let nanos = UInt64((duration + 0.15) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
            }
            self.isPlaying = false
        }
    }

    private func duration(for path: Path) -> Double {
        let r = path.boundingRect
        let length = sqrt(Double(r.width * r.width + r.height * r.height))
        return min(max(0.3 + length * 0.008, 0.3), 1.2)
    }
}

private struct StrokeShape: Shape {
    let basePath: Path
    var progress: CGFloat
    var canvasUnit: CGFloat = 109

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        let scale = min(rect.width, rect.height) / canvasUnit
        let scaled = basePath.applying(CGAffineTransform(scaleX: scale, y: scale))
        if progress >= 1 { return scaled }
        return scaled.trimmedPath(from: 0, to: progress)
    }
}

private struct StrokeCanvas: View {
    let strokes: [Stroke]
    @ObservedObject var animator: StrokeAnimator

    private static let canvasUnit: CGFloat = 109
    private static let strokeStyle = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                grid(side: side)
                strokeLayer(side: side)
                badgeLayer(side: side)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func grid(side: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            Path { p in
                p.move(to: CGPoint(x: side / 2, y: 0))
                p.addLine(to: CGPoint(x: side / 2, y: side))
                p.move(to: CGPoint(x: 0, y: side / 2))
                p.addLine(to: CGPoint(x: side, y: side / 2))
            }
            .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func strokeLayer(side: CGFloat) -> some View {
        ForEach(Array(strokes.enumerated()), id: \.offset) { index, stroke in
            let progress = animator.progress.indices.contains(index) ? animator.progress[index] : 0
            if index <= animator.currentStrokeIndex {
                StrokeShape(basePath: stroke.path, progress: progress)
                    .stroke(color(forIndex: index), style: Self.strokeStyle)
                    .frame(width: side, height: side)
            }
        }
    }

    private func color(forIndex index: Int) -> Color {
        index < animator.currentStrokeIndex
            ? Color.primary.opacity(0.25)
            : Color.primary
    }

    @ViewBuilder
    private func badgeLayer(side: CGFloat) -> some View {
        let scale = side / Self.canvasUnit
        ForEach(Array(strokes.enumerated()), id: \.offset) { index, stroke in
            if index <= animator.currentStrokeIndex {
                badge(number: index + 1)
                    .position(x: stroke.start.x * scale, y: stroke.start.y * scale)
            }
        }
    }

    @ViewBuilder
    private func badge(number: Int) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.9))
                .overlay(
                    Circle().stroke(Color(.systemBackground), lineWidth: 1.5)
                )
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
    }
}

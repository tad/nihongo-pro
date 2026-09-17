import CoreGraphics
import SwiftUI

// Adapted from the sibling kanji-concept project (Terry's own code).
// Converts an SVG path "d" string into a SwiftUI `Path`.
// Supports the subset of commands KanjiVG actually uses:
// M m L l C c S s Z z. No arcs, no quadratics — KanjiVG doesn't emit them.
nonisolated enum SVGPathParser {

    /// Parse a path d-string. Returns the constructed `Path` plus the first
    /// point of the first subpath (used to position stroke-number badges).
    /// Returns `nil` if the string contains no valid commands.
    static func parse(_ d: String) -> (path: Path, start: CGPoint)? {
        let tokens = tokenize(d)
        guard !tokens.isEmpty else { return nil }

        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint? = nil
        var firstPoint: CGPoint? = nil

        var i = 0
        while i < tokens.count {
            guard case .command(let raw) = tokens[i] else {
                return nil
            }
            i += 1

            let lower = Character(raw.lowercased())
            let absolute = raw.isUppercase

            switch lower {
            case "m":
                guard let first = readPoint(tokens, &i, origin: absolute ? nil : current) else { return nil }
                path.move(to: first)
                current = first
                subpathStart = first
                lastControl = nil
                if firstPoint == nil { firstPoint = first }
                while let next = readPoint(tokens, &i, origin: absolute ? nil : current) {
                    path.addLine(to: next)
                    current = next
                    lastControl = nil
                }

            case "l":
                var read = false
                while let p = readPoint(tokens, &i, origin: absolute ? nil : current) {
                    path.addLine(to: p)
                    current = p
                    lastControl = nil
                    read = true
                }
                if !read { return nil }

            case "c":
                var read = false
                while peekPoint(tokens, i) {
                    let origin: CGPoint? = absolute ? nil : current
                    guard
                        let c1 = readPoint(tokens, &i, origin: origin),
                        let c2 = readPoint(tokens, &i, origin: origin),
                        let p  = readPoint(tokens, &i, origin: origin)
                    else { break }
                    path.addCurve(to: p, control1: c1, control2: c2)
                    lastControl = c2
                    current = p
                    read = true
                }
                if !read { return nil }

            case "s":
                var read = false
                while peekPoint(tokens, i) {
                    let origin: CGPoint? = absolute ? nil : current
                    guard
                        let c2 = readPoint(tokens, &i, origin: origin),
                        let p  = readPoint(tokens, &i, origin: origin)
                    else { break }
                    let c1: CGPoint
                    if let lc = lastControl {
                        c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                    } else {
                        c1 = current
                    }
                    path.addCurve(to: p, control1: c1, control2: c2)
                    lastControl = c2
                    current = p
                    read = true
                }
                if !read { return nil }

            case "z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil

            default:
                return nil
            }
        }

        guard let start = firstPoint else { return nil }
        return (path, start)
    }

    private static func peekPoint(_ tokens: [Token], _ i: Int) -> Bool {
        guard i + 1 < tokens.count else { return false }
        if case .number = tokens[i], case .number = tokens[i + 1] { return true }
        return false
    }

    private static func readPoint(_ tokens: [Token], _ i: inout Int, origin: CGPoint?) -> CGPoint? {
        guard i + 1 < tokens.count else { return nil }
        guard case .number(let x) = tokens[i] else { return nil }
        guard case .number(let y) = tokens[i + 1] else { return nil }
        i += 2
        if let o = origin {
            return CGPoint(x: o.x + x, y: o.y + y)
        }
        return CGPoint(x: x, y: y)
    }

    enum Token: Equatable {
        case command(Character)
        case number(CGFloat)
    }

    static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "," {
                i += 1
                continue
            }
            if c.isLetter {
                tokens.append(.command(c))
                i += 1
                continue
            }
            if c == "+" || c == "-" || c == "." || c.isASCIIDigit {
                var j = i
                if chars[j] == "+" || chars[j] == "-" { j += 1 }
                var sawDot = false
                var sawDigit = false
                while j < chars.count {
                    let ch = chars[j]
                    if ch.isASCIIDigit {
                        sawDigit = true
                        j += 1
                    } else if ch == "." && !sawDot {
                        sawDot = true
                        j += 1
                    } else if (ch == "e" || ch == "E") && sawDigit {
                        j += 1
                        if j < chars.count && (chars[j] == "+" || chars[j] == "-") { j += 1 }
                        while j < chars.count && chars[j].isASCIIDigit { j += 1 }
                        break
                    } else {
                        break
                    }
                }
                let slice = String(chars[i..<j])
                if let v = Double(slice) {
                    tokens.append(.number(CGFloat(v)))
                }
                i = j
                continue
            }
            i += 1
        }
        return tokens
    }
}

nonisolated private extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}

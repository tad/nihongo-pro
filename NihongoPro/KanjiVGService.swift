import Foundation

enum KanjiVGError: LocalizedError {
    case notKanji
    case notFound
    case network(Error)
    case invalidResponse(status: Int)

    var errorDescription: String? {
        switch self {
        case .notKanji:
            return "Not a kanji character."
        case .notFound:
            return "Stroke order not available for this character."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let status):
            return "Couldn't load stroke data (HTTP \(status))."
        }
    }
}

enum KanjiVGService {
    static func loadSVG(for kanji: Character) async throws -> String {
        guard let codepoint = kanji.kanjiVGCodepoint else {
            throw KanjiVGError.notKanji
        }

        if let cached = readCached(codepoint: codepoint) {
            return cached
        }

        let url = URL(string: "https://raw.githubusercontent.com/KanjiVG/kanjivg/master/kanji/\(codepoint).svg")!

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw KanjiVGError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw KanjiVGError.invalidResponse(status: -1)
        }
        if http.statusCode == 404 {
            throw KanjiVGError.notFound
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KanjiVGError.invalidResponse(status: http.statusCode)
        }
        guard let svg = String(data: data, encoding: .utf8) else {
            throw KanjiVGError.invalidResponse(status: http.statusCode)
        }

        writeCached(codepoint: codepoint, svg: svg)
        return svg
    }

    private static func readCached(codepoint: String) -> String? {
        let url = cacheURL(for: codepoint)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func writeCached(codepoint: String, svg: String) {
        let url = cacheURL(for: codepoint)
        try? svg.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func cacheURL(for codepoint: String) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cachesDir.appendingPathComponent("kanji_\(codepoint).svg")
    }
}

extension Character {
    var isKanji: Bool {
        guard let scalar = self.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value)
    }

    var kanjiVGCodepoint: String? {
        guard isKanji, let scalar = self.unicodeScalars.first else { return nil }
        return String(format: "%05x", scalar.value)
    }
}

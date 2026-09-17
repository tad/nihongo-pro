import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Pronunciation practice
//
// The user reads the parsed sentence aloud; iOS 26's on-device `SpeechAnalyzer` +
// `SpeechTranscriber` (ja-JP) transcribe it; `PronunciationScorer` compares the
// transcript to the sentence word by word and `FuriganaText` colors each word
// matched / partial / missed. Nothing is persisted and nothing leaves the device.

/// Drives one practice attempt: permissions → speech model assets → microphone
/// capture → live transcript → score. Owned by `ContentView` as `@State`.
@MainActor
@Observable
final class PronunciationService {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        /// The ja-JP speech model is being reserved/downloaded (first use only).
        case preparingAssets
        case listening
        case evaluating
        case result(PronunciationScorer.Result)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Volatile + finalized transcript so far, for the live caption while listening.
    private(set) var liveTranscript: String = ""

    var isListening: Bool { phase == .listening }
    var isBusy: Bool {
        switch phase {
        case .requestingPermission, .preparingAssets, .evaluating: return true
        default: return false
        }
    }
    /// Per-word outcomes of the last attempt (word index → outcome), or nil.
    var outcomes: [Int: PronunciationScorer.Outcome]? {
        if case .result(let result) = phase { return result.outcomes }
        return nil
    }

    @ObservationIgnored private var expected: [Word] = []
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var finalizedText: String = ""

    /// Begins listening for a reading of `words`. Any earlier attempt is discarded.
    func start(expected words: [Word]) async {
        cancel()
        expected = words
        finalizedText = ""
        liveTranscript = ""

        phase = .requestingPermission
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed("Microphone access is off. Allow it in Settings → Nihongo Pro to practise pronunciation.")
            return
        }

        phase = .preparingAssets
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja_JP")) else {
            phase = .failed("Japanese speech recognition isn't available on this device.")
            return
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        do {
            if await AssetInventory.status(forModules: [transcriber]) != .installed {
                _ = try? await AssetInventory.reserve(locale: locale)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw PracticeError.noAudioFormat
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation
            try startCapture(into: continuation, format: format)
            self.analyzer = analyzer
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.handle(result)
                    }
                } catch {
                    self?.fail(error)
                }
            }
            try await analyzer.start(inputSequence: stream)
            phase = .listening
        } catch {
            stopCapture()
            phase = .failed(error.localizedDescription)
        }
    }

    /// Stops listening, finalizes the transcript and scores it.
    func stop() async {
        guard phase == .listening else { cancel(); return }
        phase = .evaluating
        stopCapture()
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        // Finalized results are delivered on their own task; give them a beat to land.
        try? await Task.sleep(for: .milliseconds(200))
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        let transcript = finalizedText.isEmpty ? liveTranscript : finalizedText
        phase = .result(PronunciationScorer.score(expected: expected, transcript: transcript))
    }

    /// Discards the attempt (and any shown result) and releases the microphone.
    func cancel() {
        resultsTask?.cancel()
        resultsTask = nil
        stopCapture()
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        liveTranscript = ""
        finalizedText = ""
        phase = .idle
    }

    // MARK: Transcript

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        if result.isFinal {
            finalizedText += text
            liveTranscript = finalizedText
        } else {
            liveTranscript = finalizedText + text
        }
    }

    private func fail(_ error: Error) {
        guard phase == .listening || phase == .preparingAssets else { return }
        stopCapture()
        phase = .failed(error.localizedDescription)
    }

    // MARK: Microphone capture

    private func startCapture(into continuation: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // The microphone rarely delivers the analyzer's format (typically 48 kHz vs
        // 16 kHz); feeding unconverted buffers yields silence rather than an error.
        let converter = TapConverter(from: inputFormat, to: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func stopCapture() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        SpeechService.configurePlaybackSession()
    }

    private enum PracticeError: LocalizedError {
        case noAudioFormat
        var errorDescription: String? { "Couldn't set up audio for speech recognition." }
    }
}

/// Resamples microphone buffers to the analyzer's format. `@unchecked Sendable`
/// because the tap block is `@Sendable`, but the converter is only ever touched from
/// the single audio-tap thread — no other code holds it.
nonisolated private final class TapConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        self.outputFormat = outputFormat
        self.ratio = outputFormat.sampleRate / inputFormat.sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

// MARK: - Kana reading of arbitrary Japanese text

/// Turns kanji-mixed text into hiragana on-device, via the system tokenizer's
/// Latin transcription (`CFStringTokenizer` + `kCFStringTokenizerAttributeLatinTranscription`)
/// transformed back to kana. The transcriber has no kana output option, so this is how
/// its kanji-mixed transcript becomes comparable with the sentence's readings.
nonisolated enum KanaReading {
    /// Hiragana for `text`, or nil if the tokenizer produced no transcription at all.
    static func hiragana(of text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let cfText = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            CFRange(location: 0, length: CFStringGetLength(cfText)),
            kCFStringTokenizerUnitWordBoundary | kCFStringTokenizerAttributeLatinTranscription,
            Locale(identifier: "ja") as CFLocale
        )
        var output = ""
        var transcribedAny = false
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
               !latin.isEmpty,
               let kana = latin.applyingTransform(.latinToHiragana, reverse: false) {
                output += kana
                transcribedAny = true
            } else {
                output += token
            }
        }
        return transcribedAny ? output : nil
    }
}

// MARK: - Scoring

/// Pure comparison of what was said with what the sentence says.
nonisolated enum PronunciationScorer {
    enum Outcome: Sendable, Equatable {
        case matched, partial, missed
    }

    struct Result: Sendable, Equatable {
        /// Word index (into the `[Word]` that was read) → outcome. Punctuation words are absent.
        var outcomes: [Int: Outcome]
        var transcript: String
        var matched: Int
        var total: Int
    }

    /// Reduces kana to the sounds that matter for a match: katakana → hiragana,
    /// the long-vowel mark and small っ dropped (recognizers and speakers vary on
    /// both), は/を/へ collapsed onto the sounds they're pronounced with as particles
    /// (わ/お/え — the transcriber writes what it hears), ぢ/づ onto じ/ず, and
    /// everything that isn't a kana letter (punctuation, spaces, stray kanji) removed.
    /// Applied to both sides, so a lossy mapping can never create a mismatch.
    static func normalize(_ text: String) -> String {
        // Drop ー before the kana transform: the transform would otherwise expand it
        // into the preceding vowel (コーヒー → こおひい), which a hiragana reading
        // (こーひー) never contains, so the two sides would disagree.
        let stripped = text.replacingOccurrences(of: "\u{30FC}", with: "")
        let hiragana = stripped.applyingTransform(.hiraganaToKatakana, reverse: true) ?? stripped
        var out = ""
        for scalar in hiragana.unicodeScalars {
            switch scalar {
            case "\u{30FC}", "\u{3063}": continue            // ー, っ
            case "\u{306F}": out.append("\u{308F}")           // は → わ
            case "\u{3092}": out.append("\u{304A}")           // を → お
            case "\u{3078}": out.append("\u{3048}")           // へ → え
            case "\u{3062}": out.append("\u{3058}")           // ぢ → じ
            case "\u{3065}": out.append("\u{305A}")           // づ → ず
            case "\u{3041}"..."\u{3096}": out.unicodeScalars.append(scalar)
            default: continue
            }
        }
        return out
    }

    /// Word-by-word verdict. Expected kana per word is the pass-1 `reading`; the
    /// transcript is converted to kana with `KanaReading` (falling back to the raw
    /// text when that fails). Characters are aligned with a longest-common-subsequence
    /// so a dropped or extra syllable shifts nothing; a word with ≥ 80 % of its kana
    /// aligned is `matched`, any is `partial`, none is `missed`.
    static func score(expected words: [Word], transcript: String) -> Result {
        var spans: [(index: Int, kana: [Character])] = []
        for (index, word) in words.enumerated() where !JapaneseWordFilter.isPurePunctuation(word.text) {
            let kana = Array(normalize(word.reading.isEmpty ? word.text : word.reading))
            if !kana.isEmpty { spans.append((index, kana)) }
        }
        let heard = Array(normalize(KanaReading.hiragana(of: transcript) ?? transcript))
        let expectedKana = spans.flatMap(\.kana)
        let aligned = alignment(of: expectedKana, in: heard)

        var outcomes: [Int: Outcome] = [:]
        var matchedCount = 0
        var cursor = 0
        for span in spans {
            let hits = aligned[cursor..<(cursor + span.kana.count)].filter { $0 }.count
            cursor += span.kana.count
            let outcome: Outcome
            if Double(hits) >= 0.8 * Double(span.kana.count) {
                outcome = .matched
                matchedCount += 1
            } else if hits > 0 {
                outcome = .partial
            } else {
                outcome = .missed
            }
            outcomes[span.index] = outcome
        }
        return Result(outcomes: outcomes, transcript: transcript, matched: matchedCount, total: spans.count)
    }

    /// For each character of `a`, whether it takes part in one longest common
    /// subsequence with `b` (classic DP + backtrack; inputs are a sentence long).
    static func alignment(of a: [Character], in b: [Character]) -> [Bool] {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return Array(repeating: false, count: n) }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1])
            }
        }
        var used = Array(repeating: false, count: n)
        var i = n, j = m
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] && dp[i][j] == dp[i - 1][j - 1] + 1 {
                used[i - 1] = true
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return used
    }
}

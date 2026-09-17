import Foundation
import Testing
@testable import NihongoPro

struct JSONStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonstore-\(UUID().uuidString).json")
    }

    @Test func saveAndLoadRoundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let slice = DeviceFreqSlice(word: ["猫": 3], kanji: ["猫": 3])
        JSONStore.save(slice, to: url)
        let loaded = JSONStore.load(DeviceFreqSlice.self, from: url)
        #expect(loaded?.word == ["猫": 3])
        #expect(loaded?.kanji == ["猫": 3])
    }

    @Test func missingFileLoadsAsNil() {
        #expect(JSONStore.load(DeviceFreqSlice.self, from: tempURL()) == nil)
    }

    @Test func saveLaterWritesTheLatestValue() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        JSONStore.saveLater(DeviceFreqSlice(word: ["a": 1], kanji: [:]), to: url)
        JSONStore.saveLater(DeviceFreqSlice(word: ["a": 2], kanji: [:]), to: url)
        var loaded: DeviceFreqSlice?
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(20))
            loaded = JSONStore.load(DeviceFreqSlice.self, from: url)
            if loaded?.word["a"] == 2 { break }
        }
        #expect(loaded?.word == ["a": 2])
    }

    /// The bytes on disk and on CloudKit are a contract with older installs and the
    /// kanji-study app: default key names, dates as reference-interval numbers.
    @Test func encoderKeepsFoundationDefaults() throws {
        let entry = FamiliaritySliceEntry(level: "known", modifiedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let text = String(decoding: try JSONStore.encoder.encode(["猫": entry]), as: UTF8.self)
        #expect(text.contains("\"modifiedAt\":800000000"))
        #expect(text.contains("\"level\":\"known\""))
    }
}

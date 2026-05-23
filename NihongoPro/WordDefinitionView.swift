import SwiftUI

struct WordDefinitionView: View {
    let word: Word
    let translator: TranslationService
    @ObservedObject var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKanji: KanjiSelection?
    @State private var seenCount: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(seenCountLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    wordHeader

                                    if word.reading != word.text {
                                        Text(word.reading)
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }

                                Spacer()

                                Button {
                                    if speechService.isSpeaking {
                                        speechService.stop()
                                    } else {
                                        speechService.speak(word.text)
                                    }
                                } label: {
                                    Image(systemName: speechService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tint)
                                        .frame(width: 56, height: 56)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(speechService.isSpeaking ? "Stop word audio" : "Play word audio")
                            }

                            familiarityPicker
                        }
                        .cardChrome()

                        if let definition = word.definition {
                            Text(definition)
                                .font(.title3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Definition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedKanji) { selection in
                KanjiDetailView(kanji: selection.character, translator: translator)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                seenCount = await FrequencyTracker.shared.wordFrequency(for: word.text)
            }
        }
    }

    private var seenCountLabel: String {
        seenCount == 1 ? "Seen 1 time" : "Seen \(seenCount) times"
    }

    private var familiarityPicker: some View {
        WordFamiliarityPicker(word: word.text)
    }

    private var wordHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.text.enumerated()), id: \.offset) { _, char in
                if char.isKanji {
                    Button {
                        selectedKanji = KanjiSelection(character: char)
                    } label: {
                        Text(String(char))
                            .font(.system(size: 64, weight: .regular, design: .serif))
                            .foregroundStyle(.tint)
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(String(char))
                        .font(.system(size: 64, weight: .regular, design: .serif))
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct KanjiSelection: Identifiable {
    let id = UUID()
    let character: Character
}

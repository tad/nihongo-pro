import SwiftUI

struct WordDefinitionView: View {
    let word: Word
    let translator: TranslationService
    let speechService: SpeechService
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
                                    if seenCount > 0 {
                                        Text(seenCountLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

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
                                        // Same selection rule as the sentence: speak the kanji
                                        // surface form (which the neural voices read correctly),
                                        // and only drop to the kana reading for tts_kana-flagged
                                        // rare compounds. Feeding bare kana made the engine
                                        // truncate a terminal っ/つ (温帯低気圧 → "…あ").
                                        speechService.speak([word].sentenceSpeechText())
                                    }
                                } label: {
                                    Image(systemName: speechService.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tint)
                                        .contentTransition(.symbolEffect(.replace))
                                        .symbolEffect(.pulse, isActive: speechService.isSpeaking)
                                        .frame(width: 56, height: 56)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(speechService.isSpeaking ? "Stop word audio" : "Play word audio")
                            }

                            familiarityPicker

                            HStack(spacing: 12) {
                                NihongoLookupLink(kind: .word, query: word.text)
                                JishoLookupLink(kind: .word, query: word.text)
                                Spacer()
                            }
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
                seenCount = FrequencyTracker.shared.wordFrequency(for: word.text)
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
        let store = FamiliarityStore.shared
        return HStack(spacing: 0) {
            ForEach(Array(word.text.enumerated()), id: \.offset) { _, char in
                if char.isKanji {
                    Button {
                        selectedKanji = KanjiSelection(character: char)
                    } label: {
                        Text(String(char))
                            .font(.system(size: 64, weight: .regular, design: .serif))
                            .foregroundStyle(kanjiTint(for: char, store: store))
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

    /// Same mapping as the sentence view's knowledge markup: Known → green,
    /// Familiar → amber, Unknown → the accent tint (the tappable-kanji cue).
    private func kanjiTint(for char: Character, store: FamiliarityStore) -> AnyShapeStyle {
        if let color = store.kanjiLevel(for: char).markupColor {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(.tint)
    }
}

private struct KanjiSelection: Identifiable {
    let id = UUID()
    let character: Character
}

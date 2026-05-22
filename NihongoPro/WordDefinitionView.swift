import SwiftUI

struct WordDefinitionView: View {
    let word: Word
    @ObservedObject var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(word.text)
                                .font(.system(size: 64, weight: .regular, design: .serif))
                                .textSelection(.enabled)

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

                    if let definition = word.definition {
                        Divider()
                        Text(definition)
                            .font(.title3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Definition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

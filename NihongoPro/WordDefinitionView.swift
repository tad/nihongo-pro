import SwiftUI

struct WordDefinitionView: View {
    let word: Word
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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

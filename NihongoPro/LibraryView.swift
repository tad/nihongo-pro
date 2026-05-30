import SwiftUI

/// Browse bookmarked sentences. Tapping one hands it back to `ContentView` to reload
/// (with furigana + definitions intact); swipe to delete. Presented as a sheet.
struct LibraryView: View {
    var onSelect: (SavedSentence) -> Void

    @Environment(\.dismiss) private var dismiss
    private let store = SavedSentenceStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                if store.sentences.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.sentences) { sentence in
                            Button {
                                onSelect(sentence)
                                dismiss()
                            } label: {
                                row(sentence)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.remove(id: store.sentences[index].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Saved sentences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ sentence: SavedSentence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sentence.text)
                .font(.system(size: 24, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if !sentence.englishTranslation.isEmpty {
                Text(sentence.englishTranslation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(sentence.savedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.55))
            Text("No saved sentences")
                .font(.title3)
            Text("Tap the bookmark on a parsed sentence to keep it here for later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.top, 80)
    }
}

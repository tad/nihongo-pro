import SwiftUI

/// Pick the parts a mnemonic should be built from, then either have the model write
/// the story from exactly those or type one yourself. Both routes pin the result so
/// no later fetch — here, on another device, or in the kanji-study app — replaces it.
///
/// MIRRORED with the kanji-study app's `MnemonicEditorView`. The behaviour is the
/// same; the plumbing differs because `DefinitionCache` here is an actor rather than
/// an `@Observable` store, so this view owns the `KanjiInfo` it is editing and hands
/// the updated copy back through `onSave` instead of the caller re-reading a cache.
struct MnemonicEditorView: View {
    let kanji: Character
    let translator: TranslationService
    /// The freshly stored entry, so `KanjiDetailView` can update the card behind us.
    let onSave: (KanjiInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var info: KanjiInfo?
    /// Candidate parts, resolved once in `.task`. Generating rewrites
    /// `info.components`, so rebuilding these would shuffle the chips under the
    /// user's finger mid-session.
    @State private var candidates: [Candidate] = []
    /// Selected part keys, in candidate order.
    @State private var selected: [String] = []
    @State private var customText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    /// One pickable part. `key` is the raw KRADFILE character (or the component
    /// string the model supplied), stable across a regenerate; `label` is what the
    /// user sees and what the model is told to echo back.
    private struct Candidate: Identifiable, Equatable {
        let key: String
        let glyph: String
        let keyword: String?
        var id: String { key }
        var label: String { keyword.map { "\(glyph) \($0)" } ?? glyph }
    }

    private var selectedLabels: [String] {
        candidates.filter { selected.contains($0.key) }.map(\.label)
    }

    private var trimmedCustom: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveCustom: Bool {
        !trimmedCustom.isEmpty && trimmedCustom != info?.mnemonic
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        header
                        if !candidates.isEmpty { partsCard }
                        currentCard
                        customCard
                        attribution
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Mnemonic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text(String(kanji))
                .font(.system(size: 72, weight: .regular, design: .serif))
            if let meanings = info?.meanings, !meanings.isEmpty {
                Text(meanings.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var partsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parts")
                .font(.headline)
            Text("Choose the parts the story should be built from.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                ForEach(candidates) { candidate in
                    chip(candidate)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(padding: 18)
    }

    private func chip(_ candidate: Candidate) -> some View {
        let isOn = selected.contains(candidate.key)
        return Button {
            toggle(candidate)
        } label: {
            HStack(spacing: 6) {
                Text(candidate.glyph)
                    .font(.system(.title3, design: .serif))
                if let keyword = candidate.keyword {
                    // Scale rather than wrap: a two-word keyword hyphenated across
                    // lines ("twen-ty") is harder to read than slightly smaller text.
                    Text(keyword)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.accentColor : .primary)
    }

    private var currentCard: some View {
        VStack(spacing: 10) {
            Text(info?.mnemonic.flatMap { $0.isEmpty ? nil : $0 } ?? "No mnemonic yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            if info?.pinned == true {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Automatic lookups won't replace this mnemonic.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Writing a new mnemonic…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Button("Generate from selected parts") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardChrome(padding: 18)
    }

    private var customCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Write your own")
                .font(.headline)
            TextEditor(text: $customText)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            Button("Save mnemonic") { saveCustom() }
                .buttonStyle(.bordered)
                .disabled(!canSaveCustom)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(padding: 18)
    }

    /// Same inline-attribution pattern as the KanjiVG credit on the stroke-order
    /// section of `KanjiDetailView`.
    private var attribution: some View {
        Text("Component data: KRADFILE/KRADFILE2, © EDRDG (CC BY-SA)")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Actions

    /// KRADFILE parts first, then any part the model used that KRADFILE doesn't list,
    /// so the union covers both sources. Parts already in `components` start selected.
    private func load() async {
        guard candidates.isEmpty else { return }
        let cached = await DefinitionCache.shared.kanjiInfo(for: kanji)
        info = cached

        var result: [Candidate] = []
        var seenGlyphs: Set<String> = []
        for part in Krad.parts(for: String(kanji)) {
            let glyph = Krad.glyph(for: part)
            result.append(Candidate(key: part, glyph: glyph, keyword: KradKeywords.keywords[part]))
            seenGlyphs.insert(glyph)
        }

        let existing = cached?.components ?? []
        for component in existing {
            // The model's components are "尸 flag": the glyph, a space, the keyword.
            let glyph = String(component.prefix(while: { !$0.isWhitespace }))
            guard !glyph.isEmpty, !seenGlyphs.contains(glyph) else { continue }
            let keyword = component.dropFirst(glyph.count).trimmingCharacters(in: .whitespaces)
            result.append(Candidate(key: component, glyph: glyph,
                                    keyword: keyword.isEmpty ? nil : keyword))
            seenGlyphs.insert(glyph)
        }

        candidates = result
        let usedGlyphs = Set(existing.map { String($0.prefix(while: { !$0.isWhitespace })) })
        selected = result.filter { usedGlyphs.contains($0.glyph) }.map(\.key)
        customText = cached?.mnemonic ?? ""
    }

    private func toggle(_ candidate: Candidate) {
        if let index = selected.firstIndex(of: candidate.key) {
            selected.remove(at: index)
        } else {
            selected.append(candidate.key)
        }
    }

    /// Stays open on success so the user can keep iterating on the parts.
    private func generate() {
        errorMessage = nil
        isGenerating = true
        let labels = selectedLabels
        Task {
            do {
                let updated = try await translator.regenerateKanjiInfo(kanji: kanji, using: labels)
                info = updated
                customText = updated.mnemonic ?? customText
                onSave(updated)
            } catch {
                errorMessage = (error as? TranslationError)?.errorDescription ?? error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func saveCustom() {
        let text = trimmedCustom
        let components = selected.isEmpty ? nil : selectedLabels
        Task {
            if let updated = await DefinitionCache.shared.saveCustomMnemonic(
                text, components: components, for: kanji
            ) {
                onSave(updated)
            }
            dismiss()
        }
    }
}

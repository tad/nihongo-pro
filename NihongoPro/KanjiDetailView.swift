import SwiftUI

struct KanjiDetailView: View {
    let kanji: Character
    let translator: TranslationService

    @Environment(\.dismiss) private var dismiss

    @State private var info: KanjiInfo?
    @State private var infoError: String?
    @State private var isLoadingInfo: Bool = true

    @State private var svg: String?
    @State private var svgError: String?
    @State private var isLoadingSVG: Bool = true

    @State private var animationKey: Int = 0
    @State private var seenCount: Int = 0

    @State private var isRegenerating: Bool = false
    @State private var regenerateError: String?

    @State private var isEditingMnemonic: Bool = false
    /// Set when "New mnemonic" is tapped on a pinned entry — a reroll would discard
    /// the user's own words, so it waits for confirmation.
    @State private var confirmingReroll: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperBackground.ignoresSafeArea()

                ScrollView {
                    // The glyph is the hero — lead with it (mirroring how
                    // WordDefinitionView leads with the word), then meanings,
                    // then the rating/lookup controls, then stroke order.
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(spacing: 8) {
                            Text(String(kanji))
                                .font(.displayKanji)
                                .textSelection(.enabled)

                            if seenCount > 0 {
                                Text(seenCountLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        infoSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardChrome()

                        familiarityPicker

                        VStack(alignment: .leading, spacing: 12) {
                            NihongoLookupLink(kind: .kanji, query: String(kanji))
                            JishoLookupLink(kind: .kanji, query: String(kanji))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        strokeOrderSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Kanji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isEditingMnemonic) {
            MnemonicEditorView(kanji: kanji, translator: translator) { updated in
                // Keep the card behind the sheet in step with what was just saved.
                info = updated
            }
        }
        .confirmationDialog("Replace your pinned mnemonic?",
                            isPresented: $confirmingReroll, titleVisibility: .visible) {
            Button("Replace it", role: .destructive) { regenerateMnemonic() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This mnemonic is pinned. A new one from the model will take its place.")
        }
        .task {
            async let infoTask: Void = loadInfo()
            async let svgTask: Void = loadSVG()
            _ = await (infoTask, svgTask)
        }
        .task {
            seenCount = FrequencyTracker.shared.kanjiFrequency(for: kanji)
        }
    }

    private var seenCountLabel: String {
        seenCount == 1 ? "Seen 1 time" : "Seen \(seenCount) times"
    }

    private var familiarityPicker: some View {
        KanjiFamiliarityPicker(kanji: kanji)
    }

    @ViewBuilder
    private var infoSection: some View {
        if isLoadingInfo {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading definition…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let infoError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text(infoError)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let info {
            VStack(alignment: .leading, spacing: 12) {
                if !info.meanings.isEmpty {
                    Text(info.meanings.joined(separator: ", "))
                        .font(.title3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !info.onyomi.isEmpty || !info.kunyomi.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !info.onyomi.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("On'yomi")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 86, alignment: .leading)
                                Text(info.onyomi.joined(separator: " ・ "))
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }
                        if !info.kunyomi.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Kun'yomi")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 86, alignment: .leading)
                                Text(info.kunyomi.joined(separator: " ・ "))
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if let jlpt = info.jlpt {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("JLPT")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 86, alignment: .leading)
                        Text("N\(jlpt)")
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                if let example = info.example {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Example")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 86, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.word)
                                .font(.system(.title3, design: .serif))
                                .textSelection(.enabled)
                            Text("\(example.reading) · \(example.meaning)")
                                .font(.footnote)
                                .selectableLabel(.secondary)
                        }
                    }
                }

                if let components = info.components, !components.isEmpty {
                    Text(components.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let mnemonic = info.mnemonic, !mnemonic.isEmpty {
                    Text(mnemonic)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .selectableLabel(.secondary)
                } else if let note = info.note, !note.isEmpty {
                    // Pre-mnemonic cache entries still carry the old memorable note.
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if info.pinned == true {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Outside the mnemonic check on purpose: a legacy note-only entry
                // still deserves a way to get a real mnemonic written for it.
                if isRegenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Writing a new mnemonic…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack(spacing: 16) {
                        Button("New mnemonic") {
                            if info.pinned == true {
                                confirmingReroll = true
                            } else {
                                regenerateMnemonic()
                            }
                        }
                        Button("Edit mnemonic…") { isEditingMnemonic = true }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
                if let regenerateError {
                    Text(regenerateError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var strokeOrderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stroke Order")
                    .font(.headline)
                Spacer()
                if svg != nil {
                    Button {
                        animationKey += 1
                    } label: {
                        Label("Replay", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isLoadingSVG {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading stroke order…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            } else if let svgError {
                Text(svgError)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            } else if let svg {
                KanjiStrokeView(svg: svg)
                    .id(animationKey)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
            }

            Text("Stroke order data: KanjiVG (CC BY-SA 3.0)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private func loadInfo() async {
        do {
            // Goes through the prefetcher so an in-flight background batch is
            // awaited instead of duplicated; cached or uncached-and-idle behave
            // exactly like translator.fetchKanjiInfo.
            info = try await KanjiInfoPrefetcher.shared.ensure(kanji)
        } catch {
            infoError = (error as? TranslationError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingInfo = false
    }

    /// Rerolls a mnemonic the user found unhelpful. The refetched entry replaces
    /// the cached one, so the new story sticks.
    private func regenerateMnemonic() {
        regenerateError = nil
        isRegenerating = true
        Task {
            do {
                info = try await translator.regenerateKanjiInfo(kanji: kanji)
            } catch {
                regenerateError = (error as? TranslationError)?.errorDescription ?? error.localizedDescription
            }
            isRegenerating = false
        }
    }

    private func loadSVG() async {
        do {
            svg = try await KanjiVGService.loadSVG(for: kanji)
        } catch {
            svgError = (error as? KanjiVGError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingSVG = false
    }
}

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

                        HStack(spacing: 12) {
                            NihongoLookupLink(kind: .kanji, query: String(kanji))
                            JishoLookupLink(kind: .kanji, query: String(kanji))
                            Spacer()
                        }

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
        .task {
            async let infoTask: Void = loadInfo()
            async let svgTask: Void = loadSVG()
            _ = await (infoTask, svgTask)
        }
        .task {
            seenCount = await FrequencyTracker.shared.kanjiFrequency(for: kanji)
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

                if let note = info.note, !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            info = try await translator.fetchKanjiInfo(kanji: kanji)
        } catch let error as TranslationError {
            infoError = error.errorDescription
        } catch {
            infoError = error.localizedDescription
        }
        isLoadingInfo = false
    }

    private func loadSVG() async {
        do {
            svg = try await KanjiVGService.loadSVG(for: kanji)
        } catch let error as KanjiVGError {
            svgError = error.errorDescription
        } catch {
            svgError = error.localizedDescription
        }
        isLoadingSVG = false
    }
}

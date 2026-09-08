import SwiftUI

@main
struct NihongoProApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Start iCloud sync once per launch. No-ops if iCloud is
                    // unavailable; the app works fully on local data either way.
                    await SyncCoordinator.shared.start()
                    // Then queue background kanji-info prefetch for every seen kanji
                    // (most-seen first) — after the initial sync so entries fetched
                    // by other devices / kanji-study aren't re-fetched.
                    KanjiInfoPrefetcher.shared.enqueueBacklog()
                    // Two-way sync with the Video-Study extension on launch, then on a
                    // periodic timer (no-op until the worker URL + secret are set).
                    await VideoStudySync.shared.sync()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(180))
                        await VideoStudySync.shared.sync()
                    }
                }
        }
    }
}

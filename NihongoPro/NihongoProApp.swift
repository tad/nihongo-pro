import SwiftUI

@main
struct NihongoProApp: App {
    /// True when the app is launched as the host for `NihongoProTests`. The test
    /// host is built unsigned (`CODE_SIGNING_ALLOWED=NO`), which strips the iCloud
    /// entitlement, so starting CloudKit sync there would crash at launch; the
    /// prefetch backlog and the Video-Study loop are just noise under test.
    static let isRunningTests: Bool =
        NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !Self.isRunningTests else { return }
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

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
                }
        }
    }
}

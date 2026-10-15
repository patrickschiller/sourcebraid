import SwiftUI

@main
struct SourceBraidApp: App {
    init() { ArchiveBackgroundRefresh.register() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.accentColor)
        }
    }
}

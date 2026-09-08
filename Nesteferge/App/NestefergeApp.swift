import SwiftUI

/// SwiftUI owns the phone window scene; no app delegate is needed.
@main
struct NestefergeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(FerryStore.shared)
        }
    }
}

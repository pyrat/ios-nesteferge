import SwiftUI

/// SwiftUI owns the phone window scene. The CarPlay scene is routed straight to
/// `CarPlaySceneDelegate` by the `UIApplicationSceneManifest` in Info.plist, so
/// no app delegate is needed to bridge the two.
@main
struct NestefergeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(FerryStore.shared)
        }
    }
}

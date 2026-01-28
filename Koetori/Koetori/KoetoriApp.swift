import SwiftUI

@main
struct KoetoriApp: App {
    var body: some Scene {
        WindowGroup {
            RecordingView()
                .preferredColorScheme(.dark)
        }
    }
}

import SwiftUI

@main
struct KoetoriApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RecordingView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink("History") {
                                HistoryView()
                            }
                            .foregroundColor(.primary)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }
}

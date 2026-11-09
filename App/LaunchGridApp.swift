import SwiftUI

@main
struct LaunchGridApp: App {
    @StateObject private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { store.handle($0) }   // ウィジェットからの launchgrid://run?id=...
        }
    }
}

import SwiftUI

@main
struct GeodeApp: App {
    @StateObject private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { store.handle($0) }   // ウィジェットからの geode://run?id=...
        }
    }
}

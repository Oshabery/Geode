import SwiftUI

/// ユーザーの指定で一旦外している機能。true に戻せば元どおり表示される
/// （コードと保存データは残してある）
enum Features {
    /// 画面下部の 3 つのボタン（DockBar）
    static let dock = false
    /// 通知バッジ（BadgeRing）。オフの間は、保存済みのバッジにも触らない
    static let badge = false
}

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

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var editing = false
    @State private var showLayout = false
    @State private var working = false
    @State private var info: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if editing {
                    Menu {
                        Button("検出したアプリを一括配置", systemImage: "square.and.arrow.down.on.square") {
                            Task {
                                working = true
                                let n = await store.addDetectedApps()
                                working = false
                                info = n > 0 ? "\(n) 件のアプリを配置しました。" : "追加できるアプリはありませんでした（配置済み、または空きマスなし）。"
                            }
                        }
                        Button("レイアウト（行・列）", systemImage: "square.grid.3x3") { showLayout = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title2)
                    }
                    if working { ProgressView().padding(.leading, 8) }
                }
                Spacer()
                Button(editing ? "完了" : "編集") { editing.toggle() }
                    .font(.title3.weight(editing ? .bold : .regular))
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            if editing {
                EditGridView(slots: $store.board.slots, layout: store.board.layout, allowGroups: true)
            } else {
                LauncherGridView()
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showLayout) { LayoutSettings().environmentObject(store) }
        .alert("Geode", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") {}
        } message: { Text(info ?? "") }
        .alert("起動エラー", isPresented: Binding(get: { store.errorMessage != nil },
                                              set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct LayoutSettings: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var layout = GridLayout()
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("列: \(layout.columns)", value: $layout.columns, in: 2...5)
                    Stepper("行: \(layout.rows)", value: $layout.rows, in: 3...8)
                } footer: {
                    Text("グループ内のグリッドも同じ行・列になります。はみ出すアイテムは空きマスへ移動します。")
                }
            }
            .navigationTitle("レイアウト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        if store.applyLayout(layout) { dismiss() } else { failed = true }
                    }
                }
            }
            .alert("アイテムが収まりません。先にいくつか削除してください。", isPresented: $failed) { Button("OK") {} }
            .onAppear { layout = store.board.layout }
        }
        .presentationDetents([.medium])
    }
}

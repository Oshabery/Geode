import SwiftUI

/// 外観設定（@AppStorage("appearance") に保存）
enum Appearance: Int, CaseIterable, Identifiable {
    case auto, light, dark
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .auto: return "自動"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: BoardStore
    @AppStorage("appearance") private var appearance = Appearance.auto.rawValue
    @State private var editing = false
    @State private var showSettings = false

    private var scheme: ColorScheme? { Appearance(rawValue: appearance)?.colorScheme }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title2)
                }
                .accessibilityLabel("設定")
                Spacer()
                Button { editing.toggle() } label: {
                    Image(systemName: editing ? "checkmark.circle.fill" : "pencil").font(.title2)
                }
                .accessibilityLabel(editing ? "編集を完了" : "編集")
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            if editing {
                EditGridView(slots: $store.board.slots, layout: store.board.layout, allowGroups: true)
            } else {
                LauncherGridView()
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .preferredColorScheme(scheme)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
                .preferredColorScheme(scheme)
        }
        .alert("起動エラー", isPresented: Binding(get: { store.errorMessage != nil },
                                              set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.auto.rawValue
    @AppStorage("showLabels") private var showLabels = true
    @State private var working = false
    @State private var message: String?

    /// 行・列は変更のたびに即反映。収まらなければ元のままにして知らせる。
    private func layoutBinding(_ keyPath: WritableKeyPath<GridLayout, Int>) -> Binding<Int> {
        Binding(
            get: { store.board.layout[keyPath: keyPath] },
            set: { newValue in
                var layout = store.board.layout
                layout[keyPath: keyPath] = newValue
                if !store.applyLayout(layout) {
                    message = "アイテムが収まりません。先にいくつか削除してください。"
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("外観") {
                    Picker("モード", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("アプリ名を表示", isOn: $showLabels)
                    Stepper("列: \(store.board.layout.columns)", value: layoutBinding(\.columns), in: 2...5)
                    Stepper("行: \(store.board.layout.rows)", value: layoutBinding(\.rows), in: 3...8)
                } header: {
                    Text("グリッド")
                } footer: {
                    Text("アイコンはマスに収まる最大サイズで表示されます。アプリ名を消す、または行・列を減らすと大きくなります。グループ内も同じ行・列です。")
                }

                Section {
                    Button {
                        Task {
                            working = true
                            let n = await store.addDetectedApps()
                            working = false
                            message = n > 0 ? "\(n) 件のアプリを配置しました。"
                                            : "追加できるアプリはありませんでした（配置済み、または空きマスなし）。"
                        }
                    } label: {
                        HStack {
                            Label("検出したアプリを一括配置", systemImage: "square.and.arrow.down.on.square")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                } header: {
                    Text("アプリ")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .alert("Geode", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }
}

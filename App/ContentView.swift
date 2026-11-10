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
    @AppStorage("useCustomBackground") private var useCustomBackground = false
    @AppStorage("backgroundColor") private var backgroundColor = Theme.defaultBackground
    @AppStorage("useCustomTint") private var useCustomTint = false
    @AppStorage("tintColor") private var tintColor = Theme.defaultTint
    @State private var editing = false
    @State private var showSettings = false

    private var scheme: ColorScheme? { Appearance(rawValue: appearance)?.colorScheme }
    private var tint: Color? { useCustomTint ? tintColor.color : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                }
                .glass(in: Circle(), interactive: true)
                .accessibilityLabel("設定")
                Spacer()
                Button { editing.toggle() } label: {
                    Image(systemName: editing ? "checkmark" : "pencil").font(.title3).frame(width: 44, height: 44)
                }
                .glass(in: Circle(), tint: editing ? tint ?? .accentColor : nil, interactive: true)
                .accessibilityLabel(editing ? "編集を完了" : "編集")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if editing {
                EditGridView(slots: $store.board.slots, layout: store.board.layout, allowGroups: true)
            } else {
                LauncherGridView()
            }
        }
        .background((useCustomBackground ? backgroundColor.color : Color(.systemBackground)).ignoresSafeArea())
        .tint(tint)
        .preferredColorScheme(scheme)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
                .tint(tint)
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
    @AppStorage("gridGap") private var gridGap = GridDefaults.gap
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("useCustomBackground") private var useCustomBackground = false
    @AppStorage("backgroundColor") private var backgroundColor = Theme.defaultBackground
    @AppStorage("useCustomTint") private var useCustomTint = false
    @AppStorage("tintColor") private var tintColor = Theme.defaultTint
    @AppStorage("glassIcons") private var glassIcons = false
    @AppStorage("labelWeight") private var labelWeight = Theme.defaultWeight
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("useCustomGridColor") private var useCustomGridColor = false
    @AppStorage("gridColor") private var gridColor = Theme.defaultGrid
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
                    Toggle("アイコンをガラス風にする", isOn: $glassIcons)
                }

                Section {
                    Toggle("背景色を指定", isOn: $useCustomBackground)
                    if useCustomBackground { HSBEditor(color: $backgroundColor) }
                } header: {
                    Text("背景色（HSB）")
                } footer: {
                    Text("オフのときは外観モードに合わせた白 / 黒になります。")
                }

                Section {
                    Toggle("UI の色を指定", isOn: $useCustomTint)
                    if useCustomTint { HSBEditor(color: $tintColor) }
                } header: {
                    Text("UI の色（HSB）")
                } footer: {
                    Text("アプリ名、ボタン、シンボルのアイコンに使う色です。コードは「色相 0–360, 彩度 0–100, 明度 0–100」の順で入力します。")
                }

                Section {
                    Toggle("グリッド線を表示", isOn: $showGridLines)
                    if showGridLines {
                        Toggle("グリッド線の色を指定", isOn: $useCustomGridColor)
                        if useCustomGridColor { HSBEditor(color: $gridColor) }
                    }
                } header: {
                    Text("グリッド線の色（HSB）")
                } footer: {
                    Text("色の指定がオフのときは、UI の色を薄くした線になります。")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("アイコンサイズ: \(Int((iconScale * 100).rounded()))%")
                        Slider(value: $iconScale, in: 0.4...1, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        Text("余白: \(Int(gridGap)) pt")
                        Slider(value: $gridGap, in: 0...40, step: 1)
                    }
                    Button("サイズと余白を初期値に戻す") {
                        iconScale = GridDefaults.iconScale
                        gridGap = GridDefaults.gap
                    }
                    .disabled(iconScale == GridDefaults.iconScale && gridGap == GridDefaults.gap)
                } header: {
                    Text("サイズと余白")
                } footer: {
                    Text("余白は、アイコン同士の間隔と画面端までの間隔の最小値です。アイコンサイズは、その余白で収まる最大サイズに対する割合です。小さくした分は余白へ均等に配分されます。")
                }

                Section {
                    Toggle("アプリ名を表示", isOn: $showLabels)
                    Picker("アプリ名の太さ", selection: $labelWeight) {
                        ForEach(Theme.weights.indices, id: \.self) { Text(Theme.weights[$0].name).tag($0) }
                    }
                    .disabled(!showLabels)
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
            .presentationDetents([.medium, .large])   // 半分の高さにすると、後ろのグリッドで変化を確認できる
            .alert("Geode", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }
}

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
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    @State private var editing = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }
    /// グローは暗い画面専用。保存している外観モードは書き換えず、表示のときだけダークにする
    private var scheme: ColorScheme? { isGlow ? .dark : Appearance(rawValue: appearance)?.colorScheme }
    private var tint: Color? { useCustomTint ? tintColor.color : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                }
                .styledCircleGlass(interactive: true)
                .accessibilityLabel("設定")
                Spacer()
                Button { editing.toggle() } label: {
                    Image(systemName: editing ? "checkmark" : "pencil").font(.title3).frame(width: 44, height: 44)
                }
                .styledCircleGlass(tint: editing ? tint ?? .accentColor : nil, interactive: true)
                .accessibilityLabel(editing ? "編集を完了" : "編集")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if editing {
                EditGridView(slots: $store.board.slots, layout: store.board.layout, allowGroups: true)
            } else {
                LauncherGridView()
            }

            DockBar(editing: editing)
        }
        .background {
            if isGlow {
                GlowBackground()
            } else {
                (useCustomBackground ? backgroundColor.color : Color(.systemBackground)).ignoresSafeArea()
            }
        }
        .tint(tint)
        .preferredColorScheme(scheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshDirectStates() }
        }
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
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("gridGap") private var gridGapX = GridDefaults.gapX
    @AppStorage("gridGapY") private var gridGapY = GridDefaults.gapY
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("useCustomBackground") private var useCustomBackground = false
    @AppStorage("backgroundColor") private var backgroundColor = Theme.defaultBackground
    @AppStorage("useCustomTint") private var useCustomTint = false
    @AppStorage("tintColor") private var tintColor = Theme.defaultTint
    @AppStorage("glassIcons") private var glassIcons = false
    @AppStorage("labelWeight") private var labelWeight = Theme.defaultWeight
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @AppStorage("dockSpacing") private var dockSpacing = GridDefaults.dockSpacing
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
                Section {
                    Picker("デザイン", selection: $uiStyle) {
                        ForEach(UIStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Picker("モード", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(uiStyle == UIStyle.glow.rawValue)
                    Toggle("アイコンをガラス風にする", isOn: $glassIcons)
                        .disabled(uiStyle == UIStyle.glow.rawValue)
                    if uiStyle == UIStyle.glow.rawValue {
                        GlowColorPicker()
                    }
                } header: {
                    Text("外観")
                } footer: {
                    if uiStyle == UIStyle.glow.rawValue {
                        Text("グローは黒地に青い光のデザインです。暗い画面専用のため、モード・ガラス風アイコン・背景色は使われません（設定は残っていて、「標準」に戻すと元どおりになります）。")
                    }
                }

                Section {
                    Toggle("背景色を指定", isOn: $useCustomBackground)
                    if useCustomBackground { HSBEditor(color: $backgroundColor) }
                } header: {
                    Text("背景色（HSB）")
                } footer: {
                    Text("オフのときは外観モードに合わせた白 / 黒になります。")
                }
                .disabled(uiStyle == UIStyle.glow.rawValue)

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
                        Text("横の間隔: \(Int(gridGapX)) pt")
                        Slider(value: $gridGapX, in: 0...150, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("縦の間隔: \(Int(gridGapY)) pt")
                        Slider(value: $gridGapY, in: 0...150, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("外側の余白: \(Int(outerMargin)) pt")
                        Slider(value: $outerMargin, in: 0...60, step: 1)
                    }
                    Button("サイズと余白を初期値に戻す") {
                        iconScale = GridDefaults.iconScale
                        gridGapX = GridDefaults.gapX
                        gridGapY = GridDefaults.gapY
                        outerMargin = GridDefaults.outerMargin
                    }
                    .disabled(iconScale == GridDefaults.iconScale && gridGapX == GridDefaults.gapX
                              && gridGapY == GridDefaults.gapY && outerMargin == GridDefaults.outerMargin)
                } header: {
                    Text("サイズと余白")
                } footer: {
                    Text("アイコンは画面中央を基準に並びます。間隔は隣のアイコンとの距離で、広げるほど中央から外側へ広がります。外側の余白は、端から一番外のアイコンまで最低限あける距離です。アイコンは正方形なので、縦横のうち余裕のある方向では端までの距離が設定より広くなります。その方向の間隔を広げると端に近づきます。")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("ボタンの間隔: \(Int(dockSpacing)) pt")
                        Slider(value: $dockSpacing, in: 0...150, step: 1)
                    }
                } header: {
                    Text("下部の 3 つのボタン")
                } footer: {
                    Text("中央のボタンを基準に、左右のボタンをどれだけ離すかを決めます。画面の幅を超える値にしても、端で止まります。")
                }

                if !store.estimatedSwitches.isEmpty {
                    Section {
                        ForEach(store.estimatedSwitches) { item in
                            Toggle(item.name, isOn: Binding(
                                get: { store.switchState(for: item) ?? false },
                                set: { store.setSwitchState(item, $0) }))
                        }
                    } header: {
                        Text("オン / オフの表示")
                    } footer: {
                        Text("ショートカット経由のオン / オフは、Geode が状態を推定してアイコンを反転しています。コントロールセンターなど Geode の外で切り替えて表示がずれたときは、ここで直せます（操作は実行されません）。")
                    }
                }

                Section {
                    Toggle("アプリ名を表示", isOn: $showLabels)
                    Picker("アプリ名の太さ", selection: $labelWeight) {
                        ForEach(Theme.weights.indices, id: \.self) { Text(Theme.weights[$0].name).tag($0) }
                    }
                    .disabled(!showLabels)
                    VStack(alignment: .leading) {
                        Text("アイコンとアプリ名の間隔: \(Int(labelSpacing)) pt")
                        Slider(value: $labelSpacing, in: 0...24, step: 1)
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

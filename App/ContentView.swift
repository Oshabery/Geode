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
    @AppStorage("glowMotion") private var glowMotion = true
    @AppStorage("glowMotionStrength") private var glowMotionStrength = 1.0
    @State private var editing = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }
    /// グローは暗い画面専用。保存している外観モードは書き換えず、表示のときだけダークにする
    private var scheme: ColorScheme? { isGlow ? .dark : Appearance(rawValue: appearance)?.colorScheme }
    private var tint: Color? { useCustomTint ? tintColor.color : nil }

    /// 傾きの読み取りは、グローを選んでいて、設定がオンで、アプリが前面のときだけ動かす
    private func updateGlowMotion() {
        GlowMotion.shared.strength = glowMotionStrength
        if isGlow && glowMotion && scenePhase == .active {
            GlowMotion.shared.start()
        } else {
            GlowMotion.shared.stop()
        }
    }

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
                    // グループを開いている間だけ最前面にして、暗い背景が下のボタンも覆うようにする
                    .zIndex(store.groupLayerOpen ? 1 : 0)
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
            updateGlowMotion()
        }
        .onChange(of: uiStyle) { _, _ in updateGlowMotion() }
        .onChange(of: glowMotion) { _, _ in updateGlowMotion() }
        .onChange(of: glowMotionStrength) { _, _ in updateGlowMotion() }
        .onAppear { updateGlowMotion() }
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
    @AppStorage("gridLineOpacity") private var gridLineOpacity = 1.0
    @AppStorage("gridOffsetY") private var gridOffsetY = 0.0
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

    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }

    var body: some View {
        NavigationStack {
            Form {
                SettingsGroup("外観", id: "appearance",
                              footer: isGlow ? "グローは暗い地に色の光のデザインです。モード・ガラス風アイコン・背景色は使われません（設定は残っていて、「標準」に戻すと元どおりになります）。" : nil) {
                    Picker("デザイン", selection: $uiStyle) {
                        ForEach(UIStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Picker("モード", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isGlow)
                    Toggle("アイコンをガラス風にする", isOn: $glassIcons)
                        .disabled(isGlow)
                    if isGlow {
                        GlowColorPicker()
                        GlowMotionSettings()
                    }
                }

                SettingsGroup("背景色（HSB）", id: "background",
                              footer: "オフのときは外観モードに合わせた白 / 黒になります。") {
                    Toggle("背景色を指定", isOn: $useCustomBackground)
                    if useCustomBackground { HSBEditor(color: $backgroundColor) }
                }
                .disabled(isGlow)

                SettingsGroup("UI の色（HSB）", id: "tint",
                              footer: "アプリ名、ボタン、シンボルのアイコンに使う色です。コードは「色相 0–360, 彩度 0–100, 明度 0–100」の順で入力します。") {
                    Toggle("UI の色を指定", isOn: $useCustomTint)
                    if useCustomTint { HSBEditor(color: $tintColor) }
                }

                SettingsGroup("グリッド線", id: "gridLines",
                              footer: "色の指定がオフのときは、UI の色を薄くした線になります。") {
                    Toggle("グリッド線を表示", isOn: $showGridLines)
                    if showGridLines {
                        VStack(alignment: .leading) {
                            Text("グリッド線の濃さ: \(Int((gridLineOpacity * 100).rounded()))%")
                            Slider(value: $gridLineOpacity, in: 0.05...1, step: 0.05)
                        }
                        Toggle("グリッド線の色を指定", isOn: $useCustomGridColor)
                        if useCustomGridColor { HSBEditor(color: $gridColor) }
                    }
                }

                SettingsGroup("サイズと余白", id: "size",
                              footer: "アイコンは画面中央を基準に並びます。間隔は隣のアイコンとの距離で、広げるほど中央から外側へ広がります。外側の余白は、端から一番外のアイコンまで最低限あける距離です。上下の位置は、上下に空いている分だけ動かせます。動かないときは、アイコンサイズ・縦の間隔・行の数を減らすか、アプリ名を消すと空きができます。") {
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
                    VStack(alignment: .leading) {
                        Text("上下の位置: \(gridOffsetY > 0 ? "下へ" : gridOffsetY < 0 ? "上へ" : "中央")\(gridOffsetY == 0 ? "" : " \(Int(abs(gridOffsetY))) pt")")
                        Slider(value: $gridOffsetY, in: -200...200, step: 2)
                    }
                    Button("サイズと余白を初期値に戻す") {
                        iconScale = GridDefaults.iconScale
                        gridGapX = GridDefaults.gapX
                        gridGapY = GridDefaults.gapY
                        outerMargin = GridDefaults.outerMargin
                        gridOffsetY = 0
                    }
                    .disabled(iconScale == GridDefaults.iconScale && gridGapX == GridDefaults.gapX
                              && gridGapY == GridDefaults.gapY && outerMargin == GridDefaults.outerMargin
                              && gridOffsetY == 0)
                }

                SettingsGroup("グリッド", id: "grid",
                              footer: "アイコンはマスに収まる最大サイズで表示されます。アプリ名を消す、または行・列を減らすと大きくなります。グループ内も同じ行・列です。") {
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
                }

                SettingsGroup("下部の 3 つのボタン", id: "dock",
                              footer: "中央のボタンを基準に、左右のボタンをどれだけ離すかを決めます。画面の幅を超える値にしても、端で止まります。") {
                    VStack(alignment: .leading) {
                        Text("ボタンの間隔: \(Int(dockSpacing)) pt")
                        Slider(value: $dockSpacing, in: 0...150, step: 1)
                    }
                }

                if !store.estimatedSwitches.isEmpty {
                    SettingsGroup("オン / オフの表示", id: "switches",
                                  footer: "ショートカット経由のオン / オフは、Geode が状態を推定してアイコンを反転しています。コントロールセンターなど Geode の外で切り替えて表示がずれたときは、ここで直せます（操作は実行されません）。") {
                        ForEach(store.estimatedSwitches) { item in
                            Toggle(item.name, isOn: Binding(
                                get: { store.switchState(for: item) ?? false },
                                set: { store.setSwitchState(item, $0) }))
                        }
                    }
                }

                SettingsGroup("アプリ", id: "apps") {
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

/// 設定画面の折りたためるまとまり。開閉の状態は項目ごとに覚えておく（最初は閉じている）
struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content
    @AppStorage private var expanded: Bool

    init(_ title: String, id: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
        _expanded = AppStorage(wrappedValue: false, "settingsOpen." + id)
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                content
            } label: {
                Text(title).font(.headline)
            }
        } footer: {
            if expanded, let footer {
                Text(footer)
            }
        }
    }
}

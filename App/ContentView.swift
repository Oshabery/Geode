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
    @AppStorage("preferBottomTouches") private var preferBottomTouches = false
    @AppStorage("glowLight") private var glowLight = false
    @AppStorage("glowMotion") private var glowMotion = true
    @AppStorage("glowMotionStrength") private var glowMotionStrength = 1.0
    @State private var editing = false
    @State private var showSettings = false
    /// iPad の向き（アイコンを回す角度と、縦 / 横どちらの配置を出すか）
    @ObservedObject private var canvas = CanvasOrientation.shared
    private let isPad = UIDevice.current.userInterfaceIdiom == .pad

    /// いま使う配置の向き。iPad を横に持っていれば横画面の配置。iPhone は常に縦
    private var orientation: BoardOrientation {
        isPad && canvas.isLandscape ? .landscape : .portrait
    }

    /// 向きごとの配置を編集するためのバインディング
    private var pageSlots: Binding<[Int: LaunchItem]> {
        let orientation = orientation
        return Binding(get: { store.board.slots(for: orientation) },
                       set: { store.board.setSlots($0, for: orientation) })
    }
    @Environment(\.scenePhase) private var scenePhase

    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }
    /// グローは「グローの明るさ」でダーク / ライトを決める。標準の外観モードの設定は書き換えない
    private var scheme: ColorScheme? {
        isGlow ? (glowLight ? .light : .dark) : Appearance(rawValue: appearance)?.colorScheme
    }
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

    /// 上の「設定」「編集」ボタン
    private var topBar: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }
            .styledCircleGlass(interactive: true)
            .accessibilityLabel("設定")
            Spacer()
            if isPad && editing {
                // iPad: どちらの向きの並びを編集しているかを示す（縦と横で別々の並び）
                Text(orientation == .landscape ? "横画面の並びを編集中" : "縦画面の並びを編集中")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .glass(in: Capsule())
                    .accessibilityIdentifier("geode-editing-orientation")
                Spacer()
            }
            Button { editing.toggle() } label: {
                Image(systemName: editing ? "checkmark" : "pencil").font(.title3).frame(width: 44, height: 44)
            }
            .styledCircleGlass(tint: editing ? tint ?? .accentColor : nil, interactive: true)
            .accessibilityLabel(editing ? "編集を完了" : "編集")
        }
        .padding(.horizontal, 16)
        .frame(height: Self.topBarHeight)
    }

    private static let topBarHeight: CGFloat = 56

    /// グリッド（通常モード / 編集モード）
    @ViewBuilder
    private var grid: some View {
        if editing {
            EditGridView(slots: pageSlots, layout: store.board.layout(for: orientation), allowGroups: true)
                // 向きが変わったら、編集中の状態（開いている編集画面など）を捨てて作り直す。
                // 古い向きのマス番号のまま、別の向きの配置へ保存してしまわないようにするため
                .id(orientation)
        } else {
            LauncherGridView(orientation: orientation)
                // グループを開いている間だけ最前面にして、暗い背景が下のボタンも覆うようにする
                .zIndex(store.groupLayerOpen ? 1 : 0)
        }
    }

    /// iPhone: 上のボタンとグリッド
    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            grid
            if DockBar.enabled {
                DockBar(editing: editing)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if isGlow {
            GlowBackground()
        } else {
            (useCustomBackground ? backgroundColor.color : Color(.systemBackground)).ignoresSafeArea()
        }
    }

    /// iPad: グリッドと背景は端末に対して動かさない（`FixedCanvas`）。アイコンだけが持った向きに回り、縦 / 横の配置に入れ替わる。
    /// 上のボタンはウィンドウ側に置くので、持った向きの上の角へ移る
    private var padContent: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            // ボタンはどの辺の上にも来うるので、グリッドは四辺ともボタンとステータスバーの分を空ける
            let edge = max(insets.top, insets.bottom, insets.leading, insets.trailing) + Self.topBarHeight
            ZStack(alignment: .top) {
                FixedCanvas(content: fixedLayer(edge: edge))
                    .ignoresSafeArea()
                topBar
                    // グループを開いている間は、暗い背景の上に出ないよう隠す
                    .opacity(store.groupLayerOpen ? 0 : 1)
                    .allowsHitTesting(!store.groupLayerOpen)
                    .animation(.easeOut(duration: 0.2), value: store.groupLayerOpen)
            }
        }
    }

    /// 動かさないキャンバスの中身。別の UIHostingController で描くので、環境の値はここで渡し直す
    private func fixedLayer(edge: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                background
                grid
                    .padding(edge)
                if SharedStorage.isUITesting {
                    // UI テスト用の目印: キャンバスの左上の角（端末を縦に持ったときの左上）。回しても画面上で動かないことを確かめる
                    Rectangle().fill(Color.black.opacity(0.01))
                        .frame(width: 8, height: 8)
                        .accessibilityElement()
                        .accessibilityIdentifier("geode-canvas-origin")
                }
            }
            .environment(\.geodeCanvasSize, geo.size)
            .coordinateSpace(name: CanvasRotation.coordinateSpace)
        }
        .environment(\.geodeIconAngle, canvas.iconDegrees)
        .environment(\.geodeRevealToken, canvas.revealToken)
        .environment(\.geodeIconsHidden, canvas.iconsHidden)
        .environmentObject(store)
        .tint(tint)
        .preferredColorScheme(scheme)
    }

    var body: some View {
        Group {
            if isPad {
                padContent
            } else {
                mainContent
                    .background { background }
            }
        }
        .tint(tint)
        .preferredColorScheme(scheme)
        // 画面下端の近くは、iOS がホームへ戻るスワイプかを見分けるためにタッチを遅らせる。
        // オンにすると Geode のタッチを優先する（代わりにホームへ戻るには下端を 2 回スワイプする）
        .defersSystemGestures(on: preferBottomTouches ? .bottom : [])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshDirectStates() }
            updateGlowMotion()
        }
        .onChange(of: uiStyle) { _, _ in updateGlowMotion() }
        .onChange(of: glowMotion) { _, _ in updateGlowMotion() }
        .onChange(of: glowMotionStrength) { _, _ in updateGlowMotion() }
        .onAppear {
            updateGlowMotion()
            // UI テストで出直しの動きを録画する（-GeodeRevealLoop）: 回さずに 3 秒ごとにアイコンを隠して出し直す
            if SharedStorage.isUITesting, CommandLine.arguments.contains("-GeodeRevealLoop") {
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    Task { @MainActor in
                        print("GEODE-REVEAL \(Date().timeIntervalSince1970)")
                        CanvasOrientation.shared.hideIcons()
                        try? await Task.sleep(for: .milliseconds(300))
                        CanvasOrientation.shared.revealIcons()
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(orientation: orientation)
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
    /// 行・列と一括配置の対象になる配置の向き（開いたときの画面の向き）
    let orientation: BoardOrientation
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
    @AppStorage("labelWeight") private var labelWeight = Theme.defaultWeight
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @AppStorage("dockSpacing") private var dockSpacing = GridDefaults.dockSpacing
    @AppStorage("useCustomGridColor") private var useCustomGridColor = false
    @AppStorage("gridColor") private var gridColor = Theme.defaultGrid
    @AppStorage("gridLineOpacity") private var gridLineOpacity = 1.0
    @AppStorage("gridOffsetY") private var gridOffsetY = 0.0
    @AppStorage("preferBottomTouches") private var preferBottomTouches = false
    @State private var working = false
    @State private var message: String?

    /// 行・列は変更のたびに即反映。収まらなければ元のままにして知らせる。
    private func layoutBinding(_ keyPath: WritableKeyPath<GridLayout, Int>) -> Binding<Int> {
        Binding(
            get: { store.board.layout(for: orientation)[keyPath: keyPath] },
            set: { newValue in
                var layout = store.board.layout(for: orientation)
                layout[keyPath: keyPath] = newValue
                if !store.applyLayout(layout) {
                    message = "アイテムが収まりません。先にいくつか削除してください。"
                }
            }
        )
    }

    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            Form {
                SettingsGroup("外観", id: "appearance",
                              footer: isGlow ? "グローは地に色の光が差すデザインです。明るさは「グローの明るさ」で選びます。上のモードと背景色は使われません（設定は残っていて、「標準」に戻すと元どおりになります）。" : nil) {
                    Picker("デザイン", selection: $uiStyle) {
                        ForEach(UIStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Picker("モード", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isGlow)
                    if isGlow {
                        GlowBrightnessPicker()
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
                              footer: "アイコンは画面中央を基準に並びます。間隔は隣のアイコンとの距離で、広げるほど中央から外側へ広がります。外側の余白は、端から一番外のアイコンまで最低限あける距離です。上下の位置は、上下に空いている分だけ動かせます。アイコンが縦いっぱいの大きさのときはほとんど動きません。アイコンサイズを小さくする、外側の余白を広げる、行を減らす、アプリ名を消すと空きができます。") {
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
                    // iPad は画面が広いので、行・列を多くできる
                    if isPad {
                        // iPad: 行と列は縦横共通、アイコンの並びは縦と横で別
                        Text("行と列は縦画面と横画面で共通です。アイコンの並びは縦と横で別々に編集できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Stepper("列: \(store.board.layout(for: orientation).columns)", value: layoutBinding(\.columns),
                            in: isPad ? Board.padColumns : 2...5)
                    Stepper("行: \(store.board.layout(for: orientation).rows)", value: layoutBinding(\.rows),
                            in: isPad ? Board.padRows : 3...8)
                }

                SettingsGroup("操作", id: "touch",
                              footer: "画面の下端の近くは、iOS がホームへ戻るスワイプかどうかを見分けるために、タッチを少し遅らせます。そのため一番下の行（特に中央）の反応が遅くなります。オンにすると Geode の操作を優先しますが、Geode を表示している間は、ホームへ戻るのに下端を 2 回スワイプする必要があります。") {
                    Toggle("下端のタッチを優先する", isOn: $preferBottomTouches)
                }

                if DockBar.enabled {
                    SettingsGroup("下部の 3 つのボタン", id: "dock",
                                  footer: "中央のボタンを基準に、左右のボタンをどれだけ離すかを決めます。画面の幅を超える値にしても、端で止まります。") {
                        VStack(alignment: .leading) {
                            Text("ボタンの間隔: \(Int(dockSpacing)) pt")
                            Slider(value: $dockSpacing, in: 0...150, step: 1)
                        }
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
                            let n = await store.addDetectedApps(for: orientation)
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

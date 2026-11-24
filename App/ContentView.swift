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

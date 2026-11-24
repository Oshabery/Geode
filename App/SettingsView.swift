import SwiftUI

/// 設定画面（ユーザーと決めたデザイン: キャンバス「Geode 設定画面の調整」の「案 3 改」）。
/// - 一番上にプレビューを固定し、下の一覧をスクロールしても動かない
/// - iOS の設定と同じ、グループ分けした一覧。各行に今の値を出し、細かい調整は 1 つ下の画面へ
/// - グローを選んでいる間は、使わない項目（外観モード・背景色・UI の色）を出さず、グロー専用の項目だけを出す
struct SettingsView: View {
    /// 一括配置の対象になる配置の向き（開いたときの画面の向き）
    let orientation: BoardOrientation
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.auto.rawValue
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    @AppStorage("glowLight") private var glowLight = false
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("useCustomBackground") private var useCustomBackground = false
    @AppStorage("useCustomTint") private var useCustomTint = false
    @AppStorage("tintColor") private var tintColor = Theme.defaultTint
    @AppStorage("backgroundColor") private var backgroundColor = Theme.defaultBackground
    @AppStorage("preferBottomTouches") private var preferBottomTouches = false
    @State private var working = false
    @State private var message: String?

    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }

    var body: some View {
        NavigationStack {
            Form {
                designSection
                if isGlow {
                    GlowColorSection()
                    GlowMotionSection()
                } else {
                    colorSection
                }
                layoutSection
                touchSection
                if !store.estimatedSwitches.isEmpty { switchSection }
                appsSection
            }
            // プレビューは一覧の上に固定する（一覧をスクロールしても動かない）
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsPreview(orientation: orientation)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(.bar)
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
        .presentationDetents([.medium, .large])   // 半分の高さにすると、後ろのグリッドでも変化を確認できる
    }

    // MARK: デザイン

    private var designSection: some View {
        Section("デザイン") {
            Picker("デザイン", selection: $uiStyle) {
                ForEach(UIStyle.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if isGlow {
                LabeledContent("明るさ") {
                    Picker("明るさ", selection: $glowLight) {
                        Text("ダーク").tag(false)
                        Text("ライト").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            } else {
                LabeledContent("外観モード") {
                    Picker("外観モード", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 210)
                }
            }
        }
    }

    // MARK: 色（標準のみ）

    private var colorSection: some View {
        Section("色") {
            NavigationLink {
                ColorSettingPage(title: "背景色", toggleTitle: "背景色を指定", isOn: $useCustomBackground,
                                 color: $backgroundColor,
                                 footer: "オフのときは外観モードに合わせた白 / 黒になります。")
            } label: {
                ColorRow(title: "背景色", isOn: useCustomBackground, color: backgroundColor.color, offText: "自動")
            }
            NavigationLink {
                ColorSettingPage(title: "UI の色", toggleTitle: "UI の色を指定", isOn: $useCustomTint,
                                 color: $tintColor,
                                 footer: "アプリ名、ボタン、シンボルのアイコンに使う色です。コードは「色相 0–360, 彩度 0–100, 明度 0–100」の順で入力します。")
            } label: {
                ColorRow(title: "UI の色", isOn: useCustomTint, color: tintColor.color, offText: "標準")
            }
        }
    }

    // MARK: レイアウト・表示

    private var layoutSection: some View {
        let layout = store.board.layout(for: orientation)
        return Section {
            NavigationLink {
                SizeSettingsPage(message: $message)
            } label: {
                LabeledContent("サイズと余白", value: "\(layout.columns) × \(layout.rows) ・ \(Int((iconScale * 100).rounded()))%")
            }
            NavigationLink {
                LabelGridSettingsPage()
            } label: {
                LabeledContent("アプリ名とグリッド線", value: labelGridSummary)
            }
        } header: {
            Text("レイアウト・表示")
        } footer: {
            if isGlow {
                Text("グローでは外観モード・背景色・UI の色は使いません。「標準」に戻すと元の設定で表示されます。")
            }
        }
    }

    private var labelGridSummary: String {
        switch (showLabels, showGridLines) {
        case (true, true): return "どちらも表示"
        case (true, false): return "アプリ名のみ"
        case (false, true): return "グリッド線のみ"
        case (false, false): return "表示しない"
        }
    }

    // MARK: 操作・スイッチ・アプリ

    private var touchSection: some View {
        Section {
            Toggle("下端のタッチを優先する", isOn: $preferBottomTouches)
        } header: {
            Text("操作")
        } footer: {
            Text("オンにすると一番下の行がすぐ反応します。代わりに、Geode を表示している間は下端を 2 回スワイプしてホームへ戻ります。")
        }
    }

    private var switchSection: some View {
        Section {
            ForEach(store.estimatedSwitches) { item in
                Toggle(item.name, isOn: Binding(
                    get: { store.switchState(for: item) ?? false },
                    set: { store.setSwitchState(item, $0) }))
            }
        } header: {
            Text("オン / オフの表示")
        } footer: {
            Text("ショートカット経由のオン / オフは、Geode が状態を推定してアイコンを反転しています。Geode の外で切り替えて表示がずれたときは、ここで直せます（操作は実行されません）。")
        }
    }

    private var appsSection: some View {
        Section("アプリ") {
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
                    Label("検出したアプリを空きマスに並べる", systemImage: "square.grid.2x2")
                    Spacer()
                    if working { ProgressView() }
                }
            }
            .disabled(working)
        }
    }
}

// MARK: - プレビュー

/// 設定画面の上に固定するプレビュー。いまの盤面の最初のアイコン（無ければ見本）を、いまの設定で描く
struct SettingsPreview: View {
    let orientation: BoardOrientation
    @EnvironmentObject private var store: BoardStore
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("gridGap") private var gridGapX = GridDefaults.gapX
    @AppStorage("gridGapY") private var gridGapY = GridDefaults.gapY
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("useCustomBackground") private var useCustomBackground = false
    @AppStorage("backgroundColor") private var backgroundColor = Theme.defaultBackground
    @AppStorage("appearance") private var appearance = Appearance.auto.rawValue
    @AppStorage("glowLight") private var glowLight = false
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.gradientKey) private var gradient = false
    @AppStorage(GlowPalette.monoKey) private var mono = false
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity

    private static let layout = GridLayout(columns: 4, rows: 2)
    private var isGlow: Bool { uiStyle == UIStyle.glow.rawValue }

    /// 盤面の左上から 8 個（グループも含む）。空きマスは詰める。1 つも無ければ見本のアイコン
    private var items: [LaunchItem] {
        let placed = store.board.slots(for: orientation).sorted { $0.key < $1.key }.map(\.value)
        if !placed.isEmpty { return Array(placed.prefix(8)) }
        let samples = [("star.fill", "Star"), ("heart.fill", "Heart"), ("bolt.fill", "Bolt"), ("leaf.fill", "Leaf"),
                       ("moon.fill", "Moon"), ("music.note", "Music"), ("camera.fill", "Camera"), ("flashlight.on.fill", "Light")]
        return samples.map { LaunchItem(kind: .action, name: $0.1, symbol: $0.0) }
    }

    private var summary: String {
        if isGlow {
            let color: String
            if mono { color = "モノトーン" }
            else if gradient { color = "グラデ" }
            else { color = GlowPalette.presets.first { $0.hue == themeHue }?.name ?? "色相 \(Int(themeHue))°" }
            return "\(color) ・ \(glowLight ? "ライト" : "ダーク") ・ 光の強さ \(Int(intensity))"
        }
        let mode = Appearance(rawValue: appearance)?.title ?? "自動"
        return "標準 ・ \(mode)\(useCustomBackground ? " ・ 背景色を指定" : "")"
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let metrics = GridMetrics(size: geo.size, layout: Self.layout, showLabels: showLabels,
                                          gapX: min(gridGapX, 24), gapY: min(gridGapY, 16), iconScale: iconScale,
                                          labelSpacing: min(labelSpacing, 6), outerMargin: 12)
                ZStack {
                    if showGridLines { GridLines(metrics: metrics) }
                    let list = items
                    GridCells(metrics: metrics) { slot in
                        TileView(item: slot < list.count ? list[slot] : nil, metrics: metrics)
                    }
                    .foregroundStyle(.tint)
                }
            }
            .frame(height: showLabels ? 150 : 128)
            .background {
                if isGlow {
                    GlowBackground()
                } else {
                    useCustomBackground ? backgroundColor.color : Color(.systemBackground)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("プレビュー")
            .accessibilityValue(summary)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - グロー

/// 光の色: 色の種類（単色 / グラデ / モノトーン）、プリセット、色相の微調整、光の強さ
struct GlowColorSection: View {
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.gradientKey) private var gradient = false
    @AppStorage(GlowPalette.monoKey) private var mono = false
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity

    enum Kind: Int, CaseIterable, Identifiable {
        case solid, gradient, mono
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .solid: return "単色"
            case .gradient: return "グラデ"
            case .mono: return "モノトーン"
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(get: { mono ? .mono : gradient ? .gradient : .solid },
                set: { newKind in
                    switch newKind {
                    case .solid:
                        gradient = false
                        mono = false
                    case .gradient:
                        // グラデに切り替えたときは、アプリアイコンと同じ配色から始める
                        if !gradient || mono { themeHue = GlowPalette.gradientCenter }
                        gradient = true
                        mono = false
                    case .mono:
                        mono = true
                        gradient = false
                    }
                })
    }

    private var selectedPreset: GlowPalette.Preset? { GlowPalette.presets.first { $0.hue == themeHue } }

    var body: some View {
        Section("光の色") {
            Picker("色の種類", selection: kind) {
                ForEach(Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !mono && !gradient {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("プリセット", value: selectedPreset?.name ?? "カスタム")
                    HStack(spacing: 0) {
                        ForEach(GlowPalette.presets) { preset in
                            Button {
                                themeHue = preset.hue
                            } label: {
                                Circle()
                                    .fill(preset.swatch)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                                    }
                                    .padding(3)
                                    .overlay {
                                        if themeHue == preset.hue {
                                            Circle().strokeBorder(Color.primary, lineWidth: 2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(themeHue == preset.hue ? .isSelected : [])
                        }
                    }
                }
            }

            if !mono {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(gradient ? "色相（全体）" : "色相の微調整", value: "\(Int(themeHue))°")
                    HueSlider(hue: $themeHue, gradientPreview: gradient)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("光の強さ", value: "\(Int(intensity))")
                Slider(value: $intensity, in: 1...10, step: 1) {
                    Text("光の強さ")
                } minimumValueLabel: {
                    Text("弱い").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("強い").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 虹色のバーの上を動かして色相を選ぶ（つまみの位置で色が分かる）。VoiceOver では上下のスワイプで 10° ずつ変わる
struct HueSlider: View {
    @Binding var hue: Double
    /// グラデのときは、つまみにグラデの配色を出す
    var gradientPreview = false

    private static let spectrum: [Color] = stride(from: 0.0, through: 360.0, by: 30.0).map {
        Color(hue: $0 / 360, saturation: 0.85, brightness: 0.95)
    }

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 28
            let track = max(geo.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                    .padding(.horizontal, knob / 2)
                Circle()
                    .fill(gradientPreview
                          ? AnyShapeStyle(LinearGradient(colors: GlowPalette.gradientColors(hue),
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color(hue: hue / 360, saturation: 0.85, brightness: 0.95)))
                    .overlay { Circle().strokeBorder(Color.white, lineWidth: 3) }
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: CGFloat(hue / 360) * track)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let x = min(max(value.location.x - knob / 2, 0), track)
                hue = (Double(x / track) * 360).rounded()
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("色相")
        .accessibilityValue("\(Int(hue))度")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: hue = min(360, hue + 10)
            case .decrement: hue = max(0, hue - 10)
            @unknown default: break
            }
        }
    }
}

/// 動き: 傾きで光を動かす、動きの大きさ、アイコンの浮き上がり
struct GlowMotionSection: View {
    @AppStorage("glowMotion") private var glowMotion = true
    @AppStorage("glowMotionStrength") private var strength = 1.0
    @AppStorage("glowParallax") private var parallax = 8.0

    var body: some View {
        Section {
            Toggle("傾きで光を動かす", isOn: $glowMotion)
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("動きの大きさ", value: "\(Int((strength * 100).rounded()))%")
                Slider(value: $strength, in: 0.3...2, step: 0.1) {
                    Text("動きの大きさ")
                } minimumValueLabel: {
                    Text("小さい").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("大きい").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!glowMotion)
            .opacity(glowMotion ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("アイコンの浮き上がり", value: "\(Int(parallax)) pt")
                Slider(value: $parallax, in: 0...20, step: 1)
            }
            .disabled(!glowMotion)
            .opacity(glowMotion ? 1 : 0.4)
        } header: {
            Text("動き")
        } footer: {
            Text("オフにすると傾きを読まなくなり、電池の減りを抑えられます。")
        }
    }
}

// MARK: - 標準の色

/// 色の行: 名前、今の値、色の丸
struct ColorRow: View {
    let title: String
    let isOn: Bool
    let color: Color
    let offText: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(isOn ? "指定" : offText).foregroundStyle(.secondary)
            Circle()
                .fill(isOn ? AnyShapeStyle(color)
                           : AnyShapeStyle(LinearGradient(colors: [.white, .black], startPoint: .topLeading,
                                                          endPoint: .bottomTrailing)))
                .frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1) }
                .accessibilityHidden(true)
        }
    }
}

/// 色を指定する 1 つ下の画面（背景色 / UI の色）
struct ColorSettingPage: View {
    let title: String
    let toggleTitle: String
    @Binding var isOn: Bool
    @Binding var color: HSBColor
    let footer: String

    var body: some View {
        Form {
            Section {
                Toggle(toggleTitle, isOn: $isOn)
                if isOn { HSBEditor(color: $color) }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - サイズと余白

/// 列と行、大きさと間隔（1 つ下の画面）
struct SizeSettingsPage: View {
    @Binding var message: String?
    @EnvironmentObject private var store: BoardStore
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("gridGap") private var gridGapX = GridDefaults.gapX
    @AppStorage("gridGapY") private var gridGapY = GridDefaults.gapY
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @AppStorage("gridOffsetY") private var gridOffsetY = 0.0
    @AppStorage("dockSpacing") private var dockSpacing = GridDefaults.dockSpacing

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// 行・列は変更のたびに即反映。収まらなければ元のままにして知らせる（iPad の縦と横で共通）
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

    private var isDefault: Bool {
        iconScale == GridDefaults.iconScale && gridGapX == GridDefaults.gapX && gridGapY == GridDefaults.gapY
            && outerMargin == GridDefaults.outerMargin && gridOffsetY == 0
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: text)
            Slider(value: value, in: range, step: step) { Text(title) }
        }
    }

    var body: some View {
        Form {
            Section {
                Stepper("列: \(store.board.layout.columns)", value: layoutBinding(\.columns),
                        in: isPad ? Board.padColumns : 2...5)
                Stepper("行: \(store.board.layout.rows)", value: layoutBinding(\.rows),
                        in: isPad ? Board.padRows : 3...8)
            } header: {
                Text("列と行")
            } footer: {
                Text(isPad ? "縦画面と横画面で共通です。アイコンの並びは縦と横で別々に編集できます。グループの中も同じ列と行です。"
                           : "グループの中も同じ列と行です。")
            }

            Section {
                slider("アイコンの大きさ", value: $iconScale, in: 0.4...1, step: 0.05,
                       text: "\(Int((iconScale * 100).rounded()))%")
                slider("横の間隔", value: $gridGapX, in: 0...150, step: 1, text: "\(Int(gridGapX)) pt")
                slider("縦の間隔", value: $gridGapY, in: 0...150, step: 1, text: "\(Int(gridGapY)) pt")
                slider("外側の余白", value: $outerMargin, in: 0...60, step: 1, text: "\(Int(outerMargin)) pt")
                slider("上下の位置", value: $gridOffsetY, in: -200...200, step: 2,
                       text: gridOffsetY == 0 ? "中央" : "\(gridOffsetY > 0 ? "下へ" : "上へ") \(Int(abs(gridOffsetY))) pt")
            } header: {
                Text("大きさと間隔")
            } footer: {
                Text("アイコンはマスに収まる最大の大きさで表示されます。アプリ名を消すか、行や列を減らすと大きくなります。上下の位置は、上下に空いている分だけ動かせます。")
            }

            if DockBar.enabled {
                Section {
                    slider("ボタンの間隔", value: $dockSpacing, in: 0...150, step: 1, text: "\(Int(dockSpacing)) pt")
                } header: {
                    Text("下部の 3 つのボタン")
                }
            }

            Section {
                Button("初期値に戻す", role: .destructive) {
                    iconScale = GridDefaults.iconScale
                    gridGapX = GridDefaults.gapX
                    gridGapY = GridDefaults.gapY
                    outerMargin = GridDefaults.outerMargin
                    gridOffsetY = 0
                }
                .frame(maxWidth: .infinity)
                .disabled(isDefault)
            }
        }
        .navigationTitle("サイズと余白")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - アプリ名とグリッド線

/// アプリ名とグリッド線（1 つ下の画面）
struct LabelGridSettingsPage: View {
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("labelWeight") private var labelWeight = Theme.defaultWeight
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("gridLineOpacity") private var gridLineOpacity = 1.0
    @AppStorage("useCustomGridColor") private var useCustomGridColor = false
    @AppStorage("gridColor") private var gridColor = Theme.defaultGrid

    var body: some View {
        Form {
            Section("アプリ名") {
                Toggle("アプリ名を表示", isOn: $showLabels)
                if showLabels {
                    Picker("文字の太さ", selection: $labelWeight) {
                        ForEach(Theme.weights.indices, id: \.self) { Text(Theme.weights[$0].name).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("アイコンとの間隔", value: "\(Int(labelSpacing)) pt")
                        Slider(value: $labelSpacing, in: 0...24, step: 1) { Text("アイコンとの間隔") }
                    }
                }
            }
            Section {
                Toggle("グリッド線を表示", isOn: $showGridLines)
                if showGridLines {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("濃さ", value: "\(Int((gridLineOpacity * 100).rounded()))%")
                        Slider(value: $gridLineOpacity, in: 0.05...1, step: 0.05) { Text("濃さ") }
                    }
                    Toggle("線の色を指定", isOn: $useCustomGridColor)
                    if useCustomGridColor { HSBEditor(color: $gridColor) }
                }
            } header: {
                Text("グリッド線")
            } footer: {
                Text("色の指定がオフのときは、UI の色を薄くした線になります。")
            }
        }
        .navigationTitle("アプリ名とグリッド線")
        .navigationBarTitleDisplayMode(.inline)
    }
}

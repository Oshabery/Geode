import SwiftUI

/// グリッドの寸法計算。
/// アイコンの格子を表示領域の中央に置き、間隔の設定どおりに中央から外側へ広げる。
/// - 間隔 (gapX / gapY): 隣り合うアイコン同士の距離。設定値そのまま
/// - 外側の余白: 表示領域の端から一番外のアイコンまで最低限あける距離。アイコンの最大サイズを決める
/// アイコンは正方形なので、縦横のうち余裕のある方向では端までの距離が設定値より広くなる。
struct GridMetrics {
    let layout: GridLayout
    let tile: CGFloat          // アイコン 1 辺
    let labelHeight: CGFloat   // アイコン下の間隔 + アプリ名の高さ（非表示なら 0）
    let gapX: CGFloat          // 横方向のアイコン同士の間隔
    let gapY: CGFloat          // 縦方向のアイコン同士の間隔
    let marginX: CGFloat       // 表示領域の左右端から格子までの距離（中央寄せの結果）
    let marginY: CGFloat       // 表示領域の上下端から格子までの距離（中央寄せの結果）

    private static let minTile: CGFloat = 24

    /// - gapX / gapY: アイコン同士の間隔 (pt)
    /// - iconScale: 収まる最大サイズに対する倍率 (0.4...1)。小さくしても間隔は変えず、格子全体が中央に縮む
    /// - labelSpacing: アイコンとアプリ名の間隔 (pt)
    /// - outerMargin: 表示領域の端から最低限あける距離 (pt)
    /// - offsetY: 格子全体を上下にずらす量 (pt、+ で下)。空いている高さの分までしか動かない
    init(size: CGSize, layout: GridLayout, showLabels: Bool, gapX: Double, gapY: Double,
         iconScale: Double, labelSpacing: Double, outerMargin: Double, offsetY: Double = 0) {
        let cols = CGFloat(layout.columns), rows = CGFloat(layout.rows)
        self.layout = layout
        let label = showLabels ? GridDefaults.labelTextHeight + CGFloat(max(labelSpacing, 0)) : 0
        labelHeight = label
        let scale = CGFloat(min(max(iconScale, 0.4), 1))

        // 設定値が大きすぎて格子が領域からはみ出さないよう、外側の余白 → 間隔の順に上限をかける
        let minW = cols * Self.minTile, minH = rows * (Self.minTile + label)
        let mX = min(CGFloat(max(outerMargin, 0)), max((size.width - minW) / 2, 0))
        let mY = min(CGFloat(max(outerMargin, 0)), max((size.height - minH) / 2, 0))
        let gx = min(CGFloat(max(gapX, 0)), max((size.width - 2 * mX - minW) / max(cols - 1, 1), 0))
        let gy = min(CGFloat(max(gapY, 0)), max((size.height - 2 * mY - minH) / max(rows - 1, 1), 0))

        let byWidth = (size.width - 2 * mX - (cols - 1) * gx) / cols
        let byHeight = (size.height - 2 * mY - (rows - 1) * gy) / rows - label
        let side = max(min(byWidth, byHeight) * scale, Self.minTile)
        tile = side
        self.gapX = gx      // 引数と同名なので self. が必要
        self.gapY = gy
        // 格子を中央に置く
        marginX = (size.width - cols * side - (cols - 1) * gx) / 2
        let centeredY = (size.height - rows * (side + label) - (rows - 1) * gy) / 2
        // 上下にずらす。格子が表示領域からはみ出さない（タッチが届かなくならない）範囲まで
        let room = max(centeredY - gy / 2, 0)
        marginY = centeredY + min(max(CGFloat(offsetY), -room), room)
    }

    var cellSize: CGSize { CGSize(width: tile, height: tile + labelHeight) }

    /// 格子全体（各アイコンの周りに間隔の半分ずつを含めた「ボックス」の集まり）
    var latticeRect: CGRect {
        CGRect(x: marginX - gapX / 2, y: marginY - gapY / 2,
               width: CGFloat(layout.columns) * (tile + gapX),
               height: CGFloat(layout.rows) * (cellSize.height + gapY))
    }

    func center(_ slot: Int) -> CGPoint {
        let c = CGFloat(slot % layout.columns), r = CGFloat(slot / layout.columns)
        return CGPoint(x: marginX + c * (tile + gapX) + tile / 2,
                       y: marginY + r * (cellSize.height + gapY) + cellSize.height / 2)
    }

    /// 格子の外側でも、この距離までは一番近いマスに当たったとみなす (pt)。
    /// 外周のアイコンは、外側に間隔の半分しか当たり判定が無く、指が少しずれると反応しなかったため
    static let edgeHitSlop: CGFloat = 24

    /// 座標 → スロット番号。格子の外（何も無い余白）は nil。ただし外周から edgeHitSlop までは近いマスに当てる
    func slot(at p: CGPoint) -> Int? {
        let rect = latticeRect
        guard rect.insetBy(dx: -Self.edgeHitSlop, dy: -Self.edgeHitSlop).contains(p) else { return nil }
        let c = Int(((p.x - rect.minX) / (tile + gapX)).rounded(.down))
        let r = Int(((p.y - rect.minY) / (cellSize.height + gapY)).rounded(.down))
        return min(max(r, 0), layout.rows - 1) * layout.columns + min(max(c, 0), layout.columns - 1)
    }
}

enum GridDefaults {
    static let gapX: Double = 12
    static let gapY: Double = 12
    static let iconScale: Double = 1
    static let labelSpacing: Double = 8
    static let labelTextHeight: CGFloat = 18
    static let outerMargin: Double = 12
    static let dockSpacing: Double = 48
}

struct GridCells<Cell: View>: View {
    let metrics: GridMetrics
    /// マスの中身の識別子（指定すると、配置が変わったときに同じアイコンが新しい位置へ動いて見える）。
    /// 指定しなければマスの番号で識別する
    var itemID: ((Int) -> AnyHashable)? = nil
    @ViewBuilder let cell: (Int) -> Cell

    private struct Entry: Identifiable {
        let id: AnyHashable
        let slot: Int
    }

    /// ForEach の識別子に中身の ID を使うことで、同じアイテムが別のマスへ移ったときに「移動」としてアニメーションする
    private var entries: [Entry] {
        (0..<metrics.layout.capacity).map { Entry(id: itemID?($0) ?? AnyHashable($0), slot: $0) }
    }

    var body: some View {
        ZStack {
            Color.clear
            ForEach(entries) { entry in
                cell(entry.slot)
                    .frame(width: metrics.cellSize.width, height: metrics.cellSize.height, alignment: .top)
                    .position(metrics.center(entry.slot))
            }
        }
    }
}

/// 通知バッジ: アイコンの周りを囲む、薄く透き通った赤いガラスの縁。
/// 周りへの発光はほとんど付けない（縁のすぐ外にごく薄い赤を 1 本だけ）
struct BadgeRing: View {
    /// 通知バッジを使うか。ユーザーの指定で外している（true に戻せば元どおり。
    /// オフの間は、起動時にバッジを外す処理も動かさないので、各アクションの showBadge はそのまま残る）
    static let enabled = false

    let size: CGFloat

    var body: some View {
        let width = max(1, size * 0.028)
        let red = Color(uiColor: .systemRed)
        let ring = iconShape(size + width * 2)
        ZStack {
            // 縁のすぐ外のごく薄い赤（発光というより、縁の輪郭をやわらげる程度）
            iconShape(size + width * 3)
                .stroke(red.opacity(0.08), lineWidth: width)
            // 透明感のある赤い縁: 全体を半透明にし、上は白っぽく、下は少しだけ赤を濃く
            ring.strokeBorder(LinearGradient(colors: [red.opacity(0.25), red.opacity(0.45), red.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: width)
            // ガラスの映り込み: 上側に細い白
            ring.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)],
                                             startPoint: .top, endPoint: .center),
                              lineWidth: max(0.5, width * 0.4))
        }
        .frame(width: size + width * 2, height: size + width * 2)
        .accessibilityLabel("通知バッジ")
        .allowsHitTesting(false)
    }
}

/// アイコンとアイコンの間（余白の中央）に引く区切り線
struct GridLines: View {
    let metrics: GridMetrics
    @AppStorage("useCustomGridColor") private var useCustomGridColor = false
    @AppStorage("gridColor") private var gridColor = Theme.defaultGrid
    /// グリッド線の濃さ（0...1）。1 でこれまでと同じ
    @AppStorage("gridLineOpacity") private var lineOpacity = 1.0

    var body: some View {
        if useCustomGridColor {
            path.stroke(gridColor.color.opacity(lineOpacity), lineWidth: 1).allowsHitTesting(false)
        } else {
            path.stroke(.tint.opacity(0.35 * lineOpacity), lineWidth: 1).allowsHitTesting(false)
        }
    }

    /// アイコン同士を区切る線。ボックスはすべて同じ大きさで、アイコンはその中央に来る。
    /// 一番外側の枠線は引かない
    private var path: Path {
        Path { p in
            let rect = metrics.latticeRect
            let stepX = metrics.tile + metrics.gapX
            let stepY = metrics.cellSize.height + metrics.gapY
            for c in 1..<max(metrics.layout.columns, 2) {
                let x = rect.minX + CGFloat(c) * stepX
                p.move(to: CGPoint(x: x, y: rect.minY))
                p.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for r in 1..<max(metrics.layout.rows, 2) {
                let y = rect.minY + CGFloat(r) * stepY
                p.move(to: CGPoint(x: rect.minX, y: y))
                p.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }
}

/// 1 マス分の表示（アイコン + 任意でアプリ名）
struct TileView: View {
    let item: LaunchItem?
    let metrics: GridMetrics
    var highlighted = false
    /// オン / オフのスイッチの状態。true ならアイコンをネガポジ反転する（編集モードでは渡さない）
    var switchState: Bool? = nil
    /// グローで傾けたとき、背景との視差でずらすか（通常モードのグリッドだけ。編集中は動かさない）
    var parallax = false
    @AppStorage("labelWeight") private var labelWeight = Theme.defaultWeight
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let item {
            let isGlow = uiStyle == UIStyle.glow.rawValue
            VStack(spacing: 0) {
                Group {
                    if isGlow {
                        GlowIcon(item: item, size: metrics.tile, isOn: switchState ?? false)
                    } else {
                        ItemIcon(item: item, size: metrics.tile, isOn: switchState ?? false)
                    }
                }
                .overlay(iconShape(metrics.tile).fill(Color.white.opacity(highlighted ? 0.3 : 0)))
                .overlay {
                    if BadgeRing.enabled && item.showBadge == true {
                        BadgeRing(size: metrics.tile)
                    }
                }
                .scaleEffect(highlighted ? 1.06 : 1)
                if metrics.labelHeight > 0 {
                    if isGlow {
                        label(item).foregroundStyle(scheme == .light ? Color.black.opacity(0.72) : Color.white.opacity(0.85))
                    } else {
                        label(item)
                    }
                }
            }
            .modifier(GlowParallax(enabled: isGlow && parallax))
        } else {
            Color.clear
        }
    }

    private func label(_ item: LaunchItem) -> some View {
        Text(item.name)
            .font(.caption.weight(Theme.weight(labelWeight)))
            .lineLimit(1)
            .frame(width: metrics.tile, height: metrics.labelHeight, alignment: .bottom)
    }
}

/// グリッドのタッチを UIKit で直接受け取る透明なビュー。
/// 指を置いた瞬間（touchesBegan）に通知するので、動かさなくてもすぐ反応する。取り消し（touchesCancelled）も届く
struct TouchSurface: UIViewRepresentable {
    var began: (CGPoint) -> Void
    var moved: (_ point: CGPoint, _ start: CGPoint) -> Void
    var ended: (CGPoint) -> Void
    var cancelled: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.began = began
        view.moved = moved
        view.ended = ended
        view.cancelled = cancelled
    }

    final class TouchView: UIView {
        var began: ((CGPoint) -> Void)?
        var moved: ((CGPoint, CGPoint) -> Void)?
        var ended: ((CGPoint) -> Void)?
        var cancelled: (() -> Void)?
        private weak var tracked: UITouch?
        private var start: CGPoint = .zero

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard tracked == nil, let touch = touches.first else { return }
            tracked = touch
            start = touch.location(in: self)
            began?(start)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = tracked, touches.contains(touch) else { return }
            moved?(touch.location(in: self), start)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = tracked, touches.contains(touch) else { return }
            tracked = nil
            ended?(touch.location(in: self))
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = tracked, touches.contains(touch) else { return }
            tracked = nil
            cancelled?()
        }
    }
}

/// 1 回のタッチの始まりと終わり。
/// 以前は「触れている」フラグだけで判断していたため、タッチが取り消されて終わりの通知が来ないと
/// フラグが立ったままになり、次にグループを長押ししても開かないことがあった
struct TouchSession {
    private(set) var isActive = false
    private var start: CGPoint?

    /// 新しいタッチの始まりなら true。同じタッチの途中なら false
    mutating func begin(at point: CGPoint) -> Bool {
        if isActive, start == point { return false }
        isActive = true
        start = point
        return true
    }

    mutating func end() {
        isActive = false
        start = nil
    }
}

/// グループの中身が出てくる順番を決める距離のルール（テストできるよう独立させている）
enum GroupEntrance {
    /// これより遠いものは、すべてこの距離として扱う
    static let maxDistance = 3.0

    /// グループのマスからの距離。上下左右の 1 マスを 1、斜めの 1 マスを 1.5 として数え、3 で頭打ち
    static func distance(_ slot: Int, from origin: Int, columns: Int) -> Double {
        let dx = abs(slot % columns - origin % columns)
        let dy = abs(slot / columns - origin / columns)
        let diagonal = min(dx, dy)
        let straight = max(dx, dy) - diagonal
        return min(Double(diagonal) * 1.5 + Double(straight), maxDistance)
    }
}

/// グループの中身のアイコン 1 つ分の出方。表示された瞬間に、ずらした位置・少し小さい・透明な状態から
/// 遅れて定位置へ動く（親ごと挿入されると子の transition は効かないため、状態で動かす）
struct GroupChildAppear<Content: View>: View {
    let delay: Double
    let from: CGSize
    let animation: Animation
    let content: Content
    @State private var shown = false

    init(delay: Double, from: CGSize, animation: Animation, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.from = from
        self.animation = animation
        self.content = content()
    }

    var body: some View {
        content
            .offset(shown ? .zero : from)
            .scaleEffect(shown ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(animation.delay(delay)) { shown = true }
            }
    }
}

/// グループ階層の背景。グリッドの枠で切れないよう、画面全体（上のボタン・下のボタン・画面の端まで）を覆う。
/// 触っても反応しない（下のボタンなどの操作を邪魔しない）
struct GroupBackdrop: View {
    /// グリッドの画面上の位置
    let gridFrame: CGRect
    /// 押しているグループの中心（グリッド内の座標）
    let focus: CGPoint?
    /// 明るい背景にする（グローのライト）。それ以外はこれまでどおり暗いすりガラス
    var light = false
    /// iPad の回すキャンバスの範囲（グリッド内の座標）。あればキャンバス全体を覆う。
    /// 無ければ（iPhone）これまでどおり画面全体を覆う
    var canvas: CGRect? = nil

    var body: some View {
        let screen = UIScreen.main.bounds.size
        // 覆う範囲（グリッド内の座標）。回したキャンバスの中では画面の座標が使えないので、キャンバスの範囲を使う
        let area = canvas ?? CGRect(x: -gridFrame.minX, y: -gridFrame.minY, width: screen.width, height: screen.height)
        // 明るい部分の中心（覆う範囲の中の座標）。分からなければ中央
        let center = focus.map { CGPoint(x: $0.x - area.minX, y: $0.y - area.minY) }
            ?? CGPoint(x: area.width / 2, y: area.height / 2)
        ZStack {
            if light {
                // 明るいすりガラス。中心は透けて、離れるほど白い霧がかかる
                Rectangle().fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                Rectangle()
                    .fill(RadialGradient(colors: [.white.opacity(0.1), .white.opacity(0.6)],
                                         center: .center, startRadius: 50, endRadius: 460))
                    .frame(width: 2400, height: 2400)
                    .position(center)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                // 中心は薄く、離れるほど暗い。どこを中心にしても画面を覆える大きさで描く
                Rectangle()
                    .fill(RadialGradient(colors: [.black.opacity(0.08), .black.opacity(0.5)],
                                         center: .center, startRadius: 50, endRadius: 460))
                    .frame(width: 2400, height: 2400)
                    .position(center)
            }
        }
        .frame(width: area.width, height: area.height)
        .clipped()
        // グリッドの座標の中で、覆う範囲にぴったり重なる位置へ置く
        .position(x: area.midX, y: area.midY)
        .allowsHitTesting(false)
    }
}

/// 通常モード。
/// - アクション: タップで URL スキームを開く
/// - グループ: 触れている間だけ 1 レイヤー上へ中身を展開。アプリの上まで指を滑らせて離すと起動。
///   その場や空きマスで離すとホーム階層に戻る。
struct LauncherGridView: View {
    /// どちらの向きの配置を表示・操作するか（iPad の横画面は別の配置）
    let orientation: BoardOrientation
    @EnvironmentObject private var store: BoardStore
    /// iPad の回したキャンバスの大きさ（iPhone では nil）
    @Environment(\.geodeCanvasSize) private var canvasSize
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("gridGap") private var gridGapX = GridDefaults.gapX
    @AppStorage("gridGapY") private var gridGapY = GridDefaults.gapY
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @AppStorage("gridOffsetY") private var gridOffsetY = 0.0
    @State private var openGroup: LaunchItem?
    @State private var groupSlot: Int?
    @State private var highlighted: Int?
    @State private var touchStart: Int?
    /// いまのタッチ。新しいタッチの始まりを、指を置いた位置で見分ける
    @State private var session = TouchSession()
    /// グループを開いたときの触覚。毎回作ると触覚エンジンの起動待ちで遅れるので、作り置きして準備しておく
    @State private var openHaptic = UIImpactFeedbackGenerator(style: .rigid)
    @AppStorage("uiStyle") private var uiStyleRaw = UIStyle.standard.rawValue
    @Environment(\.colorScheme) private var currentScheme
    /// グループ階層の中身の配色。背景が暗いので、グローではダークに固定する（標準はこれまでどおり）
    private var isGlowLight: Bool { uiStyleRaw == UIStyle.glow.rawValue && currentScheme == .light }
    /// グループ階層の中身の配色。グローのライトでは背景も明るいので、ライトのまま描く
    private var groupScheme: ColorScheme { currentScheme }

    /// グループ階層に入るときの動き。出だしは速く（押した瞬間にほぼ見える）、
    /// 終わりにかけて長くゆっくり落ち着く（余韻）
    private static let openAnimation = Animation.timingCurve(0.2, 0.75, 0.1, 1.0, duration: 0.3)
    /// 中身が出てくるときの、距離 1 あたりの遅れ（秒）と移動量（マスの間隔に対する割合）
    private static let entranceDelayPerUnit = 0.035
    private static let entranceTravelPerUnit: CGFloat = 0.09

    /// 中身のアイコンの出方: 遅れと、動き出す位置（グループのマスの方向へずらした位置）
    private func childEntrance(_ slot: Int, metrics: GridMetrics) -> (delay: Double, from: CGSize) {
        guard let origin = groupSlot else { return (0, .zero) }
        let distance = GroupEntrance.distance(slot, from: origin, columns: metrics.layout.columns)
        let a = metrics.center(origin), b = metrics.center(slot)
        let vx = b.x - a.x, vy = b.y - a.y
        let length = max(sqrt(vx * vx + vy * vy), 1)
        let step = ((metrics.tile + metrics.gapX) + (metrics.cellSize.height + metrics.gapY)) / 2
        let travel = step * Self.entranceTravelPerUnit * CGFloat(distance)
        // 隣のマス（距離 1）は遅れなしで出だしを速く保ち、それより遠いものだけ遅らせる
        return (max(distance - 1, 0) * Self.entranceDelayPerUnit,
                CGSize(width: -vx / length * travel, height: -vy / length * travel))
    }

    /// 戻るときは短く、すっと消える
    private static let closeDuration = 0.22
    private static let closeAnimation = Animation.timingCurve(0.3, 0.0, 0.2, 1.0, duration: closeDuration)

    /// 表示している向きの配置。表示・タッチ・ウィジェットから開くグループのすべてでこれを使う
    private var pageSlots: [Int: LaunchItem] { store.board.slots(for: orientation) }

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(size: geo.size, layout: store.board.layout(for: orientation), showLabels: showLabels,
                                      gapX: gridGapX, gapY: gridGapY, iconScale: iconScale,
                                      labelSpacing: labelSpacing, outerMargin: outerMargin, offsetY: gridOffsetY)
            ZStack {
                if showGridLines { GridLines(metrics: metrics) }
                // iPad を回して縦と横の配置が切り替わるとき、同じアイコンが新しい位置へ動いて見えるよう、中身で識別する
                GridCells(metrics: metrics, itemID: { slot in
                    pageSlots[slot].map { AnyHashable($0.id) } ?? AnyHashable("empty-\(slot)")
                }) { slot in
                    TileView(item: pageSlots[slot], metrics: metrics,
                             highlighted: openGroup == nil && highlighted == slot,
                             switchState: pageSlots[slot].flatMap(store.switchState(for:)),
                             parallax: true)
                }
                .foregroundStyle(.tint)

                if let group = openGroup {
                    // グループ展開時の背景: 画面全体を覆う暗いすりガラス。
                    // 押しているグループの周りだけ少し明るくして、1 枚上の階層に上がった感じを出す
                    GroupBackdrop(gridFrame: geo.frame(in: .global),
                                  focus: groupSlot.map { metrics.center($0) },
                                  light: isGlowLight,
                                  canvas: canvasSize.map { size in
                                      // キャンバスの原点（グリッドの座標）と大きさ
                                      let f = geo.frame(in: .named(CanvasRotation.coordinateSpace))
                                      return CGRect(x: -f.minX, y: -f.minY, width: size.width, height: size.height)
                                  })
                        .transition(.opacity)
                        .zIndex(1)
                    // グループの中身: グループのマスから外へ広がるように、近いものから順に出てくる。
                    // 遠いものほど少し遅れ、少し長い距離を動く。消えるときは全体が薄くなるだけ
                    GridCells(metrics: metrics) { slot in
                        if slot == groupSlot {
                            Color.clear
                        } else {
                            let entrance = childEntrance(slot, metrics: metrics)
                            GroupChildAppear(delay: entrance.delay, from: entrance.from, animation: Self.openAnimation) {
                                TileView(item: group.children[slot], metrics: metrics, highlighted: highlighted == slot,
                                         switchState: group.children[slot].flatMap(store.switchState(for:)),
                                         parallax: true)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, groupScheme)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(2)
                    // 押しているグループ自身は指の下で縮まないよう、別の層で薄く出すだけ
                    GridCells(metrics: metrics) { slot in
                        if slot == groupSlot {
                            TileView(item: group, metrics: metrics, highlighted: true, parallax: true)
                        } else {
                            Color.clear
                        }
                    }
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, groupScheme)
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            // タッチは UIKit で直接受け取る。SwiftUI のジェスチャーを通すと、指を置いたまま動かさないときに
            // 最初の通知が遅れることがあり、グループが開くまで時間がかかっていた
            .overlay {
                TouchSurface(
                    began: { point in touchMoved(metrics.slot(at: point), startedAt: point) },
                    moved: { point, start in touchMoved(metrics.slot(at: point), startedAt: start) },
                    ended: { point in touchEnded(metrics.slot(at: point)) },
                    cancelled: { touchCancelled() }
                )
            }
            .animation(openGroup != nil ? Self.openAnimation : Self.closeAnimation, value: openGroup?.id)
            // 縦と横の配置が切り替わるとき、アイコンをなめらかに新しい位置へ動かす
            .animation(.spring(duration: 0.45, bounce: 0.1), value: orientation)
            .animation(.easeOut(duration: 0.1), value: highlighted)
        }
        // 開いている間は ContentView がこのビューを最前面に描く（背景が下のボタンも覆えるように）
        .onChange(of: openGroup?.id) { _, id in
            if id != nil {
                store.groupLayerOpen = true
            } else {
                // 背景が消えきるまでは最前面のままにする（途中で下のボタンが手前に飛び出さないように）
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration + 0.05) {
                    if openGroup == nil { store.groupLayerOpen = false }
                }
            }
        }
        .onAppear { openHaptic.prepare() }
        .onDisappear { store.groupLayerOpen = false }
        .onAppear(perform: openRequestedGroup)
        .onChange(of: store.requestedGroup) { _, _ in openRequestedGroup() }
        // 向きが変わったら、開いているグループを閉じる（マスの位置が変わるため）
        .onChange(of: orientation) { _, _ in
            touchCancelled()
            if openGroup != nil { close() }
        }
    }

    private func touchMoved(_ slot: Int?, startedAt start: CGPoint) {
        // 前のタッチの終わりを受け取れなかった場合でも、置いた位置が変われば新しいタッチとして扱う
        if session.begin(at: start) {
            touchStart = slot
        }
        // 指が触れている間は、グループの上にある限りレイヤーを開く。
        // 置いた瞬間に少しずれていても、指がグループの上に来た時点で開く（開いた後は離すまで閉じない）
        if openGroup == nil, let slot, let item = pageSlots[slot], item.kind == .group {
            openGroup = item
            groupSlot = slot
            // グループ階層に入った合図: カチッとした硬めの触覚
            openHaptic.impactOccurred(intensity: 1.0)
            openHaptic.prepare()   // 次に備えて触覚の準備をしておく
        }
        if highlighted != slot {
            highlighted = slot
            if let slot, openGroup != nil, slot != groupSlot, openGroup?.children[slot] != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func touchEnded(_ slot: Int?) {
        defer { session.end(); touchStart = nil; highlighted = nil }
        if let group = openGroup {
            // 指を離したら必ず閉じる。アプリのあるマスの上で離したときだけ起動し、
            // グループ自身のマス、空きマス、格子の外ではホーム階層に戻るだけ。
            if let slot, slot != groupSlot, let child = group.children[slot] { store.launch(child) }
            close()
        } else if let slot, slot == touchStart, let item = pageSlots[slot], item.kind == .action {
            store.launch(item)
        }
    }

    /// タッチが取り消されたとき（通知センターを引いた、アプリが裏に回ったなど）。何も起動せずに元へ戻す
    private func touchCancelled() {
        guard session.isActive else { return }
        session.end()
        touchStart = nil
        highlighted = nil
        if openGroup != nil { close() }
    }

    private func close() {
        openGroup = nil
        groupSlot = nil
    }

    private func openRequestedGroup() {
        guard let id = store.requestedGroup else { return }
        store.requestedGroup = nil
        if let entry = pageSlots.first(where: { $0.value.id == id }) {
            openGroup = entry.value
            groupSlot = entry.key
        }
    }
}

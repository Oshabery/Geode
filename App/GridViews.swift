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
    init(size: CGSize, layout: GridLayout, showLabels: Bool, gapX: Double, gapY: Double,
         iconScale: Double, labelSpacing: Double, outerMargin: Double) {
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
        gapX = gx
        gapY = gy
        // 格子を中央に置く
        marginX = (size.width - cols * side - (cols - 1) * gx) / 2
        marginY = (size.height - rows * (side + label) - (rows - 1) * gy) / 2
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

    /// 座標 → スロット番号。格子の外（何も無い余白）は nil
    func slot(at p: CGPoint) -> Int? {
        let rect = latticeRect
        guard rect.contains(p) else { return nil }
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
}

struct GridCells<Cell: View>: View {
    let metrics: GridMetrics
    @ViewBuilder let cell: (Int) -> Cell

    var body: some View {
        ZStack {
            Color.clear
            ForEach(0..<metrics.layout.capacity, id: \.self) { slot in
                cell(slot)
                    .frame(width: metrics.cellSize.width, height: metrics.cellSize.height, alignment: .top)
                    .position(metrics.center(slot))
            }
        }
    }
}

/// アイコンとアイコンの間（余白の中央）に引く区切り線
struct GridLines: View {
    let metrics: GridMetrics
    @AppStorage("useCustomGridColor") private var useCustomGridColor = false
    @AppStorage("gridColor") private var gridColor = Theme.defaultGrid

    var body: some View {
        if useCustomGridColor {
            path.stroke(gridColor.color, lineWidth: 1).allowsHitTesting(false)
        } else {
            path.stroke(.tint.opacity(0.35), lineWidth: 1).allowsHitTesting(false)
        }
    }

    /// 各アイコンを同じ大きさのボックスで囲む線（外枠を含む）。アイコンは必ずボックスの中央に来る
    private var path: Path {
        Path { p in
            let rect = metrics.latticeRect
            let stepX = metrics.tile + metrics.gapX
            let stepY = metrics.cellSize.height + metrics.gapY
            for c in 0...metrics.layout.columns {
                let x = rect.minX + CGFloat(c) * stepX
                p.move(to: CGPoint(x: x, y: rect.minY))
                p.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for r in 0...metrics.layout.rows {
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
    @AppStorage("glassIcons") private var glassIcons = false
    @AppStorage("labelWeight") private var labelWeight = Theme.defaultWeight

    var body: some View {
        if let item {
            VStack(spacing: 0) {
                ItemIcon(item: item, size: metrics.tile, glass: glassIcons)
                    .overlay(iconShape(metrics.tile).fill(Color.white.opacity(highlighted ? 0.3 : 0)))
                    .scaleEffect(highlighted ? 1.06 : 1)
                if metrics.labelHeight > 0 {
                    Text(item.name)
                        .font(.caption.weight(Theme.weight(labelWeight)))
                        .lineLimit(1)
                        .frame(width: metrics.tile, height: metrics.labelHeight, alignment: .bottom)
                }
            }
        } else {
            Color.clear
        }
    }
}

/// 通常モード。
/// - アクション: タップで URL スキームを開く
/// - グループ: 触れている間だけ 1 レイヤー上へ中身を展開。アプリの上まで指を滑らせて離すと起動。
///   その場や空きマスで離すとホーム階層に戻る。
struct LauncherGridView: View {
    @EnvironmentObject private var store: BoardStore
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("gridGap") private var gridGapX = GridDefaults.gapX
    @AppStorage("gridGapY") private var gridGapY = GridDefaults.gapY
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @State private var openGroup: LaunchItem?
    @State private var groupSlot: Int?
    @State private var highlighted: Int?
    @State private var touchStart: Int?
    /// 指が触れている間 true（最初のイベントの判定用。触れた場所が格子の外だと touchStart は nil になる）
    @State private var touching = false

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(size: geo.size, layout: store.board.layout, showLabels: showLabels,
                                      gapX: gridGapX, gapY: gridGapY, iconScale: iconScale,
                                      labelSpacing: labelSpacing, outerMargin: outerMargin)
            ZStack {
                if showGridLines { GridLines(metrics: metrics) }
                GridCells(metrics: metrics) { slot in
                    TileView(item: store.board.slots[slot], metrics: metrics,
                             highlighted: openGroup == nil && highlighted == slot)
                }
                .foregroundStyle(.tint)

                if let group = openGroup {
                    // グループ展開時の背景: 暗いすりガラス
                    Rectangle().fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Color.black.opacity(0.35))
                        .ignoresSafeArea()
                    GridCells(metrics: metrics) { slot in
                        if slot == groupSlot {
                            TileView(item: group, metrics: metrics, highlighted: true)
                        } else {
                            TileView(item: group.children[slot], metrics: metrics, highlighted: highlighted == slot)
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { touchMoved(metrics.slot(at: $0.location)) }
                    .onEnded { touchEnded(metrics.slot(at: $0.location)) }
            )
            .animation(.easeOut(duration: 0.06), value: openGroup?.id)
            .animation(.easeOut(duration: 0.1), value: highlighted)
        }
        .onAppear(perform: openRequestedGroup)
        .onChange(of: store.requestedGroup) { _, _ in openRequestedGroup() }
    }

    private func touchMoved(_ slot: Int?) {
        if !touching {
            touching = true
            touchStart = slot
            if openGroup == nil, let slot, let item = store.board.slots[slot], item.kind == .group {
                openGroup = item
                groupSlot = slot
                // グループ階層に入った合図: カチッとした硬めの触覚
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
            }
        }
        if highlighted != slot {
            highlighted = slot
            if let slot, openGroup != nil, slot != groupSlot, openGroup?.children[slot] != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func touchEnded(_ slot: Int?) {
        defer { touching = false; touchStart = nil; highlighted = nil }
        if let group = openGroup {
            // 指を離したら必ず閉じる。アプリのあるマスの上で離したときだけ起動し、
            // グループ自身のマス、空きマス、格子の外ではホーム階層に戻るだけ。
            if let slot, slot != groupSlot, let child = group.children[slot] { store.launch(child) }
            close()
        } else if let slot, slot == touchStart, let item = store.board.slots[slot], item.kind == .action {
            store.launch(item)
        }
    }

    private func close() {
        openGroup = nil
        groupSlot = nil
    }

    private func openRequestedGroup() {
        guard let id = store.requestedGroup else { return }
        store.requestedGroup = nil
        if let entry = store.board.slots.first(where: { $0.value.id == id }) {
            openGroup = entry.value
            groupSlot = entry.key
        }
    }
}

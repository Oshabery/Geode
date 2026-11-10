import SwiftUI

/// グリッドの寸法計算。
/// タイルは正方形で、タイル間の余白と画面端の余白が（縦横それぞれ）同じピクセル数になるよう配置する。
struct GridMetrics {
    let layout: GridLayout
    let tile: CGFloat          // アイコン 1 辺
    let labelHeight: CGFloat   // アプリ名の高さ（非表示なら 0）
    let gapX: CGFloat          // 横方向の余白（タイル間 = 画面端）
    let gapY: CGFloat          // 縦方向の余白（タイル間 = 画面端）

    /// - gap: 最小余白 (pt)。アイコンはこの余白を確保したうえで収まる最大サイズになる
    /// - iconScale: その最大サイズに対する倍率 (0.4...1)。小さくした分は余白へ均等に配分される
    init(size: CGSize, layout: GridLayout, showLabels: Bool, gap: Double, iconScale: Double) {
        let minGap = CGFloat(gap)
        let cols = CGFloat(layout.columns), rows = CGFloat(layout.rows)
        self.layout = layout
        labelHeight = showLabels ? 18 : 0
        let byWidth = (size.width - (cols + 1) * minGap) / cols
        let byHeight = (size.height - (rows + 1) * minGap) / rows - labelHeight
        tile = max(min(byWidth, byHeight) * CGFloat(min(max(iconScale, 0.4), 1)), 10)
        gapX = (size.width - cols * tile) / (cols + 1)
        gapY = (size.height - rows * (tile + labelHeight)) / (rows + 1)
    }

    var cellSize: CGSize { CGSize(width: tile, height: tile + labelHeight) }

    func center(_ slot: Int) -> CGPoint {
        let c = CGFloat(slot % layout.columns), r = CGFloat(slot / layout.columns)
        return CGPoint(x: gapX + c * (tile + gapX) + tile / 2,
                       y: gapY + r * (cellSize.height + gapY) + cellSize.height / 2)
    }

    /// 座標 → スロット番号（余白部分は近い方のタイルに寄せる）
    func slot(at p: CGPoint) -> Int {
        let c = Int(((p.x - gapX / 2) / (tile + gapX)).rounded(.down))
        let r = Int(((p.y - gapY / 2) / (cellSize.height + gapY)).rounded(.down))
        return min(max(r, 0), layout.rows - 1) * layout.columns + min(max(c, 0), layout.columns - 1)
    }
}

enum GridDefaults {
    static let gap: Double = 12
    static let iconScale: Double = 1
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

    var body: some View {
        Path { p in
            let cols = metrics.layout.columns, rows = metrics.layout.rows
            let stepX = metrics.tile + metrics.gapX
            let stepY = metrics.cellSize.height + metrics.gapY
            let width = CGFloat(cols) * stepX + metrics.gapX
            let height = CGFloat(rows) * stepY + metrics.gapY
            for c in 1..<max(cols, 2) {
                let x = CGFloat(c) * stepX + metrics.gapX / 2
                p.move(to: CGPoint(x: x, y: metrics.gapY / 2))
                p.addLine(to: CGPoint(x: x, y: height - metrics.gapY / 2))
            }
            for r in 1..<max(rows, 2) {
                let y = CGFloat(r) * stepY + metrics.gapY / 2
                p.move(to: CGPoint(x: metrics.gapX / 2, y: y))
                p.addLine(to: CGPoint(x: width - metrics.gapX / 2, y: y))
            }
        }
        .stroke(.tint.opacity(0.35), lineWidth: 1)
        .allowsHitTesting(false)
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
                        .frame(width: metrics.tile, height: metrics.labelHeight)
                }
            }
        } else {
            Color.clear
        }
    }
}

/// 通常モード。
/// - アクション: タップで URL スキームを開く
/// - グループ: 触れた瞬間に 1 レイヤー上へ中身を展開。指を滑らせて離すと起動。
///   その場で離すと展開したままになり、次のタップで選択。
struct LauncherGridView: View {
    @EnvironmentObject private var store: BoardStore
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("gridGap") private var gridGap = GridDefaults.gap
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("showGridLines") private var showGridLines = true
    @State private var openGroup: LaunchItem?
    @State private var groupSlot: Int?
    @State private var highlighted: Int?
    @State private var touchStart: Int?
    @State private var openedThisTouch = false

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(size: geo.size, layout: store.board.layout, showLabels: showLabels,
                                      gap: gridGap, iconScale: iconScale)
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
            .animation(.easeOut(duration: 0.12), value: openGroup?.id)
            .animation(.easeOut(duration: 0.1), value: highlighted)
        }
        .onAppear(perform: openRequestedGroup)
        .onChange(of: store.requestedGroup) { _, _ in openRequestedGroup() }
    }

    private func touchMoved(_ slot: Int) {
        if touchStart == nil {
            touchStart = slot
            openedThisTouch = false
            if openGroup == nil, let item = store.board.slots[slot], item.kind == .group {
                openGroup = item
                groupSlot = slot
                openedThisTouch = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        if highlighted != slot {
            highlighted = slot
            if openGroup != nil, slot != groupSlot, openGroup?.children[slot] != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    private func touchEnded(_ slot: Int) {
        defer { touchStart = nil; highlighted = nil }
        if let group = openGroup {
            if slot == groupSlot {
                if !openedThisTouch { close() }      // 展開中にグループをもう一度タップ → 閉じる
            } else {
                if let child = group.children[slot] { store.launch(child) }
                close()
            }
        } else if slot == touchStart, let item = store.board.slots[slot], item.kind == .action {
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

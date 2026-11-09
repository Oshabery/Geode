import SwiftUI

/// rows × columns の等分グリッド。slot = row * columns + column
struct GridCells<Cell: View>: View {
    let layout: GridLayout
    @ViewBuilder let cell: (Int) -> Cell

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<layout.rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<layout.columns, id: \.self) { c in
                        cell(r * layout.columns + c)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

func slotIndex(at point: CGPoint, in size: CGSize, layout: GridLayout) -> Int {
    let w = size.width / CGFloat(layout.columns)
    let h = size.height / CGFloat(layout.rows)
    let c = min(max(Int(point.x / max(w, 1)), 0), layout.columns - 1)
    let r = min(max(Int(point.y / max(h, 1)), 0), layout.rows - 1)
    return r * layout.columns + c
}

struct CellView: View {
    let item: LaunchItem?
    var highlighted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(highlighted ? Color.accentColor.opacity(0.35) : Color.clear)
                if let item {
                    VStack(spacing: 6) {
                        ItemIcon(item: item, size: min(geo.size.width, geo.size.height) * 0.5)
                        Text(item.name)
                            .font(.footnote)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.25), lineWidth: 0.5))
        }
    }
}

/// 通常モード。
/// - アクション: タップで URL スキームを開く
/// - グループ: 触れた瞬間に 1 レイヤー上へ中身を展開。指を滑らせて離すと起動。
///   その場で離すと展開したままになり、次のタップで選択。
struct LaunchGridView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var openGroup: LaunchItem?
    @State private var groupSlot: Int?
    @State private var highlighted: Int?
    @State private var touchStart: Int?
    @State private var openedThisTouch = false

    var body: some View {
        GeometryReader { geo in
            let layout = store.board.layout
            ZStack {
                GridCells(layout: layout) { slot in
                    CellView(item: store.board.slots[slot],
                             highlighted: openGroup == nil && highlighted == slot)
                }
                .foregroundStyle(Color.accentColor)

                if let group = openGroup {
                    Color(white: 0.12).opacity(0.97)
                    GridCells(layout: layout) { slot in
                        if slot == groupSlot {
                            CellView(item: group, highlighted: true)
                        } else {
                            CellView(item: group.children[slot], highlighted: highlighted == slot)
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { touchMoved(slotIndex(at: $0.location, in: geo.size, layout: layout)) }
                    .onEnded { touchEnded(slotIndex(at: $0.location, in: geo.size, layout: layout)) }
            )
            .animation(.easeOut(duration: 0.12), value: openGroup?.id)
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

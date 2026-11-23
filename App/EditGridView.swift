import SwiftUI

struct EditorTarget: Identifiable {
    let id = UUID()
    let slot: Int
    let item: LaunchItem
}

/// 編集モードのグリッド。＋で追加、×で削除、タップで編集、ドラッグで移動/入れ替え。
/// ホーム階層とグループ内の両方で使う。
struct EditGridView: View {
    @Binding var slots: [Int: LaunchItem]
    let layout: GridLayout
    let allowGroups: Bool
    /// グループ内編集時: グループ自身が占めるマス（置けない）
    var reservedSlot: Int? = nil
    var reservedItem: LaunchItem? = nil

    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("gridGap") private var gridGapX = GridDefaults.gapX
    @AppStorage("gridGapY") private var gridGapY = GridDefaults.gapY
    @AppStorage("iconScale") private var iconScale = GridDefaults.iconScale
    @AppStorage("showGridLines") private var showGridLines = true
    @AppStorage("labelSpacing") private var labelSpacing = GridDefaults.labelSpacing
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @AppStorage("gridOffsetY") private var gridOffsetY = 0.0
    @State private var createSlot: Int?
    @State private var target: EditorTarget?
    @State private var dragFrom: Int?
    @State private var dragOffset: CGSize = .zero
    /// iPad: グリッドは端末に対して動かさず、アイコンだけを持った向きに回す（iPhone では 0）
    @Environment(\.geodeIconAngle) private var iconAngle

    /// 空きマスの「＋」タイルの色
    private static let addColor = Theme.addColor

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(size: geo.size, layout: layout, showLabels: showLabels,
                                      gapX: gridGapX, gapY: gridGapY, iconScale: iconScale,
                                      labelSpacing: labelSpacing, outerMargin: outerMargin, offsetY: gridOffsetY)
            ZStack {
                Color.clear
                if showGridLines { GridLines(metrics: metrics) }
                ForEach(0..<layout.capacity, id: \.self) { slot in
                    cell(slot, metrics: metrics)
                        .frame(width: metrics.cellSize.width, height: metrics.cellSize.height, alignment: .top)
                        .position(metrics.center(slot))
                        .zIndex(dragFrom == slot ? 2 : 0)
                }
                // 削除ボタン（×）はすべてのタイルより上の層に置く。タイルの中に置くと、iPad でアイコンを回したとき
                // × が隣のマスにかかり、隣のタイルのタップが先に反応していた
                ForEach(slots.keys.sorted(), id: \.self) { slot in
                    if slot != reservedSlot, slot != dragFrom, let item = slots[slot] {
                        deleteButton(slot, item)
                            .position(deleteButtonCenter(slot, metrics: metrics))
                            .zIndex(1)
                    }
                }
            }
            .coordinateSpace(name: "editgrid")
        }
        .foregroundStyle(.tint)
        .confirmationDialog("何を作成しますか？",
                            isPresented: Binding(get: { createSlot != nil }, set: { if !$0 { createSlot = nil } }),
                            titleVisibility: .visible,
                            presenting: createSlot) { slot in
            Button("グループ") {
                target = EditorTarget(slot: slot, item: LaunchItem(kind: .group, name: "", symbol: "square.grid.2x2"))
            }
            Button("アクション") {
                target = EditorTarget(slot: slot, item: LaunchItem(kind: .action, name: ""))
            }
        }
        .sheet(item: $target) { t in
            // 既に置いてあるアイテムの編集時だけ、編集画面にも「削除」を出す
            let onDelete: (() -> Void)? = slots[t.slot] == nil ? nil : { slots[t.slot] = nil }
            ItemEditor(item: t.item, slot: t.slot, layout: layout, onDelete: onDelete) { saved in
                slots[t.slot] = saved
            }
        }
    }

    private func deleteButton(_ slot: Int, _ item: LaunchItem) -> some View {
        Button {
            slots[slot] = nil
        } label: {
            Image(systemName: "xmark")
                .font(.caption.bold())
                .frame(width: 26, height: 26)
                .styledCircleGlass(interactive: true)
        }
        .accessibilityLabel("\(item.name)を削除")
    }

    /// × の中心: アイコンの左上の角から少し外（持った向きで見た左上）。iPad でアイコンを回しているときは、同じだけ回した位置
    private func deleteButtonCenter(_ slot: Int, metrics: GridMetrics) -> CGPoint {
        let center = metrics.center(slot)
        // マスの中心から見た、回す前の位置（タイルの左上から 8pt 外にはみ出した 26pt の丸の中心）
        let x = -metrics.cellSize.width / 2 + 5, y = -metrics.cellSize.height / 2 + 5
        let a = iconAngle * .pi / 180
        return CGPoint(x: center.x + x * cos(a) - y * sin(a), y: center.y + x * sin(a) + y * cos(a))
    }

    @ViewBuilder
    private func cell(_ slot: Int, metrics: GridMetrics) -> some View {
        if slot == reservedSlot {
            TileView(item: reservedItem, metrics: metrics).opacity(0.45)
                .rotationEffect(.degrees(iconAngle))
        } else if let item = slots[slot] {
            TileView(item: item, metrics: metrics)
                // iPad: アイコンだけを持った向きに回す（ドラッグの移動量は回さない）
                .rotationEffect(.degrees(iconAngle))
                .offset(dragFrom == slot ? dragOffset : .zero)
                .scaleEffect(dragFrom == slot ? 1.08 : 1)
                .contentShape(Rectangle())
                .onTapGesture { target = EditorTarget(slot: slot, item: item) }
                .gesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .named("editgrid"))
                        .onChanged { v in
                            dragFrom = slot
                            dragOffset = v.translation
                        }
                        .onEnded { v in
                            let to = metrics.slot(at: v.location)
                            withAnimation(.snappy) {
                                // 格子の外で離したときは元の位置のまま
                                if let to, to != slot, to != reservedSlot {
                                    let moving = slots[slot]
                                    slots[slot] = slots[to]
                                    slots[to] = moving
                                }
                                dragFrom = nil
                                dragOffset = .zero
                            }
                        }
                )
        } else {
            // 空きマス: アイコンと同じ角丸のガラスタイル + 中央に＋
            Button {
                if allowGroups {
                    createSlot = slot
                } else {
                    target = EditorTarget(slot: slot, item: LaunchItem(kind: .action, name: ""))
                }
            } label: {
                if uiStyle == UIStyle.glow.rawValue {
                    // グロー: 暗いガラスのタイルに銀色の＋
                    GlowTileBackground(size: metrics.tile, dim: true)
                        .overlay { GlowSymbol(name: "plus", size: metrics.tile * 0.85) }
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: metrics.tile * 0.36, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: metrics.tile, height: metrics.tile)
                        .glass(in: iconShape(metrics.tile), tint: Self.addColor, interactive: true)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

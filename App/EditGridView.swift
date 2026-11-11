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
    @AppStorage("outerMargin") private var outerMargin = GridDefaults.outerMargin
    @State private var createSlot: Int?
    @State private var target: EditorTarget?
    @State private var dragFrom: Int?
    @State private var dragOffset: CGSize = .zero

    /// 空きマスの「＋」タイルの色（#525253）
    private static let addColor = Color(red: 82 / 255, green: 82 / 255, blue: 83 / 255)

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(size: geo.size, layout: layout, showLabels: showLabels,
                                      gapX: gridGapX, gapY: gridGapY, iconScale: iconScale,
                                      labelSpacing: labelSpacing, outerMargin: outerMargin)
            ZStack {
                Color.clear
                if showGridLines { GridLines(metrics: metrics) }
                ForEach(0..<layout.capacity, id: \.self) { slot in
                    cell(slot, metrics: metrics)
                        .frame(width: metrics.cellSize.width, height: metrics.cellSize.height, alignment: .top)
                        .position(metrics.center(slot))
                        .zIndex(dragFrom == slot ? 1 : 0)
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
            ItemEditor(item: t.item, slot: t.slot, layout: layout) { saved in
                slots[t.slot] = saved
            }
        }
    }

    @ViewBuilder
    private func cell(_ slot: Int, metrics: GridMetrics) -> some View {
        if slot == reservedSlot {
            TileView(item: reservedItem, metrics: metrics).opacity(0.45)
        } else if let item = slots[slot] {
            TileView(item: item, metrics: metrics)
                .overlay(alignment: .topLeading) {
                    Button {
                        slots[slot] = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .frame(width: 26, height: 26)
                            .glass(in: Circle(), interactive: true)
                    }
                    .offset(x: -8, y: -8)
                }
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
                Image(systemName: "plus")
                    .font(.system(size: metrics.tile * 0.36, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: metrics.tile, height: metrics.tile)
                    .glass(in: iconShape(metrics.tile), tint: Self.addColor, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }
}

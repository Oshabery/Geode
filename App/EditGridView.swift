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

    @State private var createSlot: Int?
    @State private var target: EditorTarget?
    @State private var dragFrom: Int?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(0..<layout.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<layout.columns, id: \.self) { c in
                            let slot = r * layout.columns + c
                            cell(slot, size: geo.size)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .zIndex(dragFrom == slot ? 1 : 0)
                        }
                    }
                    .zIndex(dragFrom.map { $0 / layout.columns } == r ? 1 : 0)
                }
            }
            .coordinateSpace(name: "editgrid")
        }
        .foregroundStyle(Color.accentColor)
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
    private func cell(_ slot: Int, size: CGSize) -> some View {
        if slot == reservedSlot {
            CellView(item: reservedItem, highlighted: true).opacity(0.6)
        } else if let item = slots[slot] {
            CellView(item: item)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).padding(4))
                .overlay(alignment: .topLeading) {
                    Button {
                        slots[slot] = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color(.systemBackground)))
                            .overlay(Circle().stroke(lineWidth: 1))
                    }
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
                            let to = slotIndex(at: v.location, in: size, layout: layout)
                            withAnimation(.snappy) {
                                if to != slot, to != reservedSlot {
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
            Button {
                if allowGroups {
                    createSlot = slot
                } else {
                    target = EditorTarget(slot: slot, item: LaunchItem(kind: .action, name: ""))
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 34, weight: .ultraLight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
                    .overlay(Rectangle().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
                    .padding(4)
            }
        }
    }
}

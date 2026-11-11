import SwiftUI

/// 画面下部の 3 つのボタン（ドック）。設定 / 編集ボタンと同じ 44pt の丸いガラスボタン。
/// グリッドのアイコンと同じ操作にそろえている。
/// - 通常モード: 割り当て済みはタップで起動。未割り当ては「＋」で、タップするとその場で割り当て
/// - 編集モード: 未割り当ては灰色の「＋」、割り当て済みはタップで編集、× で削除、ドラッグで入れ替え
struct DockBar: View {
    @EnvironmentObject private var store: BoardStore
    let editing: Bool
    @AppStorage("dockSpacing") private var dockSpacing = GridDefaults.dockSpacing
    @State private var target: EditorTarget?
    @State private var dragFrom: Int?
    @State private var dragOffset: CGFloat = 0

    private static let buttonSize: CGFloat = 44

    private var dock: [Int: LaunchItem] { store.board.dock ?? [:] }

    private func setDock(_ index: Int, _ item: LaunchItem?) {
        var d = dock
        d[index] = item
        store.board.dock = d
    }

    var body: some View {
        GeometryReader { geo in
            // 中央のボタンを基準に、左右のボタンを dockSpacing だけ離す。画面からはみ出さないよう上限をかける
            let count = CGFloat(Board.dockCount)
            let limit = max((geo.size.width - 32 - count * Self.buttonSize) / max(count - 1, 1), 0)
            let spacing = min(CGFloat(max(dockSpacing, 0)), limit)
            HStack(spacing: spacing) {
                ForEach(0..<Board.dockCount, id: \.self) { index in
                    button(index, spacing: spacing)
                        .zIndex(dragFrom == index ? 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 56)
        .sheet(item: $target) { t in
            let onDelete: (() -> Void)? = dock[t.slot] == nil ? nil : { setDock(t.slot, nil) }
            ItemEditor(item: t.item, slot: t.slot, layout: store.board.layout, onDelete: onDelete) { saved in
                setDock(t.slot, saved)
            }
        }
    }

    @ViewBuilder
    private func button(_ index: Int, spacing: CGFloat) -> some View {
        if let item = dock[index] {
            let tint = item.iconFile == nil ? item.baseHSB?.color : nil
            if editing {
                // 編集モード: グリッドのアイコンと同じく、タップで編集・× で削除・ドラッグで入れ替え
                DockIcon(item: item)
                    .foregroundStyle(.tint)
                    .glass(in: Circle(), tint: tint)
                    .overlay(alignment: .topLeading) {
                        Button {
                            setDock(index, nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .glass(in: Circle(), interactive: true)
                        }
                        .offset(x: -8, y: -8)
                    }
                    .offset(x: dragFrom == index ? dragOffset : 0)
                    .scaleEffect(dragFrom == index ? 1.1 : 1)
                    .contentShape(Rectangle())   // グリッドと同じ指定（× バッジのタップを妨げない）
                    .onTapGesture { target = EditorTarget(slot: index, item: item) }
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { v in
                                dragFrom = index
                                dragOffset = v.translation.width
                            }
                            .onEnded { v in
                                let step = Self.buttonSize + spacing
                                let moved = Int((v.translation.width / max(step, 1)).rounded())
                                let to = min(max(index + moved, 0), Board.dockCount - 1)
                                withAnimation(.snappy) {
                                    if to != index {
                                        var d = dock
                                        let moving = d[index]
                                        d[index] = d[to]
                                        d[to] = moving
                                        store.board.dock = d
                                    }
                                    dragFrom = nil
                                    dragOffset = 0
                                }
                            }
                    )
                    .accessibilityLabel(item.name)
            } else {
                Button {
                    store.launch(item)
                } label: {
                    DockIcon(item: item)
                }
                .glass(in: Circle(), tint: tint, interactive: true)
                .accessibilityLabel(item.name)
            }
        } else {
            // 未割り当て: 常に「＋」を表示。編集モードではグリッドの空きマスと同じ灰色
            Button {
                target = EditorTarget(slot: index, item: LaunchItem(kind: .action, name: ""))
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(editing ? Color.white : Color.accentColor)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
            }
            .glass(in: Circle(), tint: editing ? Theme.addColor : nil, interactive: true)
            .accessibilityLabel("ボタンにアクションを追加")
        }
    }
}

/// ドックボタンの中身: アイコン画像があれば丸く切り抜いて表示、無ければシンボル
private struct DockIcon: View {
    let item: LaunchItem

    var body: some View {
        if let file = item.iconFile, let img = loadIconImage(file) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .frame(width: 44, height: 44)
        } else if let base = item.baseHSB {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(base.prefersDarkSymbol ? Color.black : Color.white)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: item.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
    }
}

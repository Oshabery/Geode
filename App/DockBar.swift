import SwiftUI

/// 画面下部の 3 つのボタン（ドック）。設定 / 編集ボタンと同じ 44pt の丸いガラスボタン。
/// - 未割り当てのボタンは常に「＋」を表示し、タップでアクションを割り当てる
/// - 通常モード: 割り当て済みのボタンはタップで起動
/// - 編集モード: 割り当て済みのボタンはタップで編集、× で削除
struct DockBar: View {
    @EnvironmentObject private var store: BoardStore
    let editing: Bool
    @State private var target: EditorTarget?

    private var dock: [Int: LaunchItem] { store.board.dock ?? [:] }

    var body: some View {
        HStack {
            ForEach(0..<Board.dockCount, id: \.self) { index in
                if index > 0 { Spacer() }
                button(index)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .sheet(item: $target) { t in
            ItemEditor(item: t.item, slot: t.slot, layout: store.board.layout) { saved in
                var d = dock
                d[t.slot] = saved
                store.board.dock = d
            }
        }
    }

    @ViewBuilder
    private func button(_ index: Int) -> some View {
        if let item = dock[index] {
            Button {
                if editing {
                    target = EditorTarget(slot: index, item: item)
                } else {
                    store.launch(item)
                }
            } label: {
                DockIcon(item: item)
            }
            .glass(in: Circle(), tint: item.iconFile == nil ? item.baseHSB?.color : nil, interactive: true)
            .overlay(alignment: .topLeading) {
                if editing {
                    Button {
                        var d = dock
                        d[index] = nil
                        store.board.dock = d
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .glass(in: Circle(), interactive: true)
                    }
                    .offset(x: -5, y: -5)
                }
            }
            .accessibilityLabel(item.name)
        } else {
            // 未割り当て: 通常モードでも常に「＋」を表示し、タップでその場で割り当てられる
            Button {
                target = EditorTarget(slot: index, item: LaunchItem(kind: .action, name: ""))
            } label: {
                Image(systemName: "plus").font(.title3).frame(width: 44, height: 44)
            }
            .glass(in: Circle(), interactive: true)
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

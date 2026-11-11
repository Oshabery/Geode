import SwiftUI
import PhotosUI

/// アクション / グループの編集シート
struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: LaunchItem
    let slot: Int
    let layout: GridLayout
    /// 指定すると編集画面の一番下に「削除」ボタンを出す
    var onDelete: (() -> Void)? = nil
    let onSave: (LaunchItem) -> Void

    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var note: String?

    private static let symbols = [
        "app.dashed", "square.grid.2x2", "hand.thumbsup", "camera", "photo", "music.note", "play.circle",
        "gamecontroller", "cart", "creditcard", "yensign.circle", "map", "tram", "car", "airplane",
        "message", "envelope", "phone", "person.2", "globe", "magnifyingglass", "book", "newspaper",
        "doc.text", "folder", "calendar", "checklist", "clock", "heart", "star", "bolt", "house",
        "briefcase", "graduationcap", "fork.knife", "cup.and.saucer", "figure.run", "cloud.sun", "wrench.and.screwdriver", "sparkles",
    ]

    private var useBaseColor: Binding<Bool> {
        Binding(get: { item.baseColor != nil },
                set: { item.baseColor = $0 ? (item.baseColor ?? Theme.defaultTint.rawValue) : nil })
    }

    private var baseColorValue: Binding<HSBColor> {
        Binding(get: { item.baseHSB ?? Theme.defaultTint }, set: { item.baseColor = $0.rawValue })
    }

    /// 保存して閉じる。グループ名が空のまま中身のページから完了した場合は仮の名前を付ける。
    private func save() {
        var saved = item
        if saved.name.trimmingCharacters(in: .whitespaces).isEmpty {
            saved.name = saved.kind == .group ? "グループ" : "アクション"
        }
        onSave(saved)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(item.kind == .group ? "グループ名" : "アクション名", text: $item.name)
                    if item.kind == .action {
                        TextField("url://", text: $item.urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        NavigationLink("アプリから選ぶ（スキーム・アイコン自動入力）") {
                            AppPicker { picked in
                                item.name = picked.name
                                item.urlString = picked.urlString
                                item.symbol = picked.symbol
                                item.iconFile = picked.iconFile
                                item.isToggle = nil
                                if picked.urlString.isEmpty {
                                    note = "このアプリの URL スキームは辞書にありません。URL 欄に手入力してください。"
                                }
                            }
                        }
                        NavigationLink("本体の操作から選ぶ（ライト・消音・Wi-Fi など）") {
                            SystemActionPicker { picked in
                                item.name = picked.name
                                item.urlString = picked.urlString
                                item.symbol = picked.symbol
                                item.iconFile = nil      // 前に選んだアプリの画像が残らないように
                                item.isToggle = picked.isToggle ? true : nil
                                note = nil
                            }
                        }
                        if !SystemActions.isTorchURL(item.urlString) {
                            Toggle("オン / オフのスイッチとして表示", isOn: Binding(
                                get: { item.isToggle == true },
                                set: { item.isToggle = $0 ? true : nil }))
                        }
                        Button("テスト起動") {
                            if let url = URL(string: item.urlString.trimmingCharacters(in: .whitespaces)) {
                                let builtIn = SystemActions.performIfBuiltIn(url)
                                if builtIn.handled {
                                    note = builtIn.error
                                    return
                                }
                                UIApplication.shared.open(url, options: [:]) { ok in
                                    if !ok { note = "開けませんでした。スキームを確認してください。" }
                                }
                            } else {
                                note = "URL が正しくありません。"
                            }
                        }
                        .disabled(item.urlString.isEmpty)
                    } else {
                        NavigationLink("グループの中身を配置") {
                            EditGridView(slots: $item.children, layout: layout, allowGroups: false,
                                         reservedSlot: slot, reservedItem: item)
                                .navigationTitle(item.name.isEmpty ? "グループ" : item.name)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    // 中身を配置したら、このページからそのまま保存して閉じられる
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("完了") { save() }
                                    }
                                }
                        }
                    }
                } footer: {
                    if let note { Text(note).foregroundStyle(.orange) }
                }

                Section("アイコン") {
                    HStack {
                        ItemIcon(item: item, size: 56).foregroundStyle(Color.accentColor)
                        Spacer()
                        if busy { ProgressView() }
                    }
                    Button("App Store から名前でアイコン取得") {
                        Task {
                            busy = true
                            if let hit = await IconService.search(item.name).first, let url = hit.artwork,
                               let file = await IconService.download(url) {
                                item.iconFile = file
                            } else {
                                note = "アイコンが見つかりませんでした。"
                            }
                            busy = false
                        }
                    }
                    .disabled(item.name.isEmpty || busy)
                    PhotosPicker("写真から選ぶ", selection: $photo, matching: .images)
                    if item.iconFile != nil {
                        Button("画像を外してシンボルに戻す", role: .destructive) { item.iconFile = nil }
                    }
                    Toggle("ベースの色を指定", isOn: useBaseColor)
                        .disabled(item.iconFile != nil)
                    if item.baseColor != nil && item.iconFile == nil {
                        HSBEditor(color: baseColorValue)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { s in
                            Image(systemName: s)
                                .font(.title3)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(item.iconFile == nil && item.symbol == s
                                                          ? Color.accentColor.opacity(0.25) : .clear))
                                .onTapGesture {
                                    item.symbol = s
                                    item.iconFile = nil
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let onDelete {
                    Section {
                        Button(item.kind == .group ? "このグループを削除" : "このアクションを削除", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item.kind == .group ? "グループ" : "アクション")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { save() }
                        .disabled(item.name.isEmpty)
                }
            }
            .onChange(of: photo) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data), let file = IconService.save(image) {
                        item.iconFile = file
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

import SwiftUI

struct PickedApp {
    var name: String
    var urlString: String
    var symbol: String
    var iconFile: String?
    var isToggle = false
    var startsOn = false
}

/// 辞書への登録フォームの下書き
struct CatalogDraft: Identifiable {
    let id = UUID()
    var name = ""
    var scheme = ""
    var bundleId: String? = nil
}

/// アプリ辞書 / App Store 検索からアプリを選ぶ。
/// 行を左スワイプで非表示、右スワイプ（スキーム未登録の行）でスキーム登録。
struct AppPicker: View {
    let onPick: (PickedApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = CatalogStore.shared
    @State private var query = ""
    @State private var results: [IconService.StoreApp] = []
    @State private var busy = false
    @State private var draft: CatalogDraft?

    private func filtered(_ apps: [CatalogApp]) -> [CatalogApp] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if !results.isEmpty {
                Section("App Store の検索結果") {
                    ForEach(results) { app in
                        Button { pick(store: app) } label: {
                            HStack {
                                AsyncImage(url: app.artworkUrl100) { $0.resizable() } placeholder: { Color.gray.opacity(0.2) }
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(app.trackName).lineLimit(1)
                                    Text(catalog.scheme(forBundleId: app.bundleId) ?? "スキーム不明（手入力）")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                draft = CatalogDraft(name: app.trackName,
                                                     scheme: catalog.scheme(forBundleId: app.bundleId) ?? "",
                                                     bundleId: app.bundleId)
                            } label: { Label("辞書に登録", systemImage: "plus") }
                            .tint(.blue)
                        }
                    }
                }
            }

            Section("この iPhone にあるアプリ") {
                ForEach(filtered(catalog.detected)) { row($0) }
            }

            let missing = filtered(catalog.missingScheme)
            if !missing.isEmpty {
                Section {
                    ForEach(missing) { app in
                        row(app)
                            .swipeActions(edge: .leading) {
                                Button {
                                    draft = CatalogDraft(name: app.name, bundleId: app.bundleId)
                                } label: { Label("スキームを登録", systemImage: "link.badge.plus") }
                                .tint(.blue)
                            }
                    }
                } header: {
                    Text("この iPhone にあるアプリ（スキーム未登録）")
                } footer: {
                    Text("右にスワイプして URL スキームを登録すると、以後は上の一覧に出ます。")
                }
            }

            Section("この iPhone で見つからないアプリ") {
                ForEach(filtered(catalog.undetected)) { row($0) }
            }

            Section {
                NavigationLink {
                    HiddenAppsView()
                } label: {
                    HStack {
                        Label("非表示の項目", systemImage: "eye.slash")
                        Spacer()
                        Text("\(catalog.hiddenEntries.count)").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if catalog.deviceApps.isEmpty {
                    Text("行を左にスワイプすると非表示にできます。Mac で tools/import_installed_apps.py を実行すると、この iPhone に入っているアプリの一覧を取り込めます。")
                } else {
                    Text("行を左にスワイプすると非表示にできます。")
                }
            }
        }
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .disabled(busy)
        .searchable(text: $query, prompt: "アプリ名（Enter で App Store 検索）")
        .onSubmit(of: .search) {
            Task {
                busy = true
                results = await IconService.search(query)
                busy = false
            }
        }
        .navigationTitle("アプリを選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { draft = CatalogDraft() } label: { Label("辞書に登録", systemImage: "plus") }
            }
        }
        .sheet(item: $draft) { d in
            CatalogEntryForm(draft: d) { catalog.addUser($0) }
        }
    }

    private func row(_ app: CatalogApp) -> some View {
        Button { pick(catalog: app) } label: {
            HStack {
                Image(systemName: app.symbol).frame(width: 30)
                Text(app.name).lineLimit(1)
                Spacer()
                Text(app.scheme.isEmpty ? "スキーム未登録" : app.scheme)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                catalog.hide(app)
            } label: { Label("非表示", systemImage: "eye.slash") }
        }
    }

    private func pick(catalog app: CatalogApp) {
        Task {
            busy = true
            let icon = await IconService.icon(for: app)
            busy = false
            onPick(PickedApp(name: app.name, urlString: app.scheme, symbol: app.symbol, iconFile: icon))
            dismiss()
        }
    }

    private func pick(store app: IconService.StoreApp) {
        Task {
            busy = true
            var icon: String?
            if let url = app.artwork { icon = await IconService.download(url) }
            busy = false
            onPick(PickedApp(name: app.trackName, urlString: catalog.scheme(forBundleId: app.bundleId) ?? "",
                             symbol: "app", iconFile: icon))
            dismiss()
        }
    }
}

/// 非表示にした項目の一覧（別階層）。ここから元に戻せる。
struct HiddenAppsView: View {
    @ObservedObject private var catalog = CatalogStore.shared

    var body: some View {
        List {
            if catalog.hiddenEntries.isEmpty {
                Text("非表示の項目はありません。").foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(catalog.hiddenEntries) { app in
                        HStack {
                            Image(systemName: app.symbol).frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(app.name).lineLimit(1)
                                Text(app.scheme.isEmpty ? "スキーム未登録" : app.scheme)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("戻す") { catalog.unhide(app) }
                                .buttonStyle(.bordered)
                        }
                        .swipeActions(edge: .trailing) {
                            if catalog.isUserApp(app) {
                                Button(role: .destructive) {
                                    catalog.removeUser(app)
                                } label: { Label("完全に削除", systemImage: "trash") }
                            }
                        }
                    }
                } footer: {
                    Text("非表示の項目は、アプリ選択と「検出したアプリを一括配置」の対象から外れます。自分で登録した項目は、左スワイプで辞書から完全に削除できます。")
                }
            }
        }
        .navigationTitle("非表示の項目")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 辞書への登録フォーム
struct CatalogEntryForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: CatalogDraft
    let onSave: (CatalogApp) -> Void

    private var scheme: String { draft.scheme.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { !draft.name.isEmpty && scheme.contains(":") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("アプリ名", text: $draft.name)
                    TextField("URL スキーム（例: myapp://）", text: $draft.scheme)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let id = draft.bundleId {
                        LabeledContent("Bundle ID", value: id)
                    }
                } footer: {
                    Text("スキームは「myapp://」のようにコロンまで含めて入力します。")
                }
                Section {
                    Button("テスト起動") {
                        if let url = URL(string: scheme) { UIApplication.shared.open(url) }
                    }
                    .disabled(!valid)
                }
            }
            .navigationTitle("辞書に登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("登録") {
                        onSave(CatalogApp(name: draft.name, scheme: scheme, bundleId: draft.bundleId,
                                          iconSearch: draft.name, symbol: "app"))
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
    }
}

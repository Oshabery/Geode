import SwiftUI

struct PickedApp {
    var name: String
    var urlString: String
    var symbol: String
    var iconFile: String?
}

/// 検出済みアプリ / 辞書 / App Store 検索からアプリを選ぶ
struct AppPicker: View {
    let onPick: (PickedApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [IconService.StoreApp] = []
    @State private var busy = false
    @State private var detected: [CatalogApp] = []

    private func matches(_ app: CatalogApp) -> Bool {
        query.isEmpty || app.name.localizedCaseInsensitiveContains(query)
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
                                    Text(AppCatalog.scheme(forBundleId: app.bundleId) ?? "スキーム不明（手入力）")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section("この iPhone で検出したアプリ") {
                ForEach(detected.filter(matches)) { row($0) }
            }
            Section("未検出（辞書にあるアプリ）") {
                ForEach(AppCatalog.all.filter { !detected.contains($0) && matches($0) }) { row($0) }
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
        .onAppear { detected = AppCatalog.installed() }
    }

    private func row(_ app: CatalogApp) -> some View {
        Button { pick(catalog: app) } label: {
            HStack {
                Image(systemName: app.symbol).frame(width: 30)
                Text(app.name)
                Spacer()
                Text(app.scheme).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
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
            onPick(PickedApp(name: app.trackName, urlString: AppCatalog.scheme(forBundleId: app.bundleId) ?? "",
                             symbol: "app", iconFile: icon))
            dismiss()
        }
    }
}

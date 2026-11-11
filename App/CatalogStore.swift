import SwiftUI

/// アプリ辞書の全体を管理する。
/// - 内蔵辞書 (AppCatalog.all)
/// - ユーザーが登録した項目（UserDefaults に保存）
/// - 実機のアプリ一覧（Mac で tools/import_installed_apps.py を実行して取り込んだ InstalledApps.json）
/// - 非表示にした項目
@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()

    struct DeviceApp: Decodable {
        let name: String
        let bundleId: String
    }

    @Published private(set) var hidden: Set<String>
    @Published private(set) var userApps: [CatalogApp]
    let deviceApps: [DeviceApp]
    private let deviceBundleIds: Set<String>
    private var canOpenCache: [String: Bool] = [:]

    private static let hiddenKey = "hiddenCatalogApps"
    private static let userKey = "userCatalogApps"

    private init() {
        let defaults = UserDefaults.standard
        hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
        userApps = defaults.data(forKey: Self.userKey)
            .flatMap { try? JSONDecoder().decode([CatalogApp].self, from: $0) } ?? []
        deviceApps = Bundle.main.url(forResource: "InstalledApps", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([DeviceApp].self, from: $0) } ?? []
        deviceBundleIds = Set(deviceApps.map(\.bundleId))
    }

    // MARK: 一覧

    /// 辞書全体。優先順: ユーザー登録 → 内蔵 → 実機一覧のうちまだ辞書に無いもの（スキーム未登録）
    var entries: [CatalogApp] {
        var result = userApps
        var schemes = Set(userApps.map(\.scheme))
        var bundles = Set(userApps.compactMap(\.bundleId))
        for app in AppCatalog.all {
            if schemes.contains(app.scheme) { continue }
            if let id = app.bundleId, bundles.contains(id) { continue }
            result.append(app)
            schemes.insert(app.scheme)
            if let id = app.bundleId { bundles.insert(id) }
        }
        for app in deviceApps where !bundles.contains(app.bundleId) {
            result.append(CatalogApp(name: app.name, scheme: "", bundleId: app.bundleId, symbol: "app"))
            bundles.insert(app.bundleId)
        }
        return result
    }

    private var visible: [CatalogApp] { entries.filter { !hidden.contains($0.id) } }

    /// この iPhone にあり、スキームも分かっているアプリ
    var detected: [CatalogApp] { visible.filter { !$0.scheme.isEmpty && isOnDevice($0) } }
    /// この iPhone にあるが、スキームが未登録のアプリ
    var missingScheme: [CatalogApp] { visible.filter { $0.scheme.isEmpty } }
    /// 辞書にはあるが、この iPhone では見つからないアプリ
    var undetected: [CatalogApp] { visible.filter { !$0.scheme.isEmpty && !isOnDevice($0) } }
    var hiddenEntries: [CatalogApp] { entries.filter { hidden.contains($0.id) } }

    func isUserApp(_ app: CatalogApp) -> Bool { userApps.contains { $0.id == app.id } }

    func scheme(forBundleId id: String) -> String? {
        entries.first { $0.bundleId == id && !$0.scheme.isEmpty }?.scheme
    }

    private func isOnDevice(_ app: CatalogApp) -> Bool {
        if app.system || isUserApp(app) { return true }
        if let id = app.bundleId, deviceBundleIds.contains(id) { return true }
        if let cached = canOpenCache[app.scheme] { return cached }
        let ok = URL(string: app.scheme).map { UIApplication.shared.canOpenURL($0) } ?? false
        canOpenCache[app.scheme] = ok
        return ok
    }

    // MARK: 変更

    func hide(_ app: CatalogApp) {
        hidden.insert(app.id)
        saveHidden()
    }

    func unhide(_ app: CatalogApp) {
        hidden.remove(app.id)
        saveHidden()
    }

    /// ユーザー辞書に登録（同じスキームがあれば上書き）
    func addUser(_ app: CatalogApp) {
        userApps.removeAll { $0.scheme == app.scheme }
        userApps.insert(app, at: 0)
        hidden.remove(app.id)
        saveHidden()
        saveUser()
    }

    func removeUser(_ app: CatalogApp) {
        userApps.removeAll { $0.id == app.id }
        hidden.remove(app.id)
        saveHidden()
        saveUser()
    }

    private func saveHidden() {
        UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
    }

    private func saveUser() {
        if let data = try? JSONEncoder().encode(userApps) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }
}

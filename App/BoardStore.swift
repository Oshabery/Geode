import SwiftUI
import WidgetKit

@MainActor
final class BoardStore: ObservableObject {
    @Published var board: Board {
        didSet {
            SharedStorage.save(board)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    /// ウィジェットからグループを開く要求
    @Published var requestedGroup: UUID?
    @Published var errorMessage: String?

    init() {
        board = SharedStorage.loadBoard()
        cleanUpIcons()
    }

    // MARK: 起動

    func launch(_ item: LaunchItem) {
        let raw = item.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            errorMessage = "「\(item.name)」の URL が正しくありません。"
            return
        }
        // ライトなど Geode 自身が実行する操作
        let builtIn = SystemActions.performIfBuiltIn(url)
        if builtIn.handled {
            if let error = builtIn.error { errorMessage = error }
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            if !ok {
                Task { @MainActor in
                    self?.errorMessage = "「\(item.name)」を開けませんでした。\nアプリが未インストールか、URL スキームが違う可能性があります。\n\(raw)"
                }
            }
        }
    }

    func handle(_ url: URL) {
        // ショートカットの実行に失敗して戻ってきた
        if url.scheme == "geode", url.host == SystemActions.shortcutErrorHost {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let name = query.first { $0.name == "name" }?.value ?? ""
            let detail = query.first { $0.name == "errorMessage" }?.value
            errorMessage = "ショートカット「\(name)」を実行できませんでした。\n"
                + (detail ?? "ショートカット App に同じ名前のショートカットがあるか確認してください。")
            return
        }
        guard url.scheme == "geode",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idString = comps.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idString),
              let item = board.find(id) else { return }
        if item.kind == .group {
            requestedGroup = id
        } else {
            // シーンがアクティブになるのを少し待ってから外部アプリへ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.launch(item) }
        }
    }

    // MARK: 自動検出

    /// 検出できたアプリを空きマスへ一括配置。追加件数を返す。
    func addDetectedApps() async -> Int {
        var existing = Set<String>()
        for item in board.topLevelItems {
            existing.insert(item.urlString)
            for c in item.children.values { existing.insert(c.urlString) }
        }
        var added = 0
        for app in CatalogStore.shared.detected where !existing.contains(app.scheme) {
            guard let free = (0..<board.layout.capacity).first(where: { board.slots[$0] == nil }) else { break }
            var item = LaunchItem(kind: .action, name: app.name, urlString: app.scheme, symbol: app.symbol)
            item.iconFile = await IconService.icon(for: app)
            board.slots[free] = item
            added += 1
        }
        return added
    }

    // MARK: レイアウト

    /// 行列数を変更。収まらない場合は false。
    func applyLayout(_ new: GridLayout) -> Bool {
        let old = board.layout
        guard var top = Self.remap(board.slots, from: old, to: new, reserved: nil) else { return false }
        for (slot, item) in top where item.kind == .group {
            guard let kids = Self.remap(item.children, from: old, to: new, reserved: slot) else { return false }
            top[slot]?.children = kids
        }
        var b = board
        b.layout = new
        b.slots = top
        board = b
        return true
    }

    private static func remap(_ slots: [Int: LaunchItem], from old: GridLayout, to new: GridLayout,
                              reserved: Int?) -> [Int: LaunchItem]? {
        var result: [Int: LaunchItem] = [:]
        var overflow: [LaunchItem] = []
        for (i, item) in slots.sorted(by: { $0.key < $1.key }) {
            let r = i / old.columns, c = i % old.columns
            let target = r * new.columns + c
            if r < new.rows, c < new.columns, target != reserved {
                result[target] = item
            } else {
                overflow.append(item)
            }
        }
        for item in overflow {
            guard let free = (0..<new.capacity).first(where: { result[$0] == nil && $0 != reserved })
            else { return nil }
            result[free] = item
        }
        return result
    }

    private func cleanUpIcons() {
        let used = board.referencedIconFiles
        let files = (try? FileManager.default.contentsOfDirectory(atPath: SharedStorage.iconsDir.path)) ?? []
        for f in files where !used.contains(f) {
            try? FileManager.default.removeItem(at: SharedStorage.iconURL(f))
        }
    }
}

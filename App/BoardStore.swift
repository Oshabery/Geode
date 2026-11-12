import SwiftUI
import WidgetKit
import MediaPlayer

@MainActor
final class BoardStore: ObservableObject {
    @Published var board: Board {
        didSet {
            SharedStorage.save(board)
            WidgetCenter.shared.reloadAllTimelines()
            // 新しく置いたオン / オフのボタンも、すぐに実際の状態で表示する
            refreshDirectStates()
        }
    }
    /// ウィジェットからグループを開く要求
    @Published var requestedGroup: UUID?
    @Published var errorMessage: String?
    /// グループ階層を開いている間 true（ContentView がグリッドを最前面に描くために使う）
    @Published var groupLayerOpen = false
    /// 最後に実行したショートカット名（失敗して戻ってきたときの表示用）
    private var lastShortcutName = ""

    /// Geode で直接操作するスイッチの実際の状態（キーは DirectKind.rawValue）
    @Published private(set) var directStates: [String: Bool] = [:]
    private var musicNotificationsStarted = false
    /// ショートカット経由のスイッチの状態（Geode の推定値）。キーは LaunchItem.id の文字列。
    /// 盤面と分けて保存する（切り替えのたびに board.json とウィジェットを更新しないため）
    @Published private(set) var toggleStates: [String: Bool]
    /// ショートカットの成功通知を待っているスイッチ
    private var pendingToggleID: UUID?
    private static let toggleStatesKey = "toggleStates"

    init() {
        board = SharedStorage.loadBoard()
        toggleStates = (UserDefaults.standard.dictionary(forKey: Self.toggleStatesKey) as? [String: Bool]) ?? [:]
        cleanUpIcons()
        // どこから実行しても（テスト起動を含む）状態を読み直す
        NotificationCenter.default.addObserver(forName: SystemActions.directActionPerformed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDirectStates()
                // ミュージックの状態は少し遅れて変わるので、念のため読み直す
                try? await Task.sleep(for: .milliseconds(600))
                self?.refreshDirectStates()
            }
        }
        refreshDirectStates()
    }

    // MARK: スイッチ

    /// スイッチとして表示するアイテムの状態。スイッチでなければ nil
    func switchState(for item: LaunchItem) -> Bool? {
        guard SystemActions.isSwitch(item) else { return nil }
        if let kind = SystemActions.directKind(item.urlString) { return directStates[kind.rawValue] ?? false }
        return toggleStates[item.id.uuidString] ?? (item.toggleStartsOn ?? false)
    }

    /// 実行せずに状態だけ直す（Geode の外で切り替えて表示がずれたとき用）
    func setSwitchState(_ item: LaunchItem, _ on: Bool) {
        toggleStates[item.id.uuidString] = on
        UserDefaults.standard.set(toggleStates, forKey: Self.toggleStatesKey)
    }

    /// ショートカット経由のスイッチ（状態を推定しているもの）の一覧
    var estimatedSwitches: [LaunchItem] {
        var result: [LaunchItem] = []
        for item in board.topLevelItems {
            result.append(item)
            result.append(contentsOf: item.children.values)
        }
        return result.filter { SystemActions.isSwitch($0) && SystemActions.directKind($0.urlString) == nil }
    }

    /// 盤面で使われている「Geode で直接」のスイッチの実際の状態を読み直す。
    /// 前面に戻ったとき・操作したときに呼ぶ（ライトは Geode を離れると消えるため）
    func refreshDirectStates() {
        var kinds = Set<DirectKind>()
        for item in board.topLevelItems {
            for i in [item] + Array(item.children.values) {
                if let kind = SystemActions.directKind(i.urlString), kind.isSwitch { kinds.insert(kind) }
            }
        }
        // ミュージックを使うときだけ再生状態の通知を受け取る（使わない人に許可を求めないため）
        if kinds.contains(.musicPlayPause) && !musicNotificationsStarted {
            musicNotificationsStarted = true
            let player = MPMusicPlayerController.systemMusicPlayer
            player.beginGeneratingPlaybackNotifications()
            NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange,
                                                   object: player, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDirectStates() }
            }
        }
        var states: [String: Bool] = [:]
        for kind in kinds {
            states[kind.rawValue] = SystemActions.readState(kind) ?? false
        }
        if states != directStates { directStates = states }
    }

    // MARK: 起動

    func launch(_ item: LaunchItem) {
        let raw = item.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            errorMessage = "「\(item.name)」の URL が正しくありません。"
            return
        }
        // オン / オフのスイッチは押した瞬間にカチッとした触覚を返す
        let isSwitch = SystemActions.isSwitch(item)
        if isSwitch {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        }
        // ライトなど Geode 自身が実行する操作（状態は directActionPerformed 通知で読み直す）
        let builtIn = SystemActions.performIfBuiltIn(url)
        if builtIn.handled {
            if let error = builtIn.error { errorMessage = error }
            return
        }
        if url.scheme == "shortcuts" {
            lastShortcutName = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "name" }?.value ?? ""
            // スイッチの表示は、ショートカットが成功して geode:// に戻ってきたときに切り替える
            pendingToggleID = isSwitch ? item.id : nil
        } else {
            pendingToggleID = nil
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            if !ok {
                Task { @MainActor in
                    self?.pendingToggleID = nil
                    self?.errorMessage = "「\(item.name)」を開けませんでした。\nアプリが未インストールか、URL スキームが違う可能性があります。\n\(raw)"
                }
            }
        }
    }

    func handle(_ url: URL) {
        // ショートカットの実行に失敗して戻ってきた
        // ショートカットが成功して戻ってきた（geode:// のみ）: 待っていたスイッチを切り替える
        if url.scheme == "geode", (url.host ?? "").isEmpty {
            if let id = pendingToggleID, let item = board.find(id) {
                setSwitchState(item, !(switchState(for: item) ?? false))
            }
            pendingToggleID = nil
            return
        }
        if url.scheme == "geode", url.host == SystemActions.shortcutErrorHost {
            pendingToggleID = nil
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let detail = query.first { $0.name == "errorMessage" }?.value
            errorMessage = "ショートカット「\(lastShortcutName)」を実行できませんでした。\n"
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

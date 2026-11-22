import Foundation

enum ItemKind: String, Codable {
    case action, group
}

/// グリッドの 1 マスに置かれるもの。group は children に「1 レイヤー上」のグリッドを持つ。
struct LaunchItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ItemKind
    var name: String
    var urlString: String = ""
    var symbol: String = "app.dashed"
    /// 共有コンテナ内 icons/ のファイル名。nil なら symbol を表示。
    var iconFile: String? = nil
    /// スロット番号 → アイテム（group のみ使用）
    var children: [Int: LaunchItem] = [:]
    /// シンボルアイコンのベース色（HSB の "h,s,b" 文字列）。nil なら UI の色を薄くしたもの
    var baseColor: String? = nil
    /// オン / オフのスイッチとして表示するか（ショートカット経由の操作用。ライトは URL から自動判定）
    var isToggle: Bool? = nil
    /// スイッチの状態がまだ記録されていないときの初期値（Wi-Fi など普段オンのもの用）
    var toggleStartsOn: Bool? = nil
    /// 通知バッジ（赤い点）を表示するか。未読などの目印として利用者が自分で付け外しする
    /// （iOS ではほかのアプリの未読を読み取れないため、自動では付かない）
    var showBadge: Bool? = nil
}

struct GridLayout: Codable, Hashable {
    var columns = 3
    var rows = 6
    var capacity: Int { columns * rows }
}

/// 盤面の向き。iPad の横画面だけ別の配置を持てる（iPhone は常に縦）
enum BoardOrientation: Hashable {
    case portrait, landscape
}

struct Board: Codable {
    var layout = GridLayout()
    var slots: [Int: LaunchItem] = [:]
    /// 画面下部の 3 つのボタン（0...2）。既存の board.json に無くても読めるよう Optional
    var dock: [Int: LaunchItem]? = nil
    /// iPad の横画面の配置。nil の間は縦の配置から作ったもの（derivedLandscape）を使い、
    /// 横画面で最初に編集したときに保存する。既存の board.json に無くても読めるよう Optional
    var landscapeLayout: GridLayout? = nil
    var landscapeSlots: [Int: LaunchItem]? = nil

    static let dockCount = 3

    /// iPad で設定できる行・列の範囲（横画面の配置もこの範囲に収める）
    static let padColumns = 2...8
    static let padRows = 3...10

    /// グリッド（縦・横）とドックの全アイテム（グループの中身は含まない）。
    /// 横の配置は縦の配置のコピーとして始まるので、同じアイテムが 2 回入ることがある
    var topLevelItems: [LaunchItem] {
        Array(slots.values) + Array((landscapeSlots ?? [:]).values) + Array((dock ?? [:]).values)
    }

    // MARK: 向きごとの配置

    /// まだ横画面で編集していないときの横の配置: 縦の配置の行と列を入れ替えたもの。
    /// 入れ替えると設定できる範囲を外れるとき（2×10 など）は、縦の配置をそのまま使う
    var derivedLandscape: (layout: GridLayout, slots: [Int: LaunchItem]) {
        let swapped = GridLayout(columns: layout.rows, rows: layout.columns)
        guard Self.padColumns.contains(swapped.columns), Self.padRows.contains(swapped.rows) else {
            return (layout, slots)
        }
        return (swapped, Self.transpose(slots, from: layout))
    }

    /// 行と列を入れ替えた位置に移す（グループの中身も同じように移すので、中身がグループ自身のマスに重ならない）
    static func transpose(_ slots: [Int: LaunchItem], from layout: GridLayout) -> [Int: LaunchItem] {
        var result: [Int: LaunchItem] = [:]
        for (index, item) in slots {
            let row = index / layout.columns, column = index % layout.columns
            var moved = item
            if !item.children.isEmpty {
                moved.children = transpose(item.children, from: layout)
            }
            // 入れ替え後は列の数 = 元の行の数
            result[column * layout.rows + row] = moved
        }
        return result
    }

    func layout(for orientation: BoardOrientation) -> GridLayout {
        orientation == .portrait ? layout : (landscapeLayout ?? derivedLandscape.layout)
    }

    func slots(for orientation: BoardOrientation) -> [Int: LaunchItem] {
        orientation == .portrait ? slots : (landscapeSlots ?? derivedLandscape.slots)
    }

    /// 向きごとの配置を書き換える。横画面を初めて書き換えたときは、その時点の横の配置（縦から作ったもの）を保存する
    mutating func setSlots(_ newSlots: [Int: LaunchItem], for orientation: BoardOrientation) {
        switch orientation {
        case .portrait:
            slots = newSlots
        case .landscape:
            if landscapeLayout == nil { landscapeLayout = derivedLandscape.layout }
            landscapeSlots = newSlots
        }
    }

    mutating func setArrangement(layout newLayout: GridLayout, slots newSlots: [Int: LaunchItem],
                                 for orientation: BoardOrientation) {
        switch orientation {
        case .portrait:
            layout = newLayout
            slots = newSlots
        case .landscape:
            landscapeLayout = newLayout
            landscapeSlots = newSlots
        }
    }

    func find(_ id: UUID) -> LaunchItem? {
        for item in topLevelItems {
            if item.id == id { return item }
            if let child = item.children.values.first(where: { $0.id == id }) { return child }
        }
        return nil
    }

    /// 通知バッジを外す（縦・横のグリッド・グループの中・ドックのどこにあっても、同じアイテムをすべて）。外したら true
    @discardableResult
    mutating func clearBadge(_ id: UUID) -> Bool {
        var cleared = Self.clearBadge(id, in: &slots)
        if var landscape = landscapeSlots {
            if Self.clearBadge(id, in: &landscape) { cleared = true }
            landscapeSlots = landscape
        }
        if var docked = dock {
            if Self.clearBadge(id, in: &docked) { cleared = true }
            dock = docked
        }
        return cleared
    }

    private static func clearBadge(_ id: UUID, in slots: inout [Int: LaunchItem]) -> Bool {
        var cleared = false
        for key in slots.keys {
            if slots[key]?.id == id, slots[key]?.showBadge != nil {
                slots[key]?.showBadge = nil
                cleared = true
            }
            if let childKey = slots[key]?.children.first(where: { $0.value.id == id })?.key,
               slots[key]?.children[childKey]?.showBadge != nil {
                slots[key]?.children[childKey]?.showBadge = nil
                cleared = true
            }
        }
        return cleared
    }

    var groups: [LaunchItem] {
        slots.sorted { $0.key < $1.key }.map(\.value).filter { $0.kind == .group }
    }

    var referencedIconFiles: Set<String> {
        var s = Set<String>()
        for item in topLevelItems {
            if let f = item.iconFile { s.insert(f) }
            for c in item.children.values { if let f = c.iconFile { s.insert(f) } }
        }
        return s
    }
}

/// アプリ本体とウィジェットで共有する保存領域（App Group）。
enum SharedStorage {
    /// project.yml の App Group と必ず一致させる
    static let appGroup = "group.com.oshabery.geode"

    /// UI テスト中か（起動引数 -GeodeUITesting）。このときは本来のデータに触れないよう一時フォルダを使う
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-GeodeUITesting")

    /// UI テスト用の一時フォルダ。起動ごとに空から始める
    private static let uiTestingContainer: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GeodeUITesting", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 本来の保存先（App Group。使えないときは書類フォルダ）
    static var appContainer: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var container: URL {
        isUITesting ? uiTestingContainer : appContainer
    }
    static var boardURL: URL { container.appendingPathComponent("board.json") }
    static var iconsDir: URL {
        let dir = container.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func iconURL(_ file: String) -> URL { iconsDir.appendingPathComponent(file) }

    static func loadBoard() -> Board {
        guard let data = try? Data(contentsOf: boardURL),
              let board = try? JSONDecoder().decode(Board.self, from: data) else { return Board() }
        return board
    }

    static func save(_ board: Board) {
        guard let data = try? JSONEncoder().encode(board) else { return }
        try? data.write(to: boardURL, options: .atomic)
    }
}

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
}

struct GridLayout: Codable, Hashable {
    var columns = 3
    var rows = 6
    var capacity: Int { columns * rows }
}

struct Board: Codable {
    var layout = GridLayout()
    var slots: [Int: LaunchItem] = [:]
    /// 画面下部の 3 つのボタン（0...2）。既存の board.json に無くても読めるよう Optional
    var dock: [Int: LaunchItem]? = nil

    static let dockCount = 3

    /// グリッドとドックの全アイテム（グループの中身は含まない）
    var topLevelItems: [LaunchItem] { Array(slots.values) + Array((dock ?? [:]).values) }

    func find(_ id: UUID) -> LaunchItem? {
        for item in topLevelItems {
            if item.id == id { return item }
            if let child = item.children.values.first(where: { $0.id == id }) { return child }
        }
        return nil
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

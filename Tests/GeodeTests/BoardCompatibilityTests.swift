import XCTest
@testable import Geode

/// 保存データの互換性。
/// 盤面の形を変えたときに、以前のアプリが保存した board.json を読めないと、
/// 起動時に空の盤面で上書きされて利用者の配置が失われる（Critical）。
final class BoardCompatibilityTests: XCTestCase {

    // 最初のリリース時点（コミット 92780e4）の LaunchItem / Board の形をそのまま写したもの。
    // 手書きの JSON ではなく、当時の型でエンコードした結果を今の型で読む
    private struct LegacyItem: Codable {
        var id = UUID()
        var kind: ItemKind
        var name: String
        var urlString: String = ""
        var symbol: String = "app.dashed"
        var iconFile: String? = nil
        var children: [Int: LegacyItem] = [:]
    }

    private struct LegacyBoard: Codable {
        var layout = GridLayout()
        var slots: [Int: LegacyItem] = [:]
    }

    func testDecodesBoardSavedByFirstRelease() throws {
        let childID = UUID()
        var group = LegacyItem(kind: .group, name: "SNS", symbol: "hand.thumbsup")
        group.children[4] = LegacyItem(id: childID, kind: .action, name: "LINE", urlString: "line://", iconFile: "a.png")
        var legacy = LegacyBoard()
        legacy.layout = GridLayout(columns: 4, rows: 5)
        legacy.slots[0] = LegacyItem(kind: .action, name: "設定", urlString: "App-prefs:", symbol: "gearshape")
        legacy.slots[7] = group

        let data = try JSONEncoder().encode(legacy)
        let board = try JSONDecoder().decode(Board.self, from: data)

        XCTAssertEqual(board.layout, GridLayout(columns: 4, rows: 5))
        XCTAssertEqual(board.slots[0]?.name, "設定")
        XCTAssertEqual(board.slots[0]?.urlString, "App-prefs:")
        XCTAssertEqual(board.slots[7]?.kind, .group)
        XCTAssertEqual(board.slots[7]?.children[4]?.id, childID)
        XCTAssertEqual(board.slots[7]?.children[4]?.iconFile, "a.png")
        // 後から足した項目は、無ければ未設定として読めること
        XCTAssertNil(board.dock)
        XCTAssertNil(board.slots[0]?.baseColor)
        XCTAssertNil(board.slots[0]?.isToggle)
        XCTAssertNil(board.slots[0]?.toggleStartsOn)
        XCTAssertNil(board.slots[0]?.showBadge)
    }

    func testCurrentBoardRoundTrips() throws {
        var item = LaunchItem(kind: .action, name: "ライト", urlString: "geode://torch", symbol: "flashlight.on.fill")
        item.baseColor = "210,80,95"
        item.isToggle = true
        item.showBadge = true
        var board = Board()
        board.slots[3] = item
        board.dock = [1: LaunchItem(kind: .action, name: "Safari", urlString: "https://example.com")]

        let decoded = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board))

        XCTAssertEqual(decoded.slots[3], item)
        XCTAssertEqual(decoded.dock?[1]?.name, "Safari")
    }

    /// 通知バッジは、グリッド・グループの中・ドックのどこにあっても外せる
    func testClearBadgeFindsItemsEverywhere() {
        var top = LaunchItem(kind: .action, name: "top")
        top.showBadge = true
        var child = LaunchItem(kind: .action, name: "child")
        child.showBadge = true
        var group = LaunchItem(kind: .group, name: "G")
        group.children[2] = child
        var docked = LaunchItem(kind: .action, name: "dock")
        docked.showBadge = true
        var board = Board()
        board.slots[0] = top
        board.slots[1] = group
        board.dock = [0: docked]

        XCTAssertTrue(board.clearBadge(top.id))
        XCTAssertTrue(board.clearBadge(child.id))
        XCTAssertTrue(board.clearBadge(docked.id))
        XCTAssertNil(board.slots[0]?.showBadge)
        XCTAssertNil(board.slots[1]?.children[2]?.showBadge)
        XCTAssertNil(board.dock?[0]?.showBadge)
        // 付いていないものは何もしない
        XCTAssertFalse(board.clearBadge(top.id))
        XCTAssertFalse(board.clearBadge(UUID()))
    }

    func testReferencedIconFilesIncludeChildrenAndDock() {
        var group = LaunchItem(kind: .group, name: "G")
        group.children[0] = LaunchItem(kind: .action, name: "c", iconFile: "child.png")
        var board = Board()
        board.slots[0] = group
        board.slots[1] = LaunchItem(kind: .action, name: "a", iconFile: "top.png")
        board.dock = [0: LaunchItem(kind: .action, name: "d", iconFile: "dock.png")]

        // ここに漏れがあると、起動時の掃除でアイコン画像が消える
        XCTAssertEqual(board.referencedIconFiles, ["child.png", "top.png", "dock.png"])
    }
}

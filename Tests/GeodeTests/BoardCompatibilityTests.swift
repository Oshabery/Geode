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

/// iPad の縦画面と横画面で別の配置を持つ仕組み
final class LandscapeArrangementTests: XCTestCase {
    private func item(_ name: String, icon: String? = nil) -> LaunchItem {
        LaunchItem(kind: .action, name: name, iconFile: icon)
    }

    /// 横の配置が無いときは、縦の行と列を入れ替えた配置になる（3×6 → 6×3）
    func testLandscapeIsDerivedByTransposingUntilEdited() {
        var board = Board()          // 3 列 × 6 行
        board.slots[1] = item("a")   // 縦: 0 行目 1 列目
        board.slots[5] = item("b")   // 縦: 1 行目 2 列目

        let layout = board.layout(for: .landscape)
        let slots = board.slots(for: .landscape)

        XCTAssertEqual(layout, GridLayout(columns: 6, rows: 3))
        XCTAssertEqual(slots[6]?.name, "a")    // 横: 1 行目 0 列目
        XCTAssertEqual(slots[13]?.name, "b")   // 横: 2 行目 1 列目
        XCTAssertNil(board.landscapeSlots)     // 読むだけでは保存しない
    }

    /// グループの中身も同じように入れ替わり、グループ自身のマスと重ならない
    func testGroupContentsAreTransposedToo() {
        var group = LaunchItem(kind: .group, name: "G")
        group.children[2] = item("child")      // 縦: 0 行目 2 列目
        var board = Board()
        board.slots[0] = group

        let landscapeGroup = board.slots(for: .landscape)[0]
        XCTAssertEqual(landscapeGroup?.children[12]?.name, "child")  // 横: 2 行目 0 列目
        XCTAssertNil(landscapeGroup?.children[0])
    }

    /// 入れ替えると設定できる範囲を外れる配置（2×10、8×10）では、縦の配置をそのまま使う
    func testDerivedLayoutStaysWithinTheAllowedRange() {
        for portrait in [GridLayout(columns: 2, rows: 10), GridLayout(columns: 8, rows: 10),
                         GridLayout(columns: 3, rows: 6), GridLayout(columns: 5, rows: 8)] {
            var board = Board()
            board.layout = portrait
            let landscape = board.layout(for: .landscape)
            XCTAssertTrue(Board.padColumns.contains(landscape.columns), "\(portrait)")
            XCTAssertTrue(Board.padRows.contains(landscape.rows), "\(portrait)")
            XCTAssertEqual(landscape.capacity, portrait.capacity)
        }
    }

    /// 横画面で編集しても、縦画面の配置は変わらない
    func testEditingLandscapeLeavesPortraitUntouched() {
        var board = Board()
        board.slots[0] = item("portrait")
        var landscape = board.slots(for: .landscape)
        landscape[0] = nil
        landscape[3] = item("landscape-only", icon: "l.png")

        board.setSlots(landscape, for: .landscape)

        XCTAssertEqual(board.slots[0]?.name, "portrait")
        XCTAssertNil(board.slots[3])
        XCTAssertEqual(board.landscapeLayout, GridLayout(columns: 6, rows: 3))
        XCTAssertEqual(board.slots(for: .landscape)[3]?.name, "landscape-only")
    }

    /// 横画面にだけ置いたアイテムも、アイコン画像の掃除と ID 検索の対象になる
    func testLandscapeOnlyItemsAreFoundAndKeepTheirIcons() {
        var board = Board()
        let only = item("landscape-only", icon: "l.png")
        board.setSlots([4: only], for: .landscape)

        XCTAssertTrue(board.referencedIconFiles.contains("l.png"))
        XCTAssertEqual(board.find(only.id)?.name, "landscape-only")
    }

    /// 以前のアプリで保存した盤面には横の配置が無く、縦から作った配置で表示される
    func testOldBoardsHaveNoStoredLandscape() throws {
        var board = Board()
        board.slots[0] = item("a")
        let decoded = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board))
        XCTAssertNil(decoded.landscapeLayout)
        XCTAssertNil(decoded.landscapeSlots)
    }
}

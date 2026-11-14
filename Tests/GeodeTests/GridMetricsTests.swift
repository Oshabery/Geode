import XCTest
@testable import Geode

final class GridMetricsTests: XCTestCase {
    private let size = CGSize(width: 390, height: 700)
    private let layout = GridLayout(columns: 3, rows: 6)

    private func metrics(offsetY: Double = 0, iconScale: Double = 1, labels: Bool = true) -> GridMetrics {
        GridMetrics(size: size, layout: layout, showLabels: labels, gapX: 12, gapY: 12,
                    iconScale: iconScale, labelSpacing: 8, outerMargin: 12, offsetY: offsetY)
    }

    func testEveryCellCenterHitsItsOwnSlot() {
        let m = metrics()
        for slot in 0..<layout.capacity {
            XCTAssertEqual(m.slot(at: m.center(slot)), slot, "slot \(slot)")
        }
    }

    func testPointsOutsideTheLatticeHitNothing() {
        let m = metrics(iconScale: 0.6)
        XCTAssertNil(m.slot(at: CGPoint(x: 1, y: 1)))
        XCTAssertNil(m.slot(at: CGPoint(x: size.width - 1, y: size.height - 1)))
    }

    /// 外周のアイコンは、格子の少し外側を押しても当たる（場所によって反応が違う問題の再発防止）
    func testTouchesJustOutsideTheEdgeHitTheNearestCell() {
        let m = metrics(iconScale: 0.6)
        let rect = m.latticeRect
        XCTAssertEqual(m.slot(at: CGPoint(x: rect.minX - 10, y: rect.minY + 5)), 0)
        XCTAssertEqual(m.slot(at: CGPoint(x: rect.maxX + 10, y: rect.maxY + 10)), layout.capacity - 1)
        XCTAssertNil(m.slot(at: CGPoint(x: rect.minX - GridMetrics.edgeHitSlop - 5, y: rect.midY)))
    }

    func testLatticeIsCentredHorizontally() {
        let m = metrics()
        let left = m.latticeRect.minX
        let right = size.width - m.latticeRect.maxX
        XCTAssertEqual(left, right, accuracy: 0.5)
    }

    func testVerticalOffsetStaysInsideTheArea() {
        for offset in [-1000.0, -50, 0, 50, 1000] {
            let rect = metrics(offsetY: offset, iconScale: 0.6).latticeRect
            XCTAssertGreaterThanOrEqual(rect.minY, -0.5, "offset \(offset)")
            XCTAssertLessThanOrEqual(rect.maxY, size.height + 0.5, "offset \(offset)")
        }
    }

    func testVerticalOffsetMovesTheGrid() {
        let centred = metrics(iconScale: 0.6).latticeRect.minY
        let moved = metrics(offsetY: 20, iconScale: 0.6).latticeRect.minY
        XCTAssertEqual(moved - centred, 20, accuracy: 0.5)
    }
}

final class GroupEntranceTests: XCTestCase {
    // 3 列のグリッドで、中央（4）からの距離
    func testOrthogonalNeighbourIsOne() {
        XCTAssertEqual(GroupEntrance.distance(1, from: 4, columns: 3), 1)
        XCTAssertEqual(GroupEntrance.distance(3, from: 4, columns: 3), 1)
    }

    func testDiagonalNeighbourIsOneAndAHalf() {
        XCTAssertEqual(GroupEntrance.distance(0, from: 4, columns: 3), 1.5)
        XCTAssertEqual(GroupEntrance.distance(8, from: 4, columns: 3), 1.5)
    }

    func testMixedStepsAddUp() {
        // 5 列: 0 から 7 は横に 2・下に 1 → 斜め 1.5 + 横 1 = 2.5
        XCTAssertEqual(GroupEntrance.distance(7, from: 0, columns: 5), 2.5)
    }

    func testFarCellsAreCappedAtThree() {
        XCTAssertEqual(GroupEntrance.distance(24, from: 0, columns: 5), GroupEntrance.maxDistance)
        XCTAssertEqual(GroupEntrance.distance(3, from: 0, columns: 5), 3)
    }
}

/// グループを長押ししても開かないことがある不具合の再発防止
final class TouchSessionTests: XCTestCase {
    func testFirstEventStartsATouch() {
        var session = TouchSession()
        XCTAssertTrue(session.begin(at: CGPoint(x: 10, y: 10)))
        XCTAssertTrue(session.isActive)
    }

    func testLaterEventsOfTheSameTouchAreNotNew() {
        var session = TouchSession()
        _ = session.begin(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(session.begin(at: CGPoint(x: 10, y: 10)))
    }

    func testNextTouchIsNewAfterANormalEnd() {
        var session = TouchSession()
        _ = session.begin(at: CGPoint(x: 10, y: 10))
        session.end()
        XCTAssertTrue(session.begin(at: CGPoint(x: 10, y: 10)))
    }

    /// 終わりの通知が来なかった（取り消された）あとでも、次のタッチは新しいタッチになる
    func testNextTouchIsNewEvenIfTheEndWasMissed() {
        var session = TouchSession()
        _ = session.begin(at: CGPoint(x: 10, y: 10))
        XCTAssertTrue(session.begin(at: CGPoint(x: 200, y: 300)))
    }
}

import XCTest
import UIKit
import SwiftUI
@testable import Geode

/// iPad の回転: iOS の回転のアニメーションの代わりに、中身だけを回す仕組み
final class CanvasRotationTests: XCTestCase {
    /// 回転の変換から角度（度）を読む。回転を伴わない大きさの変更は 0
    func testDegreesOfTransitionTransform() {
        XCTAssertEqual(CanvasRotation.degrees(of: .identity), 0)
        XCTAssertEqual(CanvasRotation.degrees(of: CGAffineTransform(rotationAngle: .pi / 2)), 90)
        XCTAssertEqual(CanvasRotation.degrees(of: CGAffineTransform(rotationAngle: -.pi / 2)), -90)
        XCTAssertEqual(CanvasRotation.degrees(of: CGAffineTransform(rotationAngle: .pi)), 180)
        // 誤差があっても 90° 単位に丸める
        XCTAssertEqual(CanvasRotation.degrees(of: CGAffineTransform(rotationAngle: .pi / 2 + 0.0001)), 90)
    }

    /// 回転の瞬間は中身を逆向きに回して前の配置のまま残し、終わったら 0° に戻して配置を切り替える
    @MainActor
    func testRotationKeepsTheOldLookThenAnimatesBack() {
        let canvas = CanvasOrientation.shared
        canvas.windowResized(to: CGSize(width: 1032, height: 1376))
        XCTAssertFalse(canvas.isLandscape)

        canvas.windowWillRotate(by: 90)
        XCTAssertEqual(canvas.degrees, -90)
        canvas.windowResized(to: CGSize(width: 1376, height: 1032))
        XCTAssertFalse(canvas.isLandscape, "回転が終わるまでは前の配置のまま")

        canvas.windowDidRotate()
        XCTAssertEqual(canvas.degrees, 0)
        XCTAssertTrue(canvas.isLandscape)

        // 回転を伴わない大きさの変更（Split View など）は、そのまま配置だけ切り替える
        canvas.windowResized(to: CGSize(width: 500, height: 1032))
        XCTAssertFalse(canvas.isLandscape)
        XCTAssertEqual(canvas.degrees, 0)
    }

    func testQuarterTurnDetection() {
        XCTAssertTrue(CanvasRotation.isQuarterTurn(90))
        XCTAssertTrue(CanvasRotation.isQuarterTurn(-270))
        XCTAssertFalse(CanvasRotation.isQuarterTurn(180))
        XCTAssertFalse(CanvasRotation.isQuarterTurn(360))
    }

    /// 安全領域は、回した中身から見た上下左右に入れ替わる
    func testInsetsFollowTheRotation() {
        let p = EdgeInsets(top: 24, leading: 1, bottom: 20, trailing: 2)
        XCTAssertEqual(CanvasRotation.canvasInsets(p, degrees: 0), p)
        XCTAssertEqual(CanvasRotation.canvasInsets(p, degrees: 90),
                       EdgeInsets(top: 2, leading: 24, bottom: 1, trailing: 20))
        XCTAssertEqual(CanvasRotation.canvasInsets(p, degrees: -90),
                       EdgeInsets(top: 1, leading: 20, bottom: 2, trailing: 24))
        XCTAssertEqual(CanvasRotation.canvasInsets(p, degrees: 180),
                       EdgeInsets(top: 20, leading: 2, bottom: 24, trailing: 1))
    }
}

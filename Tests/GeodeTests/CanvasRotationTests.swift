import XCTest
import UIKit
import SwiftUI
@testable import Geode

/// iPad で画面を縦に固定したまま中身だけを回す仕組み
final class CanvasRotationTests: XCTestCase {
    func testDeviceOrientationMapsToRotationAndContentOrientation() {
        XCTAssertEqual(CanvasRotation.target(for: .portrait)?.degrees, 0)
        XCTAssertEqual(CanvasRotation.target(for: .landscapeLeft)?.degrees, 90)
        XCTAssertEqual(CanvasRotation.target(for: .landscapeLeft)?.orientation, .landscapeRight)
        XCTAssertEqual(CanvasRotation.target(for: .landscapeRight)?.degrees, -90)
        XCTAssertEqual(CanvasRotation.target(for: .landscapeRight)?.orientation, .landscapeLeft)
        XCTAssertEqual(CanvasRotation.target(for: .portraitUpsideDown)?.degrees, 180)
    }

    /// 平置き・裏返し・不明のときは向きを変えない
    func testFlatAndUnknownKeepTheLastOrientation() {
        XCTAssertNil(CanvasRotation.target(for: .faceUp))
        XCTAssertNil(CanvasRotation.target(for: .faceDown))
        XCTAssertNil(CanvasRotation.target(for: .unknown))
    }

    /// 回る量が少ない方向へ進む（-90 → 180 は 270° ではなく -90° 回る）
    func testNextAngleTakesTheShortestTurn() {
        XCTAssertEqual(CanvasRotation.nextAngle(current: 0, target: 90), 90)
        XCTAssertEqual(CanvasRotation.nextAngle(current: 90, target: -90), -90)
        XCTAssertEqual(CanvasRotation.nextAngle(current: -90, target: 180), -180)
        XCTAssertEqual(CanvasRotation.nextAngle(current: 270, target: 0), 360)
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

    /// 中身の座標の傾きを端末の座標に戻すと、GlowMotion.screenGravity の逆になる
    func testDeviceVectorInvertsScreenGravity() {
        for orientation in [UIInterfaceOrientation.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight] {
            let device = (x: 0.3, y: -0.7)
            let screen = GlowMotion.screenGravity(x: device.x, y: device.y, orientation: orientation)
            let back = CanvasRotation.deviceVector(fromScreen: CGSize(width: screen.x, height: screen.y),
                                                   orientation: orientation)
            XCTAssertEqual(back.width, device.x, accuracy: 1e-9, "\(orientation.rawValue)")
            XCTAssertEqual(back.height, device.y, accuracy: 1e-9, "\(orientation.rawValue)")
        }
    }
}

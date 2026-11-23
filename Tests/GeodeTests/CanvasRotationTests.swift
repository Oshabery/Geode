import XCTest
import UIKit
@testable import Geode

/// iPad の回転: グリッドと背景は端末に対して動かさず、アイコンだけを持った向きに回す仕組み
final class CanvasRotationTests: XCTestCase {
    /// 画面の向き → ウィンドウが端末に対して回っている角度
    func testInterfaceOrientationDegrees() {
        XCTAssertEqual(CanvasRotation.degrees(ofInterface: .portrait), 0)
        XCTAssertEqual(CanvasRotation.degrees(ofInterface: .landscapeRight), 90)
        XCTAssertEqual(CanvasRotation.degrees(ofInterface: .landscapeLeft), -90)
        XCTAssertEqual(CanvasRotation.degrees(ofInterface: .portraitUpsideDown), 180)
    }

    /// アイコンは回る量が少ない方向へ回る（累積値。半周ちょうどはどちら向きでもよい）
    func testNextAngleTakesTheShortestTurn() {
        XCTAssertEqual(CanvasRotation.nextAngle(current: 0, target: 90), 90)
        XCTAssertEqual(CanvasRotation.nextAngle(current: -90, target: 180), -180)
        XCTAssertEqual(CanvasRotation.nextAngle(current: 270, target: 0), 360)
        XCTAssertEqual(abs(CanvasRotation.nextAngle(current: 90, target: -90) - 90), 180)
    }

    func testQuarterTurnDetection() {
        XCTAssertTrue(CanvasRotation.isQuarterTurn(90))
        XCTAssertTrue(CanvasRotation.isQuarterTurn(-270))
        XCTAssertFalse(CanvasRotation.isQuarterTurn(180))
        XCTAssertFalse(CanvasRotation.isQuarterTurn(360))
    }

    /// 動かさないキャンバスは、横向きのウィンドウでも縦持ちのときの大きさ
    func testFixedSizeIsThePortraitWindowSize() {
        let landscape = CGSize(width: 1376, height: 1032)
        XCTAssertEqual(CanvasRotation.fixedSize(window: landscape, windowDegrees: 90), CGSize(width: 1032, height: 1376))
        XCTAssertEqual(CanvasRotation.fixedSize(window: landscape, windowDegrees: -90), CGSize(width: 1032, height: 1376))
        let portrait = CGSize(width: 1032, height: 1376)
        XCTAssertEqual(CanvasRotation.fixedSize(window: portrait, windowDegrees: 0), portrait)
        XCTAssertEqual(CanvasRotation.fixedSize(window: portrait, windowDegrees: 180), portrait)
    }

    /// 変換から回転角を読む（iOS の回転の量）
    func testDegreesOfTransform() {
        XCTAssertEqual(CanvasRotation.degrees(of: .identity), 0, accuracy: 1e-9)
        XCTAssertEqual(CanvasRotation.degrees(of: CGAffineTransform(rotationAngle: .pi / 2)), 90, accuracy: 1e-9)
        XCTAssertEqual(CanvasRotation.degrees(of: CGAffineTransform(rotationAngle: -.pi / 2)), -90, accuracy: 1e-9)
    }

    /// 横向きになるとアイコンが回って横の配置になり、縦に戻すと元に戻る
    @MainActor
    func testWindowRotationTurnsIconsAndSwitchesArrangement() {
        let canvas = CanvasOrientation.shared
        canvas.windowRotated(to: 0)
        XCTAssertFalse(canvas.isLandscape)

        canvas.windowRotated(to: 90)
        XCTAssertTrue(canvas.isLandscape)
        XCTAssertEqual(CanvasRotation.normalized(canvas.iconDegrees), 90)

        canvas.windowRotated(to: 0)
        XCTAssertFalse(canvas.isLandscape)
        XCTAssertEqual(CanvasRotation.normalized(canvas.iconDegrees), 0)
    }
}

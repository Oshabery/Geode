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

    /// 端末の向き → 中身を回す角度。平置き・裏返し・不明のときは nil（直前の向きを保つ）
    func testDeviceOrientationMapsToDegrees() {
        XCTAssertEqual(CanvasRotation.degrees(ofDevice: .portrait), 0)
        XCTAssertEqual(CanvasRotation.degrees(ofDevice: .landscapeLeft), 90)
        XCTAssertEqual(CanvasRotation.degrees(ofDevice: .landscapeRight), -90)
        XCTAssertEqual(CanvasRotation.degrees(ofDevice: .portraitUpsideDown), 180)
        XCTAssertNil(CanvasRotation.degrees(ofDevice: .faceUp))
        XCTAssertNil(CanvasRotation.degrees(ofDevice: .unknown))
    }

    /// 角度と画面の向きは行き来できる（端末の landscapeLeft = 画面の landscapeRight）
    func testInterfaceOrientationRoundTrip() {
        for o in [UIInterfaceOrientation.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight] {
            XCTAssertEqual(CanvasRotation.interfaceOrientation(ofDegrees: CanvasRotation.degrees(ofInterface: o)), o)
        }
        XCTAssertEqual(CanvasRotation.interfaceOrientation(ofDegrees: CanvasRotation.degrees(ofDevice: .landscapeLeft)!),
                       .landscapeRight)
    }

    /// 回る量が少ない方向へ進む（累積値。半周ちょうどはどちら向きでもよい）
    func testNextAngleTakesTheShortestTurn() {
        XCTAssertEqual(CanvasRotation.nextAngle(current: 0, target: 90), 90)
        XCTAssertEqual(CanvasRotation.nextAngle(current: -90, target: 180), -180)
        XCTAssertEqual(CanvasRotation.nextAngle(current: 270, target: 0), 360)
        XCTAssertEqual(abs(CanvasRotation.nextAngle(current: 90, target: -90) - 90), 180)
    }

    /// iOS がウィンドウを回すとき（向きを固定できなかったとき）は、回転の瞬間は中身を逆向きに回して前の配置のまま残し、
    /// 終わったら 0° に戻して配置を切り替える
    @MainActor
    func testRotationKeepsTheOldLookThenAnimatesBack() {
        let canvas = CanvasOrientation.shared
        canvas.windowResized(to: CGSize(width: 1032, height: 1376))
        XCTAssertFalse(canvas.isLandscape)

        canvas.windowWillRotate(by: 90)
        XCTAssertEqual(canvas.counter?.degrees, -90)
        XCTAssertEqual(canvas.counter?.windowSize, CGSize(width: 1032, height: 1376))
        canvas.windowResized(to: CGSize(width: 1376, height: 1032))
        XCTAssertFalse(canvas.isLandscape, "回転が終わるまでは前の配置のまま")

        canvas.windowDidRotate()
        XCTAssertNil(canvas.counter)
        XCTAssertEqual(canvas.degrees, 0)
        XCTAssertTrue(canvas.isLandscape)

        // 回転を伴わない大きさの変更（Split View など）は、そのまま配置だけ切り替える
        canvas.windowResized(to: CGSize(width: 500, height: 1032))
        XCTAssertFalse(canvas.isLandscape)
        XCTAssertEqual(canvas.degrees, 0)
    }

    /// 90° 回すときは中身の縦横を入れ替える
    func testCanvasSizeSwapsOnQuarterTurns() {
        let w = CGSize(width: 1376, height: 1032)
        XCTAssertEqual(CanvasRotation.canvasSize(window: w, degrees: 0), w)
        XCTAssertEqual(CanvasRotation.canvasSize(window: w, degrees: -90), CGSize(width: 1032, height: 1376))
        XCTAssertEqual(CanvasRotation.canvasSize(window: w, degrees: 180), w)
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

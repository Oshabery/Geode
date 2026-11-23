import SwiftUI
import UIKit

/// iPad を回したとき、画面（ウィンドウ）は縦のまま固定し、Geode の中身（上のボタンとグリッド）だけを回す。
/// iOS の回転は画面全体を回して伸縮させ、四隅が黒く見えるため（ユーザーの指定）
enum CanvasRotation {
    /// 回したキャンバスの座標空間の名前（グループの背景がキャンバス全体を覆うために使う）
    static let coordinateSpace = "geodeCanvas"

    /// 端末の向き → 中身を回す角度（度。SwiftUI の rotationEffect と同じく時計回りが正）と、
    /// 回した中身にとっての画面の向き。平置き・裏返し・不明のときは nil（直前の向きを保つ）
    static func target(for device: UIDeviceOrientation) -> (degrees: Double, orientation: UIInterfaceOrientation)? {
        switch device {
        case .portrait: return (0, .portrait)
        case .portraitUpsideDown: return (180, .portraitUpsideDown)
        // 端末の landscapeLeft（ホームボタン側が右）は、画面の向きでは landscapeRight にあたる
        case .landscapeLeft: return (90, .landscapeRight)
        case .landscapeRight: return (-90, .landscapeLeft)
        default: return nil
        }
    }

    /// ウィンドウが実際に向いている角度（縦固定が効いていれば 0）。
    /// 固定が効かずに iOS がウィンドウを回した場合は、その分を差し引いて中身が二重に回らないようにする
    static func degrees(ofInterface orientation: UIInterfaceOrientation) -> Double {
        switch orientation {
        case .portraitUpsideDown: return 180
        case .landscapeRight: return 90
        case .landscapeLeft: return -90
        default: return 0
        }
    }

    /// 今の角度から目標の角度へ、回る量が少ない方向で進めた角度（累積値。アニメーションが一周しないように）
    static func nextAngle(current: Double, target: Double) -> Double {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta <= -180 { delta += 360 }
        return current + delta
    }

    /// 角度を 0 / 90 / 180 / -90 のどれかに直す
    static func normalized(_ degrees: Double) -> Double {
        let d = ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let snapped = (d / 90).rounded() * 90
        switch snapped {
        case 90: return 90
        case 180: return 180
        case 270: return -90
        default: return 0
        }
    }

    /// 90° 回して縦横が入れ替わっているか
    static func isQuarterTurn(_ degrees: Double) -> Bool { abs(normalized(degrees)) == 90 }

    /// 縦固定のウィンドウの安全領域（ステータスバーやホームインジケーター）を、回した中身から見た上下左右に直す
    static func canvasInsets(_ p: EdgeInsets, degrees: Double) -> EdgeInsets {
        switch normalized(degrees) {
        case 90:   // 中身の上 = 画面の右
            return EdgeInsets(top: p.trailing, leading: p.top, bottom: p.leading, trailing: p.bottom)
        case -90:  // 中身の上 = 画面の左
            return EdgeInsets(top: p.leading, leading: p.bottom, bottom: p.trailing, trailing: p.top)
        case 180:
            return EdgeInsets(top: p.bottom, leading: p.trailing, bottom: p.top, trailing: p.leading)
        default:
            return p
        }
    }

    /// 回した中身の座標で表した傾きを、端末の座標に戻す（GlowMotion.screenGravity の逆）
    static func deviceVector(fromScreen v: CGSize, orientation: UIInterfaceOrientation) -> CGSize {
        switch orientation {
        case .portraitUpsideDown: return CGSize(width: -v.width, height: -v.height)
        case .landscapeRight: return CGSize(width: v.height, height: -v.width)
        case .landscapeLeft: return CGSize(width: -v.height, height: v.width)
        default: return v
        }
    }
}

/// 回したキャンバスの大きさ（iPad のみ。iPhone では nil）。グループの背景がキャンバス全体を覆うために使う
private struct CanvasSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

extension EnvironmentValues {
    var geodeCanvasSize: CGSize? {
        get { self[CanvasSizeKey.self] }
        set { self[CanvasSizeKey.self] = newValue }
    }
}

/// 端末の向きを見て、中身を回す角度を決める（iPad のみ。iPhone は常に縦）
@MainActor
final class CanvasOrientation: ObservableObject {
    static let shared = CanvasOrientation()

    /// 中身を回す角度（累積値）
    @Published private(set) var degrees: Double = 0
    /// 回した中身にとっての画面の向き。縦と横の配置の切り替え、グローの傾きの向きに使う
    @Published private(set) var contentOrientation: UIInterfaceOrientation = .portrait

    /// 回すときにアニメーションするか。起動して最初に向きが分かったときは、縦から回って見えないようにすぐ合わせる
    @Published private(set) var animates = false

    var isLandscape: Bool { contentOrientation.isLandscape }

    private init() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        // 起動時に向きが分からない（平置きなど）ときは縦として始める
        update()
    }

    /// ウィンドウが実際に向いている向き（縦固定が効いていれば縦）
    var windowOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .effectiveGeometry.interfaceOrientation ?? .portrait
    }

    func update() {
        guard let target = CanvasRotation.target(for: UIDevice.current.orientation) else { return }
        let wanted = target.degrees - CanvasRotation.degrees(ofInterface: windowOrientation)
        let next = CanvasRotation.nextAngle(current: degrees, target: wanted)
        if next != degrees { degrees = next }
        if target.orientation != contentOrientation { contentOrientation = target.orientation }
        if !animates {
            // 最初の向きを反映した描画が済んでから、以後の回転をアニメーションにする
            DispatchQueue.main.async { self.animates = true }
        }
    }
}

import SwiftUI
import UIKit

/// iPad を回したときの見せ方（ユーザーの指定）。
/// iOS の回転アニメーションは画面全体を回して伸縮させ、四隅が黒く見える。そこで回転のアニメーションだけを止め、
/// ウィンドウは一瞬で新しい向きに切り替える。その瞬間、中身（上のボタンとグリッド）を逆向きに回して元の見た目のまま残し、
/// そこから Geode 自身のアニメーションで、回転・大きさ・アイコンの並びを新しい向きへ動かす。背景は回さない。
/// シート・キーボード・Split View などは iOS の通常の回転のまま
enum CanvasRotation {
    /// 回したキャンバスの座標空間の名前（グループの背景がキャンバス全体を覆うために使う）
    static let coordinateSpace = "geodeCanvas"

    /// 回転の変換（`UIViewControllerTransitionCoordinator.targetTransform`）の角度（度、時計回りが正）。
    /// 回転を伴わない大きさの変更（Split View など）では 0
    static func degrees(of transform: CGAffineTransform) -> Double {
        normalized(atan2(Double(transform.b), Double(transform.a)) * 180 / .pi)
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

    /// ウィンドウの安全領域（ステータスバーやホームインジケーター）を、回した中身から見た上下左右に直す
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

/// 中身を回す角度と、どちらの向きの配置を出すかを持つ（iPad のみ。iPhone は常に縦で角度 0）
@MainActor
final class CanvasOrientation: ObservableObject {
    static let shared = CanvasOrientation()

    /// 中身をウィンドウに対して回している角度。ふだんは 0。回転の直後だけ逆向きの角度になり、0 へ戻る
    @Published private(set) var degrees: Double = 0
    /// 横画面の配置を出すか（ウィンドウが横長か）。回転中は、戻すアニメーションが始まるまで前の向きのまま
    @Published private(set) var isLandscape = false

    static let animation = Animation.spring(duration: 0.5, bounce: 0.1)

    /// iOS の回転が進行中（ウィンドウは新しい向き、中身は逆向きに回して前の見た目のまま）
    private var rotating = false
    /// いまのウィンドウの大きさ
    private var windowSize: CGSize = .zero

    private init() {}

    /// iOS がウィンドウを回す直前。中身を逆向きに回して、切り替わった瞬間も前と同じ見た目にする
    func windowWillRotate(by angle: Double) {
        rotating = true
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { degrees = CanvasRotation.normalized(-angle) }
    }

    /// iOS の回転が終わった。中身を新しい向きへ回し、配置も切り替える
    func windowDidRotate() {
        guard rotating else { return }
        rotating = false
        let landscape = windowSize.width > windowSize.height
        withAnimation(Self.animation) {
            degrees = 0
            isLandscape = landscape
        }
    }

    /// ウィンドウの大きさが変わった（起動時、回転、Split View など）
    func windowResized(to size: CGSize) {
        windowSize = size
        // 回転中は windowDidRotate でまとめて切り替える
        guard !rotating else { return }
        let landscape = size.width > size.height
        if landscape != isLandscape { isLandscape = landscape }
    }
}

/// iOS の回転を受け取り、回転のアニメーションを止めて、中身を Geode 自身で回す。
/// 画面に何も描かない小さなビュー。見えている UIViewController の子として回転の通知を受ける
struct RotationHook: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            let angle = CanvasRotation.degrees(of: coordinator.targetTransform)
            // 回転を伴わない大きさの変更（Split View など）は iOS のまま。
            // UI テストの比較用（-GeodeSystemRotation）では iOS の回転のアニメーションをそのまま出す
            guard angle != 0, !CommandLine.arguments.contains("-GeodeSystemRotation") else { return }
            UIView.setAnimationsEnabled(false)
            CanvasOrientation.shared.windowWillRotate(by: angle)
            coordinator.animate(alongsideTransition: nil) { _ in
                UIView.setAnimationsEnabled(true)
                CanvasOrientation.shared.windowDidRotate()
            }
        }
    }
}

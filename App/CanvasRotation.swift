import ObjectiveC
import SwiftUI
import UIKit

/// iPad を回したときの見せ方（ユーザーの指定: 画面は動かさず、ボタンとアイコンの並びだけが入れ替わって見えるように）。
///
/// 1. ウィンドウの向きを固定できるとき（iPadOS 26 の `prefersInterfaceOrientationLocked`。カメラ App と同じ仕組み）:
///    ウィンドウは回さず、端末の向きに合わせて中身（上のボタンとグリッド）だけを Geode が回す。
/// 2. 固定できないとき（iPadOS 17/18、または iOS が固定を受け付けなかったとき）:
///    iOS の回転のアニメーション（画面全体が回り四隅が黒く見える）を止めてウィンドウを一瞬で切り替え、
///    その瞬間は中身を逆向きに回して前の見た目のまま残し、そこから Geode のアニメーションで新しい向きへ動かす。
/// 背景はどちらでも回さない
enum CanvasRotation {
    /// 回したキャンバスの座標空間の名前（グループの背景がキャンバス全体を覆うために使う）
    static let coordinateSpace = "geodeCanvas"

    /// 端末の向き → 画面の座標で見た角度（度。SwiftUI の rotationEffect と同じく時計回りが正）。
    /// 平置き・裏返し・不明のときは nil（直前の向きを保つ）
    static func degrees(ofDevice device: UIDeviceOrientation) -> Double? {
        switch device {
        case .portrait: return 0
        case .portraitUpsideDown: return 180
        // 端末の landscapeLeft（ホームボタン側が右）は、画面の向きでは landscapeRight にあたる
        case .landscapeLeft: return 90
        case .landscapeRight: return -90
        default: return nil
        }
    }

    /// 画面の向き → 角度（度）
    static func degrees(ofInterface orientation: UIInterfaceOrientation) -> Double {
        switch orientation {
        case .portraitUpsideDown: return 180
        case .landscapeRight: return 90
        case .landscapeLeft: return -90
        default: return 0
        }
    }

    /// 角度（度）→ 画面の向き
    static func interfaceOrientation(ofDegrees degrees: Double) -> UIInterfaceOrientation {
        switch normalized(degrees) {
        case 90: return .landscapeRight
        case -90: return .landscapeLeft
        case 180: return .portraitUpsideDown
        default: return .portrait
        }
    }

    /// 回転の変換（`UIViewControllerTransitionCoordinator.targetTransform`）の角度（度、時計回りが正）。
    /// 回転を伴わない大きさの変更（Split View など）では 0
    static func degrees(of transform: CGAffineTransform) -> Double {
        normalized(atan2(Double(transform.b), Double(transform.a)) * 180 / .pi)
    }

    /// 今の角度から目標の角度へ、回る量が少ない方向で進めた角度（累積値。アニメーションが一周しないように）
    static func nextAngle(current: Double, target: Double) -> Double {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
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

    /// 回した中身の大きさ（90° 回すときは縦横を入れ替える）
    static func canvasSize(window: CGSize, degrees: Double) -> CGSize {
        isQuarterTurn(degrees) ? CGSize(width: window.height, height: window.width) : window
    }

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

/// 中身を回す角度と、どちらの向きの配置を出すかを持つ（iPad のみ。iPhone は常に縦で角度 0）
@MainActor
final class CanvasOrientation: ObservableObject {
    static let shared = CanvasOrientation()
    static let animation = Animation.spring(duration: 0.5, bounce: 0.1)

    /// iOS がウィンドウを回している最中の、中身の逆向きの角度と、回す前のウィンドウの大きさ
    struct Counter: Equatable {
        var degrees: Double
        var windowSize: CGSize
    }

    /// 中身をウィンドウに対して回している角度（累積値）。ウィンドウの向きが固定されていれば端末の向きに合わせて変わり、
    /// 固定されていなければ 0
    @Published private(set) var degrees: Double = 0
    /// 横画面の配置を出すか（回した中身が横長か）
    @Published private(set) var isLandscape = false
    /// iOS がウィンドウを回している最中（固定できなかったとき）。回転が終わると nil に戻し、中身を新しい向きへ動かす
    @Published private(set) var counter: Counter?

    /// いまのウィンドウの大きさ
    private var windowSize: CGSize = .zero

    private init() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in CanvasOrientation.shared.deviceChanged() }
        }
    }

    private var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    /// ウィンドウが実際に向いている向き
    var windowOrientation: UIInterfaceOrientation {
        scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    /// 回した中身にとっての画面の向き（グローの傾きの向きに使う）
    var contentOrientation: UIInterfaceOrientation {
        CanvasRotation.interfaceOrientation(ofDegrees: CanvasRotation.degrees(ofInterface: windowOrientation) + degrees)
    }

    /// ウィンドウの向きが固定されているか（iPadOS 26 以降）
    private var windowLocked: Bool {
        if #available(iOS 26.0, *) {
            return scene?.effectiveGeometry.isInterfaceOrientationLocked ?? false
        }
        return false
    }

    private func landscape(window: CGSize, degrees: Double) -> Bool {
        let size = CanvasRotation.canvasSize(window: window, degrees: degrees)
        return size.width > size.height
    }

    /// 端末の向きが変わった。ウィンドウが固定されていれば、中身だけを端末の向きへ回す
    func deviceChanged() {
        guard counter == nil, windowLocked,
              let device = CanvasRotation.degrees(ofDevice: UIDevice.current.orientation) else { return }
        let wanted = device - CanvasRotation.degrees(ofInterface: windowOrientation)
        let next = CanvasRotation.nextAngle(current: degrees, target: wanted)
        guard next != degrees else { return }
        let landscape = landscape(window: windowSize, degrees: next)
        withAnimation(Self.animation) {
            degrees = next
            isLandscape = landscape
        }
    }

    /// ウィンドウの向きの固定が外れた（または固定できなかった）ときは、中身の角度を 0 に戻す
    func lockMayHaveChanged() {
        if windowLocked {
            deviceChanged()
        } else if counter == nil, CanvasRotation.normalized(degrees) != 0 {
            let landscape = landscape(window: windowSize, degrees: 0)
            withAnimation(Self.animation) {
                degrees = 0
                isLandscape = landscape
            }
        }
    }

    /// iOS がウィンドウを回す直前（固定できなかったとき）。中身を逆向きに回して、切り替わった瞬間も前と同じ見た目にする
    func windowWillRotate(by angle: Double) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            counter = Counter(degrees: CanvasRotation.normalized(degrees - angle), windowSize: windowSize)
        }
    }

    /// iOS の回転が終わった。中身を新しい向きへ回し、配置も切り替える
    func windowDidRotate() {
        guard counter != nil else { return }
        let landscape = landscape(window: windowSize, degrees: 0)
        withAnimation(Self.animation) {
            counter = nil
            degrees = 0
            isLandscape = landscape
        }
    }

    /// ウィンドウの大きさが変わった（起動時、回転、Split View など）
    func windowResized(to size: CGSize) {
        windowSize = size
        // iOS の回転中は windowDidRotate でまとめて切り替える
        guard counter == nil else { return }
        let landscape = landscape(window: size, degrees: degrees)
        if landscape != isLandscape { isLandscape = landscape }
    }
}

/// iPadOS 26 の `prefersInterfaceOrientationLocked` を、SwiftUI が作るルートの UIViewController で true にする。
/// SwiftUI にはこの設定が無く、ルートの UIViewController は差し替えられないため、getter を入れ替えて答える
enum OrientationLock {
    /// 向きを固定するルートの UIViewController
    private static weak var lockedRoot: UIViewController?
    private static var installed = false

    static func isLocked(_ controller: UIViewController) -> Bool { controller === lockedRoot }

    static func lock(_ root: UIViewController) {
        guard #available(iOS 26.0, *) else { return }
        if !installed {
            installed = true
            guard let original = class_getInstanceMethod(UIViewController.self,
                                                         #selector(getter: UIViewController.prefersInterfaceOrientationLocked)),
                  let replacement = class_getInstanceMethod(UIViewController.self,
                                                            #selector(getter: UIViewController.geode_prefersInterfaceOrientationLocked))
            else { return }
            method_exchangeImplementations(original, replacement)
        }
        guard lockedRoot !== root else { return }
        lockedRoot = root
        root.setNeedsUpdateOfPrefersInterfaceOrientationLocked()
    }
}

extension UIViewController {
    /// `prefersInterfaceOrientationLocked` と入れ替える getter（OrientationLock）。
    /// 入れ替え後は、自分自身の呼び出しが元の実装を呼ぶ
    @objc var geode_prefersInterfaceOrientationLocked: Bool {
        OrientationLock.isLocked(self) || geode_prefersInterfaceOrientationLocked
    }
}

/// iOS の回転を受け取る、画面に何も描かない小さなビュー（見えている UIViewController の子になる）。
/// ルートの UIViewController にウィンドウの向きの固定を頼み、固定できなかったときは回転のアニメーションを止めて中身を Geode が回す
struct RotationHook: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        /// UI テストの比較用（-GeodeSystemRotation）: 何もせず、iOS の回転のアニメーションをそのまま出す
        private let systemRotation = CommandLine.arguments.contains("-GeodeSystemRotation")
        /// UI テスト用（-GeodeNoOrientationLock）: 向きを固定しない（固定できなかったときの動きを確かめる）
        private let noLock = CommandLine.arguments.contains("-GeodeNoOrientationLock")

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !systemRotation, !noLock, let root = view.window?.rootViewController else { return }
            OrientationLock.lock(root)
            // 固定が効いたかどうかは少し後に分かる。効いていれば今の端末の向きに中身を合わせる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                CanvasOrientation.shared.lockMayHaveChanged()
            }
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            let angle = CanvasRotation.degrees(of: coordinator.targetTransform)
            // 回転を伴わない大きさの変更（Split View など）は iOS のまま
            guard angle != 0, !systemRotation else { return }
            UIView.setAnimationsEnabled(false)
            CanvasOrientation.shared.windowWillRotate(by: angle)
            coordinator.animate(alongsideTransition: nil) { _ in
                UIView.setAnimationsEnabled(true)
                CanvasOrientation.shared.windowDidRotate()
            }
        }
    }
}

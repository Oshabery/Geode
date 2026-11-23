import SwiftUI
import UIKit

/// iPad を回したときの見せ方（ユーザーの指定）:
/// - グリッド（マス目・行と列）と背景は、ガラス面に貼り付いたように動かさない（`FixedCanvas`）
/// - アイコンだけが、持った向きで読める向きに回り、縦用 / 横用の配置へ入れ替わる
/// - 上の「設定」「編集」ボタンは、持った向きの上の角へ移る（ウィンドウと一緒に iOS が回す）
///
/// 仕組み: ウィンドウの向きは iOS が変えるが、回転のアニメーションは止めて一瞬で切り替える
/// （アニメーションさせると、iPadOS 26 ではウィンドウごと回る様子が見え、中で逆に回してもグリッドが傾いて見えた。CI の録画で確認）。
/// グリッドと背景は UIKit のビューに入れ、ウィンドウの回転の逆向きに回して置くので、切り替わっても画面上の位置が変わらない。
/// 切り替わった直後に、アイコンだけを Geode のアニメーションで持った向きへ回し、縦 / 横の並びへ動かす。
/// シート・キーボード・Split View は iOS の通常どおり
enum CanvasRotation {
    /// 動かさないキャンバスの座標空間の名前（グループの背景がキャンバス全体を覆うために使う）
    static let coordinateSpace = "geodeCanvas"

    /// 画面の向き → ウィンドウが端末に対して回っている角度（度。SwiftUI の rotationEffect と同じく時計回りが正）。
    /// landscapeRight はホームボタン側が右（端末を反時計回りに 90° 回した持ち方）
    static func degrees(ofInterface orientation: UIInterfaceOrientation) -> Double {
        switch orientation {
        case .portraitUpsideDown: return 180
        case .landscapeRight: return 90
        case .landscapeLeft: return -90
        default: return 0
        }
    }

    /// 今の角度から目標の角度へ、回る量が少ない方向で進めた角度（累積値。アイコンが一周しないように）
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

    /// ウィンドウの大きさと向きから、端末に対して動かさないキャンバスの大きさ（縦持ちのときのウィンドウの大きさ）
    static func fixedSize(window: CGSize, windowDegrees: Double) -> CGSize {
        isQuarterTurn(windowDegrees) ? CGSize(width: window.height, height: window.width) : window
    }

    /// 変換の回転角（度）
    static func degrees(of transform: CGAffineTransform) -> Double {
        atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
    }
}

/// 動かさないキャンバスの大きさ（iPad のみ。iPhone では nil）。グループの背景がキャンバス全体を覆うために使う
private struct CanvasSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

/// アイコンを回す角度（度）。動かさないキャンバスの中で、持った向きに読めるようにする（iPhone では 0）
private struct IconAngleKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

/// 向きが変わるたびに増える番号。変わるとアイコンが一度消えて、ぷよっと出直す（`OrientationReveal`。iPhone では変わらない）
private struct RevealTokenKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

/// iOS がウィンドウを回している間はアイコンを隠す（iPhone では常に false）
private struct IconsHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var geodeCanvasSize: CGSize? {
        get { self[CanvasSizeKey.self] }
        set { self[CanvasSizeKey.self] = newValue }
    }

    var geodeIconAngle: Double {
        get { self[IconAngleKey.self] }
        set { self[IconAngleKey.self] = newValue }
    }

    var geodeRevealToken: Int {
        get { self[RevealTokenKey.self] }
        set { self[RevealTokenKey.self] = newValue }
    }

    var geodeIconsHidden: Bool {
        get { self[IconsHiddenKey.self] }
        set { self[IconsHiddenKey.self] = newValue }
    }
}

/// ウィンドウが端末に対して回っている角度と、縦 / 横どちらの配置を出すか（iPad のみ。iPhone は常に縦）
@MainActor
final class CanvasOrientation: ObservableObject {
    static let shared = CanvasOrientation()

    /// アイコンを回す角度（累積値。ウィンドウの角度と同じ向き）
    @Published private(set) var iconDegrees: Double = 0
    /// 横画面の配置を出すか（ウィンドウが端末に対して 90° 回っているか）
    @Published private(set) var isLandscape = false
    /// iOS がウィンドウを回している間、アイコンを隠す（回転の途中で、古い並び・新しい並びが傾いて見えないように）
    @Published private(set) var iconsHidden = false
    /// 隠したアイコンを出し直すたびに増える番号（`OrientationReveal` のきっかけ）
    @Published private(set) var revealToken = 0

    private init() {}

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// ウィンドウの向きが分かった・変わった。アイコンの向きと縦 / 横の並びを、アニメーションなしで変える
    func windowRotated(to degrees: Double) {
        let next = CanvasRotation.nextAngle(current: iconDegrees, target: CanvasRotation.normalized(degrees))
        let landscape = CanvasRotation.isQuarterTurn(degrees)
        guard next != iconDegrees || landscape != isLandscape else { return }
        withoutAnimation {
            iconDegrees = next
            isLandscape = landscape
        }
    }

    /// iOS がウィンドウを回し始める。アイコンを一瞬で隠す
    func hideIcons() {
        guard !iconsHidden else { return }
        withoutAnimation { iconsHidden = true }
    }

    /// 回転が終わった（UIView のアニメーションを戻した後に呼ぶ）。隠したアイコンを、ぷよっと弾ませて出し直す。
    /// 回転の途中で始めると、アニメーションが止められて一瞬で終わってしまうため、必ず回転の後に始める
    func revealIcons() {
        withoutAnimation {
            iconsHidden = false
            revealToken &+= 1
        }
    }
}

/// グリッドと背景を入れる、端末に対して動かさないキャンバス（iPad 用）。
/// 中身は端末を縦に持ったときの大きさで描き、ウィンドウの回転の逆向きに回して置く
struct FixedCanvas<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> FixedCanvasController<Content> {
        FixedCanvasController(rootView: content)
    }

    func updateUIViewController(_ controller: FixedCanvasController<Content>, context: Context) {
        controller.host.rootView = content
    }
}

final class FixedCanvasController<Content: View>: UIViewController {
    let host: UIHostingController<Content>
    /// iOS がウィンドウを回している最中（置き直しは回転の処理の中で行う）
    private var transitioning = false
    /// UI テストの比較用（-GeodeSystemRotation）: 逆向きに回さず、iOS の回転のまま（四隅が黒く見える従来の動き）
    private let systemRotation = CommandLine.arguments.contains("-GeodeSystemRotation")

    init(rootView: Content) {
        host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        // 安全領域は Geode が自分で空ける（回したビューの中では iOS の計算が合わないため）
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = []
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// ウィンドウが端末に対して回っている角度（度）
    private var windowDegrees: Double {
        guard !systemRotation, let scene = view.window?.windowScene else { return 0 }
        return CanvasRotation.degrees(ofInterface: scene.effectiveGeometry.interfaceOrientation)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !transitioning else { return }
        place(windowDegrees: windowDegrees)
    }

    /// 端末を縦に持ったときの大きさで描き、ウィンドウの回転の逆向きに回して中央に置く
    private func place(windowDegrees: Double) {
        let size = CanvasRotation.fixedSize(window: view.bounds.size, windowDegrees: windowDegrees)
        host.view.transform = .identity
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        host.view.transform = CGAffineTransform(rotationAngle: -windowDegrees * .pi / 180)
        CanvasOrientation.shared.windowRotated(to: windowDegrees)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let delta = CanvasRotation.degrees(of: coordinator.targetTransform)
        // 回転を伴わない大きさの変更（Split View など）は、終わってから置き直すだけ
        guard abs(delta) > 1, !systemRotation else {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.view.setNeedsLayout() }
            return
        }
        transitioning = true
        // 回転の間はアイコンを隠す。iOS の回転のアニメーションも止める（止めきれずに一瞬傾いて見えることがある）
        CanvasOrientation.shared.hideIcons()
        UIView.setAnimationsEnabled(false)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            // ウィンドウを回すのと同じ量だけ逆に回す（画面上では動かない）。
            // 180° のときに回る向きが定まるよう、ごくわずかにずらす
            let layer = self.host.view.layer
            let current = (layer.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
            layer.setValue(current - delta * .pi / 180 + 0.0001, forKeyPath: "transform.rotation.z")
            self.host.view.center = CGPoint(x: size.width / 2, y: size.height / 2)
        }, completion: { [weak self] _ in
            UIView.setAnimationsEnabled(true)
            guard let self else { return }
            self.transitioning = false
            // ずらした分と誤差をなくし、ウィンドウの実際の向きで置き直す（アイコンの向きと縦 / 横の並びもここで変わる。隠したまま）
            self.place(windowDegrees: self.windowDegrees)
            // アニメーションを戻した後、次の周回でアイコンを出し直す
            DispatchQueue.main.async { CanvasOrientation.shared.revealIcons() }
        })
    }
}

// MARK: アイコンの出直し

/// 向きが変わったとき、アイコンを一度消してから、ぷよっと弾むように出す（ユーザーの指定）。
/// 出だしと終わりをなめらかにしたカーブ（イーズインアウト）で、横に広がる → 縦に伸びる → 落ち着く、を繰り返して止まる。
/// 縦と横で並びも向きも変わるので、動かして見せるより、いったん消して出し直す方が自然に見えるため
struct OrientationReveal: ViewModifier {
    /// 変わるとアニメーションが始まる番号（`geodeRevealToken`）
    let token: Int
    /// 出始めるまでの遅れ（秒）。中央から外へ、少しずつ遅らせて波のように出す
    var delay: Double = 0
    /// 回転の間は隠す
    var hidden = false

    struct Value {
        var scaleX = 1.0
        var scaleY = 1.0
        var opacity = 1.0
    }

    /// 消えている間の大きさ
    static let hiddenScale = 0.35
    /// 消えたままでいる時間（秒）。回転が終わってから少しおいて出る
    static let hold = 0.03

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Value(), trigger: token) { view, value in
            view
                .scaleEffect(x: value.scaleX, y: value.scaleY)
                .opacity(value.opacity)
        } keyframes: { _ in
            let wait = Self.hold + delay
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: wait)
                CubicKeyframe(1, duration: 0.16)
            }
            KeyframeTrack(\.scaleX) {
                MoveKeyframe(Self.hiddenScale)
                LinearKeyframe(Self.hiddenScale, duration: wait)
                CubicKeyframe(1.14, duration: 0.17)   // 横にふくらむ
                CubicKeyframe(0.93, duration: 0.12)
                CubicKeyframe(1.03, duration: 0.11)
                CubicKeyframe(1.0, duration: 0.12)
            }
            KeyframeTrack(\.scaleY) {
                MoveKeyframe(Self.hiddenScale)
                LinearKeyframe(Self.hiddenScale, duration: wait)
                CubicKeyframe(0.88, duration: 0.17)   // 縦はつぶれる
                CubicKeyframe(1.07, duration: 0.12)
                CubicKeyframe(0.98, duration: 0.11)
                CubicKeyframe(1.0, duration: 0.12)
            }
        }
        .opacity(hidden ? 0 : 1)
    }

    /// マスごとの遅れ: グリッドの中央から離れるほど少し遅らせる（最大 0.12 秒）
    static func delay(slot: Int, layout: GridLayout) -> Double {
        let row = Double(slot / layout.columns), column = Double(slot % layout.columns)
        let dr = row - Double(layout.rows - 1) / 2, dc = column - Double(layout.columns - 1) / 2
        return min(0.12, (dr * dr + dc * dc).squareRoot() * 0.025)
    }
}

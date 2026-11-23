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
}

/// ウィンドウが端末に対して回っている角度と、縦 / 横どちらの配置を出すか（iPad のみ。iPhone は常に縦）
@MainActor
final class CanvasOrientation: ObservableObject {
    static let shared = CanvasOrientation()
    static let animation = Animation.spring(duration: 0.45, bounce: 0.1)

    /// アイコンを回す角度（累積値。ウィンドウの角度と同じ向き）
    @Published private(set) var iconDegrees: Double = 0
    /// 横画面の配置を出すか（ウィンドウが端末に対して 90° 回っているか）
    @Published private(set) var isLandscape = false
    /// 向きが変わるたびに増える番号（アイコンの出直しのきっかけ）
    @Published private(set) var revealToken = 0
    /// 最初に向きが分かったとき（起動時）は出直しのアニメーションをしない
    private var known = false
    /// 最後に向きが変わった時刻（向きの変化で作り直された編集画面が、出直しのアニメーションをするかの判断に使う）
    private(set) var lastReveal = Date.distantPast

    private init() {}

    /// ウィンドウの向きが分かった・変わった。アイコンの向きと縦 / 横の並びを、画面の切り替わりと同時に一瞬で変える
    /// （アニメーションさせると、画面より遅れて回って見えるため。ユーザーの指定）
    func windowRotated(to degrees: Double) {
        let next = CanvasRotation.nextAngle(current: iconDegrees, target: CanvasRotation.normalized(degrees))
        let landscape = CanvasRotation.isQuarterTurn(degrees)
        guard next != iconDegrees || landscape != isLandscape else { known = true; return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            iconDegrees = next
            isLandscape = landscape
            if known {
                revealToken &+= 1
                lastReveal = Date()
            }
        }
        known = true
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

    /// いま置いているウィンドウの角度
    private var placedDegrees: Double = 0

    /// iOS がウィンドウを回している最中の、回った後の角度
    private var pendingDegrees: Double?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if transitioning {
            // ウィンドウが実際に新しい向きの大きさになった瞬間（同じコマ）に、キャンバスとアイコンを切り替える。
            // 回転のアニメーションを止めると、ウィンドウが切り替わるのは回転の最初とは限らないため、大きさの変化で判断する
            guard let pending = pendingDegrees,
                  CanvasRotation.isQuarterTurn(pending - placedDegrees),
                  (view.bounds.width > view.bounds.height) == CanvasRotation.isQuarterTurn(pending) else { return }
            place(windowDegrees: pending)
            return
        }
        place(windowDegrees: windowDegrees)
    }

    /// 端末を縦に持ったときの大きさで描き、ウィンドウの回転の逆向きに回して中央に置く
    private func place(windowDegrees: Double) {
        placedDegrees = windowDegrees
        let size = CanvasRotation.fixedSize(window: view.bounds.size, windowDegrees: windowDegrees)
        host.view.transform = .identity
        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        host.view.transform = CGAffineTransform(rotationAngle: -windowDegrees * .pi / 180)
        CanvasOrientation.shared.windowRotated(to: windowDegrees)
    }

    // MARK: 回転のアニメーションを止める

    /// 止めたアニメーションを、回転が始まらなかったときに戻すための予約
    private var restoreAnimations: DispatchWorkItem?
    private var observingDevice = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !systemRotation, !observingDevice else { return }
        observingDevice = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationChanged),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    /// 端末の向きが変わった（iOS が画面を回し始めるより前に届く）。ここで先にアニメーションを止めておくと、
    /// 回転の最初の 1 コマから止まる（回転の通知を受けてからでは、傾いた画面が一瞬見えていた）
    @objc private func deviceOrientationChanged() {
        guard let target = Self.interfaceOrientation(for: UIDevice.current.orientation),
              let scene = view.window?.windowScene,
              target != scene.effectiveGeometry.interfaceOrientation else { return }
        UIView.setAnimationsEnabled(false)
        // 実際には回らなかったとき（向きのロック中など）のために、少し後に必ず戻す
        restoreAnimations?.cancel()
        let restore = DispatchWorkItem { UIView.setAnimationsEnabled(true) }
        restoreAnimations = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: restore)
    }

    /// 端末の向き → その向きで iOS が回す画面の向き（端末の landscapeLeft は画面の landscapeRight）
    private static func interfaceOrientation(for device: UIDeviceOrientation) -> UIInterfaceOrientation? {
        switch device {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
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
        // iOS の回転のアニメーションを止め、ウィンドウを一瞬で切り替える（端末の向きの通知で止めていなかったとき用）
        UIView.setAnimationsEnabled(false)
        // 回った後の角度。キャンバスはウィンドウの大きさが変わった瞬間に、この角度の逆向きに置き直す（viewDidLayoutSubviews）
        pendingDegrees = CanvasRotation.normalized(placedDegrees + delta)
        coordinator.animate(alongsideTransition: nil, completion: { [weak self] _ in
            self?.restoreAnimations?.cancel()
            UIView.setAnimationsEnabled(true)
            guard let self else { return }
            self.transitioning = false
            self.pendingDegrees = nil
            // ウィンドウの実際の向きで置き直す（180° のように大きさが変わらないときや、食い違っていたときはここで直る）
            self.place(windowDegrees: self.windowDegrees)
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
    /// 向きの変化で作り直された直後にも出直す（編集画面は向きが変わると作り直すため、番号の変化では動かない）
    var onAppear = false
    @State private var appearCount = 0

    struct Value {
        var scaleX = 1.0
        var scaleY = 1.0
        var opacity = 1.0
    }

    /// 消えている間の大きさ
    static let hiddenScale = 0.35
    /// 消えたままでいる時間（秒）。画面の切り替わりと同時に消え、少しおいてから出る
    static let hold = 0.06

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Value(), trigger: token &* 1000 &+ appearCount) { view, value in
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
        .onAppear { startIfJustRotated() }
    }

    /// 作り直された直後に呼ぶ: 向きが変わったばかりなら出直しのアニメーションを始める
    @MainActor
    private func startIfJustRotated() {
        guard onAppear, Date().timeIntervalSince(CanvasOrientation.shared.lastReveal) < 0.4 else { return }
        appearCount &+= 1
    }

    /// マスごとの遅れ: グリッドの中央から離れるほど少し遅らせる（最大 0.12 秒）
    static func delay(slot: Int, layout: GridLayout) -> Double {
        let row = Double(slot / layout.columns), column = Double(slot % layout.columns)
        let dr = row - Double(layout.rows - 1) / 2, dc = column - Double(layout.columns - 1) / 2
        return min(0.12, (dr * dr + dc * dc).squareRoot() * 0.025)
    }
}

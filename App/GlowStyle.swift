import SwiftUI
import CoreMotion

/// UI のデザイン。設定の「デザイン」で切り替える（@AppStorage("uiStyle")）。
/// standard を選んでいる間は、これまでのデザインから何も変えない。グローの描画はすべてこのファイルに置く
enum UIStyle: Int, CaseIterable, Identifiable {
    case standard, glow
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .standard: return "標準"
        case .glow: return "グロー"
        }
    }
}

/// グローの色。設定で選ぶ（色相を 0–360 の度で @AppStorage に保存）
enum GlowPalette {
    static let key = "glowHue"
    static let defaultHue: Double = 222

    /// グラデーション（アプリアイコンの、コーラル → ピンク → パープル → ブルー → シアン）を使うか
    static let gradientKey = "glowGradient"
    /// グラデーションを選んだときの中心の色相（パープル）
    static let gradientCenter: Double = 250
    /// 中心の色相からのずれ（度）。色相のスライダーを動かすと、全体がそろってずれる
    static let gradientOffsets: [Double] = [120, 70, 20, -22, -50]

    /// 中心の色相（度）からずらした色相（0–1）
    static func hue(_ center: Double, _ offset: Double) -> Double {
        let h = (center + offset).truncatingRemainder(dividingBy: 360)
        return (h < 0 ? h + 360 : h) / 360
    }

    /// 設定の見本用の色
    static func gradientColors(_ center: Double) -> [Color] {
        gradientOffsets.map { Color(hue: hue(center, $0), saturation: 0.75, brightness: 1) }
    }

    /// ライトの強さ（1...10 の 10 段階、@AppStorage）。5 が基準
    static let intensityKey = "glowIntensity"
    static let defaultIntensity: Double = 5
    /// 段階を倍率に直す（5 → 1.0、1 → 0.2、10 → 2.0）
    static func factor(_ level: Double) -> Double { min(max(level, 1), 10) / defaultIntensity }
    /// タイルやボタンの色の強さの倍率（5 → 1.0、1 → 0.56、10 → 1.55）。背景の光ほどは大きく変えない
    static func tileScale(_ level: Double) -> Double { 0.45 + 0.55 * factor(level) }

    struct Preset: Identifiable {
        let name: String
        let hue: Double
        var id: String { name }
        var swatch: Color { Color(hue: hue / 360, saturation: 0.85, brightness: 0.9) }
    }

    static let presets: [Preset] = [
        .init(name: "ブルー", hue: 222),
        .init(name: "シアン", hue: 190),
        .init(name: "グリーン", hue: 140),
        .init(name: "パープル", hue: 270),
        .init(name: "ピンク", hue: 320),
        .init(name: "レッド", hue: 355),
        .init(name: "オレンジ", hue: 25),
    ]
}

// MARK: 傾き

/// 端末の傾きを読んで、グローの光の向きに使う。
/// グローを選んでいて、設定がオンで、アプリが前面のときだけ動かす（ContentView が開始・停止する）
@MainActor
final class GlowMotion: ObservableObject {
    static let shared = GlowMotion()

    /// 持ち始めの姿勢からの傾き（長さ 1 までのベクトル）。x: 左右、y: 前後。止めている間は .zero。
    /// 光や反射など描き直しの重いものが使う。少しなめらかにし、120 回/秒まで
    @Published private(set) var tilt: CGSize = .zero
    /// 設定の「動きの強さ」
    var strength: Double = 1

    /// 実機で向きが不自然なときは、ここの符号を変える
    static let signX: Double = 1
    static let signY: Double = 1

    private let manager = CMMotionManager()
    /// 基準の角度（開始時の持ち方。ゆっくり今の持ち方へ寄せる）
    private var neutral: (x: Double, y: Double)?
    private var lastPitch: Double = 0
    private var smoothed: (x: Double, y: Double) = (0, 0)
    private var fast: (x: Double, y: Double) = (0, 0)

    private init() {}

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive,
              !UIAccessibility.isReduceMotionEnabled else { return }
        neutral = nil
        smoothed = (0, 0)
        fast = (0, 0)
        // ProMotion（120Hz）の画面に合わせて 120 回/秒で読む
        manager.deviceMotionUpdateInterval = 1.0 / 120
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            let gx = g.x, gy = g.y, gz = g.z
            // メインキューで呼ばれるので、そのまま処理する（Task を挟むと 1 フレーム遅れることがある）
            MainActor.assumeIsolated { self?.update(gx: gx, gy: gy, gz: gz) }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        neutral = nil
        if tilt != .zero { tilt = .zero }
        GlowParallaxMotion.shared.set(.zero)
    }

    /// 角度の差（-π...π に折り返す）
    private static func delta(_ a: Double, _ b: Double) -> Double { remainder(a - b, 2 * .pi) }

    private func update(gx: Double, gy: Double, gz: Double) {
        guard manager.isDeviceMotionActive else { return }
        // 重力の向きを角度に直す。左右は asin、前後は y-z 面での角度にして、
        // 立てて持っても寝かせて持っても同じ感度にする（斜めに傾けたときに縦の動きが弱くならないように）
        let roll = asin(max(-1, min(1, gx)))
        let yz = sqrt(gy * gy + gz * gz)
        let pitch = yz > 0.2 ? atan2(gy, -gz) : lastPitch   // 横向きに近いときは前後の角度が不安定なので保つ
        lastPitch = pitch

        var base = neutral ?? (roll, pitch)
        // 寝転んだり置いたりして持ち方が変わっても、10 秒ほどで新しい姿勢が基準になる。
        // 傾けたまま持っていると光がゆっくり戻る速さもこの係数で決まる
        base = (base.x + Self.delta(roll, base.x) * 0.0015, base.y + Self.delta(pitch, base.y) * 0.0015)
        neutral = base

        var rawX = Self.delta(roll, base.x) * 2.2 * strength * Self.signX
        var rawY = Self.delta(pitch, base.y) * 2.2 * strength * Self.signY
        // 斜めでも大きくなりすぎないよう、ベクトルの長さで 1 までに抑える
        let length = sqrt(rawX * rawX + rawY * rawY)
        if length > 1 { rawX /= length; rawY /= length }

        // アイコンの視差: ほぼ遅れなく追従させる
        fast = (fast.x * 0.4 + rawX * 0.6, fast.y * 0.4 + rawY * 0.6)
        GlowParallaxMotion.shared.set(CGSize(width: fast.x, height: fast.y))

        // 光・反射・影: 120 回/秒で毎回更新する。なめらかさは残しつつ遅れは約 0.02 秒
        smoothed = (smoothed.x * 0.65 + rawX * 0.35, smoothed.y * 0.65 + rawY * 0.35)
        let next = CGSize(width: smoothed.x, height: smoothed.y)
        if abs(next.width - tilt.width) > 0.003 || abs(next.height - tilt.height) > 0.003 {
            tilt = next
        }
    }
}

/// アイコンの視差だけに使う、速く追従する傾き。光の描き直しと分けて、アイコンのずれだけを毎回更新する
@MainActor
final class GlowParallaxMotion: ObservableObject {
    static let shared = GlowParallaxMotion()
    @Published private(set) var tilt: CGSize = .zero
    private init() {}

    func set(_ value: CGSize) {
        if abs(value.width - tilt.width) > 0.002 || abs(value.height - tilt.height) > 0.002 || value == .zero {
            if value != tilt { tilt = value }
        }
    }
}

/// 傾きから決まる光の向き。傾き 0 のときは真下から（これまでのグローと同じ見た目）
struct GlowLight {
    /// 傾けた方向へ光が動くか、逆へ動くか。実機で不自然ならここの符号を変える
    static let direction: CGFloat = -1

    let dx: CGFloat
    let dy: CGFloat
    /// 傾きの大きさ（0...1）
    let amount: CGFloat
    /// 前後の傾き（-1...1、向きの符号込み）。光の位置を上下にずらすのに使う
    let ty: CGFloat
    /// 左右の傾き（-1...1、向きの符号込み）
    let tx: CGFloat

    init(_ tilt: CGSize) {
        tx = Self.direction * tilt.width
        ty = Self.direction * tilt.height
        let x = Self.direction * tilt.width * 1.1
        let y = 1 + Self.direction * tilt.height * 0.6
        let length = max(sqrt(x * x + y * y), 0.001)
        dx = x / length
        dy = y / length
        amount = min(1, sqrt(tilt.width * tilt.width + tilt.height * tilt.height))
    }

    /// 光が当たる側の端（傾き 0 で .bottom）
    var lit: UnitPoint { UnitPoint(x: 0.5 + dx * 0.5, y: 0.5 + dy * 0.5) }
    /// 光の反対側の端（傾き 0 で .top）
    var far: UnitPoint { UnitPoint(x: 0.5 - dx * 0.5, y: 0.5 - dy * 0.5) }
    /// 光の向きの角度（SwiftUI の角度。傾き 0 で 90°= 真下）
    var angle: Angle { .radians(Double(atan2(dy, dx))) }
}

/// 視差: 傾けるとアイコンが背景とは逆へ少しずれ、背景より手前に浮いて見える。
/// 見た目だけずらす（当たり判定の位置は変えない）。傾きが 0 のとき、グロー以外では動かない
struct GlowParallax: ViewModifier {
    var enabled: Bool
    @ObservedObject private var motion = GlowParallaxMotion.shared
    /// ずれる最大の幅 (pt)。設定の「アイコンの浮き上がり」
    @AppStorage("glowParallax") private var amount = 8.0
    /// 傾けた方向と逆へずらす。実機で不自然ならここの符号を変える
    static let direction: CGFloat = -1

    func body(content: Content) -> some View {
        let k = enabled ? Self.direction * CGFloat(amount) : 0
        content.offset(x: motion.tilt.width * k, y: motion.tilt.height * k)
    }
}

// MARK: 色

/// アイコン画像の代表的な色相（0–1）。灰色に近い画像は nil。毎フレーム呼ばれるのでキャッシュする
@MainActor private var imageHueCache: [String: Double] = [:]

@MainActor
func glowImageHue(_ file: String) -> Double? {
    if let hit = imageHueCache[file] { return hit < 0 ? nil : hit }
    var result = -1.0
    if let cg = loadIconImage(file)?.cgImage {
        // 画像を 1×1 に縮めて平均の色を取る
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let color = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        if color.getHue(&h, saturation: &sat, brightness: &b, alpha: &a), sat > 0.18, b > 0.15 {
            result = Double(h)
        }
    }
    imageHueCache[file] = result
    return result < 0 ? nil : result
}

// MARK: 背景

/// ごく暗いグレーの地に、下から色の付いた光が差し込む背景。
/// 傾けると光が左右に寄る。ライトの強さを上げるほど、色の光が濃く・広くなる
struct GlowBackground: View {
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity
    @AppStorage(GlowPalette.gradientKey) private var gradient = false
    @ObservedObject private var motion = GlowMotion.shared
    @Environment(\.colorScheme) private var scheme

    /// 真っ黒（RGB 0）ではなく、ほんの少しだけグレーに寄せた地の色
    private static let base = Color(white: 0.04)
    /// ライトの地の色
    private static let lightBase = Color(white: 0.95)

    var body: some View {
        let light = GlowLight(motion.tilt)
        let f = GlowPalette.factor(intensity)
        if scheme == .light {
            lightBody(light, f)
        } else {
            darkBody(light, f)
        }
    }

    /// 下から照らす光。グラデのときは、光の色が左から右へ 3 色に移り変わる
    /// （ピンク → パープル → ブルー。アプリアイコンの配色。色相のスライダーで全体がずれる）
    @ViewBuilder
    private func bottomLight(_ color: Color, opacity: Double, center: UnitPoint, radius: CGFloat,
                             saturation: Double, brightness: Double, shiftX: CGFloat) -> some View {
        if gradient {
            let colors = [70.0, 20.0, -45.0].map {
                Color(hue: GlowPalette.hue(themeHue, $0), saturation: saturation, brightness: brightness)
            }
            LinearGradient(colors: colors,
                           startPoint: UnitPoint(x: -0.1 + shiftX, y: 0.5),
                           endPoint: UnitPoint(x: 1.1 + shiftX, y: 0.5))
                .mask(RadialGradient(colors: [.white.opacity(opacity), .clear],
                                     center: center, startRadius: 0, endRadius: radius))
        } else {
            RadialGradient(colors: [color.opacity(opacity), .clear],
                           center: center, startRadius: 0, endRadius: radius)
        }
    }

    /// ライト: 明るい地に、下から淡い色の光
    private func lightBody(_ light: GlowLight, _ f: Double) -> some View {
        let color = Color(hue: gradient ? GlowPalette.hue(themeHue, 20) : themeHue / 360, saturation: 0.55, brightness: 1)
        let shiftX = light.dx * 0.5
        let shiftY = light.ty * 0.12
        return ZStack {
            Self.lightBase
            if f > 1 {
                color.opacity(0.06 * (f - 1))
            }
            bottomLight(color, opacity: min(0.45 * pow(f, 0.8), 0.85),
                        center: UnitPoint(x: 0.5 + shiftX, y: 1.08 + shiftY),
                        radius: 620 * (0.55 + 0.45 * f), saturation: 0.55, brightness: 1, shiftX: shiftX)
        }
        .ignoresSafeArea()
    }

    private func darkBody(_ light: GlowLight, _ f: Double) -> some View {
        let color = Color(hue: gradient ? GlowPalette.hue(themeHue, 20) : themeHue / 360, saturation: 0.85, brightness: 0.9)
        // 傾きに合わせて光の中心を左右に寄せる（上下は少しだけ）
        let shiftX = light.dx * 0.5
        // 前後に傾けたときも光が上下に動くように（斜めに傾けると斜めに動く）
        let shiftY = light.ty * 0.12
        return ZStack {
            Self.base
            // 強いときは色の光が画面全体にうっすら回る
            if f > 1 {
                color.opacity(0.09 * (f - 1))
            }
            bottomLight(color, opacity: min(0.55 * pow(f, 0.8), 0.92),
                        center: UnitPoint(x: 0.5 + shiftX, y: 1.08 + shiftY),
                        radius: 620 * (0.55 + 0.45 * f), saturation: 0.85, brightness: 0.9, shiftX: shiftX)
            RadialGradient(colors: [Color.white.opacity(min(0.22 * pow(f, 0.7), 0.5)), .clear],
                           center: UnitPoint(x: 0.5 + shiftX * 1.15, y: 1.02 + shiftY),
                           startRadius: 0, endRadius: 260 * (0.7 + 0.3 * f))
        }
        .ignoresSafeArea()
    }
}

// MARK: タイル

/// タイルの縁。光が当たる側ほど明るい細い縁と、その手前の角に出る色の屈折。
/// 屈折の色は下のタイルの色相に合わせ、加算で重ねる（光として足す）。ぼかしは使わない
struct GlowEdges<S: InsettableShape>: View {
    let shape: S
    let size: CGFloat
    /// 下にあるタイルの色相（0–1）。nil なら設定のグローの色
    var hue: Double? = nil
    var dim = false
    /// 屈折の色を光として足す（加算）か。暗いガラスの上では加算、明るい面（画像やオンのタイル）では
    /// 加算だと色が見えなくなるので通常の重ね方にする
    var additive = true
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @ObservedObject private var motion = GlowMotion.shared
    @Environment(\.colorScheme) private var scheme

    /// 下の色を中心にした、隣り合う色のスペクトル
    private func prism(_ light: GlowLight) -> AngularGradient {
        let base = hue ?? themeHue / 360
        func tone(_ offset: Double, _ saturation: Double, _ brightness: Double) -> Color {
            let h = (base + offset).truncatingRemainder(dividingBy: 1)
            return Color(hue: h < 0 ? h + 1 : h, saturation: saturation, brightness: brightness)
        }
        let end = light.angle
        return AngularGradient(stops: [
            .init(color: .clear, location: 0.00),
            .init(color: tone(-0.10, 0.9, 1), location: 0.18),
            .init(color: tone(-0.04, 0.65, 1), location: 0.32),
            .init(color: tone(0.05, 0.45, 1), location: 0.50),
            .init(color: tone(0.13, 0.8, 1), location: 0.66),
            .init(color: tone(0.22, 0.85, 0.95), location: 0.80),
            .init(color: .clear, location: 1.00),
        ], center: .center, startAngle: end - .degrees(90), endAngle: end)
    }

    var body: some View {
        let light = GlowLight(motion.tilt)
        if scheme == .light {
            // ライト: 明るい地では加算も白い縁も見えないので、通常の重ね方と少し濃い縁にする
            ZStack {
                shape.strokeBorder(prism(light), lineWidth: max(1.5, size * 0.035))
                    .opacity(dim ? 0.2 : 0.55)
                shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(0.06), Color.black.opacity(dim ? 0.1 : 0.18)],
                                                  startPoint: light.far, endPoint: light.lit),
                                   lineWidth: max(1, size * 0.012))
                shape.inset(by: max(1, size * 0.012))
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2)],
                                                 startPoint: light.far, endPoint: light.lit),
                                  lineWidth: max(0.75, size * 0.01))
            }
            .allowsHitTesting(false)
        } else {
            ZStack {
                shape.strokeBorder(prism(light), lineWidth: max(1.5, size * 0.035))
                    .opacity(dim ? 0.25 : 0.75)
                    .blendMode(additive ? .plusLighter : .normal)
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(dim ? 0.35 : 0.8)],
                                                  startPoint: light.far, endPoint: light.lit),
                                   lineWidth: max(1, size * 0.012))
            }
            .allowsHitTesting(false)
        }
    }
}

/// タイルの面に乗る光と影。光の側に明るい反射、反対側に映り込み、傾けたときだけ反対側に影が出る
struct GlowSurfaceLight<S: Shape>: View {
    let shape: S
    let size: CGFloat
    var hue: Double? = nil
    /// 光の側の反射の強さ
    var glow: Double = 0.42
    /// ライトで白い映り込みを強く乗せるか（白っぽいすりガラスのタイルだけ。画像・オンのタイル・ボタンでは白くかすむので弱くする）
    var paleSurface = false
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @ObservedObject private var motion = GlowMotion.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = GlowLight(motion.tilt)
        let base = hue ?? themeHue / 360
        if scheme == .light {
            // ライト: 光の側に淡い色、反対側に白い映り込み、傾けたときだけ薄い影
            ZStack {
                shape.fill(RadialGradient(
                    colors: [Color(hue: base, saturation: 0.45, brightness: 1).opacity(glow * 0.8), .clear],
                    center: light.lit, startRadius: 0, endRadius: size * 0.75))
                shape.fill(LinearGradient(colors: [.white.opacity(paleSurface ? 0.55 : 0.1), .clear],
                                          startPoint: light.far, endPoint: .center))
                shape.fill(LinearGradient(colors: [.black.opacity(0.12 * light.amount), .clear],
                                          startPoint: light.far, endPoint: .center))
            }
            .allowsHitTesting(false)
        } else {
            darkLayers(light, base)
        }
    }

    private func darkLayers(_ light: GlowLight, _ base: Double) -> some View {
        ZStack {
            shape.fill(RadialGradient(
                colors: [Color(hue: base, saturation: 0.3, brightness: 1).opacity(glow), .clear],
                center: light.lit, startRadius: 0, endRadius: size * 0.75))
            shape.fill(LinearGradient(colors: [.white.opacity(0.1), .clear],
                                      startPoint: light.far, endPoint: .center))
            shape.fill(LinearGradient(colors: [.black.opacity(0.35 * light.amount), .clear],
                                      startPoint: light.far, endPoint: .center))
        }
        .allowsHitTesting(false)
    }
}

/// アイコンの表面に映り込む丸い光（照明の映り込み）。傾けると、光と反対の向きへ表面をすべるように動く。
/// 傾けていないときは左上寄りに薄く乗る。端に境界が出ないよう、なだらかに透明になる
struct GlowSpecular<S: Shape>: View {
    let shape: S
    let size: CGFloat
    @ObservedObject private var motion = GlowMotion.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = motion.tilt
        let x = min(max(0.3 - t.width * 0.35, 0.05), 0.95)
        let y = min(max(0.26 - t.height * 0.35, 0.05), 0.95)
        let peak = scheme == .light ? 0.4 : 0.16
        // ぼかしたように見えるよう、中心が平らで裾の長い減り方（ガウス分布に近い形）にして、範囲を広げる
        let falloff: [(Double, Double)] = [(0, 1), (0.15, 0.94), (0.3, 0.8), (0.45, 0.6),
                                           (0.6, 0.4), (0.75, 0.22), (0.9, 0.08), (1, 0)]
        shape
            .fill(RadialGradient(stops: falloff.map { .init(color: .white.opacity(peak * $0.1), location: $0.0) },
                                 center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: size * 0.8))
            .blendMode(scheme == .light ? .normal : .plusLighter)
            .allowsHitTesting(false)
    }
}

/// すりガラスのタイル。光が当たる側が明るい。オンのときは全体が光る（ネガポジ反転）
struct GlowTileBackground: View {
    let size: CGFloat
    /// 色相（0–1）。nil なら設定のグローの色
    var hue: Double? = nil
    var isOn = false
    var dim = false
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.gradientKey) private var gradient = false
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity
    @Environment(\.colorScheme) private var scheme

    /// ライトの強さに応じて、光が当たる側の色の濃さ・明るさを変える（強さ 5 でこれまでと同じ）
    private var k: Double { GlowPalette.tileScale(intensity) }
    private func lit(_ value: Double, max upper: Double) -> Double { min(value * k, upper) }
    private func litSat(_ value: Double) -> Double { min(value * (0.75 + 0.25 * k), 1) }

    /// グラデーションのときのタイルの色（上: ピンク寄り → 下: ブルー寄り）
    private func gradientColors(isLight: Bool) -> [Color] {
        let top = GlowPalette.hue(themeHue, 70), mid = GlowPalette.hue(themeHue, 20), bottom = GlowPalette.hue(themeHue, -30)
        if isLight {
            return isOn
                ? [Color(hue: top, saturation: 0.8, brightness: 0.5), Color(hue: bottom, saturation: 0.8, brightness: 0.72)]
                : [Color(hue: top, saturation: dim ? 0.03 : 0.07, brightness: 0.99),
                   Color(hue: bottom, saturation: lit(dim ? 0.1 : 0.28, max: 0.6), brightness: dim ? 0.9 : 0.95)]
        }
        return isOn
            ? [Color(hue: top, saturation: 0.25, brightness: 0.95), Color(hue: bottom, saturation: 0.45, brightness: 1)]
            : [Color(hue: top, saturation: 0.9, brightness: 0.08),
               Color(hue: mid, saturation: litSat(0.85), brightness: lit(dim ? 0.12 : 0.24, max: 0.45)),
               Color(hue: bottom, saturation: litSat(0.85), brightness: lit(dim ? 0.2 : 0.45, max: 0.78))]
    }

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        let shape = iconShape(size)
        let isLight = scheme == .light
        // ベース色を指定していないタイルだけ、グラデーションの配色にする
        let useGradient = gradient && self.hue == nil
        // ライトは白っぽいすりガラスで、オンのときは濃い色に反転する。ダークはこれまでどおり
        let colors: [Color] = isLight
            ? (isOn
               ? [Color(hue: hue, saturation: 0.85, brightness: 0.45), Color(hue: hue, saturation: 0.8, brightness: 0.72)]
               : [Color(hue: hue, saturation: dim ? 0.03 : 0.06, brightness: 0.99),
                  Color(hue: hue, saturation: lit(dim ? 0.1 : 0.28, max: 0.6), brightness: dim ? 0.9 : 0.95)])
            : (isOn
               ? [Color(hue: hue, saturation: 0.25, brightness: 0.92), Color(hue: hue, saturation: 0.45, brightness: 1)]
               : [Color(hue: hue, saturation: 0.9, brightness: 0.07),
                  Color(hue: hue, saturation: litSat(0.85), brightness: lit(dim ? 0.2 : 0.42, max: 0.75))])
        ZStack {
            shape.fill(LinearGradient(colors: useGradient ? gradientColors(isLight: isLight) : colors,
                                      startPoint: .top, endPoint: .bottom))
            GlowSurfaceLight(shape: shape, size: size, hue: hue,
                             glow: isLight && isOn ? 0.15 : (isOn ? 0.6 : lit(dim ? 0.12 : 0.42, max: 0.8)),
                             paleSurface: !isOn)
            GlowEdges(shape: shape, size: size, hue: hue, dim: dim, additive: !isOn)
        }
        .frame(width: size, height: size)
    }
}

/// タイルの外にこぼれる光（グローのライトでは影）。光は光の側へ、影は反対側へ出る。
/// ぼかしフィルターは使わず、端で透明になるなだらかな放射グラデーションで境界を見せない
struct GlowUnderLight: View {
    let size: CGFloat
    var hue: Double? = nil
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity
    @ObservedObject private var motion = GlowMotion.shared
    @Environment(\.colorScheme) private var scheme

    /// 傾きで動く幅（タイルの大きさに対する割合）。大きく動きすぎないよう小さくしている
    private static let travel: CGFloat = 0.12

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        let light = GlowLight(motion.tilt)
        let f = GlowPalette.factor(intensity)
        let isLight = scheme == .light
        // ライトでは光の代わりに影にする（同じ形・同じぼけ方。色は地の色相を少し含んだ濃い色）
        let color = isLight
            ? Color(hue: hue, saturation: 0.5, brightness: 0.18)
            : Color(hue: hue, saturation: 0.7, brightness: 1)
        let peak = isLight
            ? min(0.16 * (0.6 + 0.4 * f), 0.3)
            : min(0.4 * (0.4 + 0.6 * f), 0.75)
        // 光は光の側へ寄り、影は反対側へ落ちる
        let side: CGFloat = isLight ? -1 : 1
        // 円の端でちょうど透明になる、なだらかな減り方のグラデーションを描き、縦につぶして楕円にする。
        // 端に境界線が出ない（ぼかしフィルターを使わずに、ぼかしたような見た目にする）
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: color.opacity(peak), location: 0),
                .init(color: color.opacity(peak * 0.62), location: 0.25),
                .init(color: color.opacity(peak * 0.3), location: 0.5),
                .init(color: color.opacity(peak * 0.1), location: 0.75),
                .init(color: color.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: size * 0.85))
            .frame(width: size * 1.7, height: size * 1.7)
            .scaleEffect(x: 1, y: 0.45)
            // 傾き 0 ではタイルの真下。そこから少しだけ光の側（影なら反対側）へ寄る
            .offset(x: side * light.dx * size * Self.travel,
                    y: size * 0.45 + side * light.ty * size * Self.travel)
            .allowsHitTesting(false)
    }
}

/// グローのデザインでのアイコン。
/// - シンボル: すりガラスのタイルに銀色の記号。オンでは明るいタイルに濃い記号（ネガポジ反転）
/// - 画像: 色はそのまま、縁と光を重ねる。縁の色は画像の代表色に合わせる。オンでは色を反転
/// - ベース色を指定したアイテムは、その色相のガラスになる
struct GlowIcon: View {
    let item: LaunchItem
    let size: CGFloat
    var isOn = false

    var body: some View {
        if let file = item.iconFile, let img = loadIconImage(file) {
            let hue = glowImageHue(file)
            let picture = Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(iconShape(size))
            Group {
                if isOn { picture.colorInvert() } else { picture }
            }
            .overlay { GlowSurfaceLight(shape: iconShape(size), size: size, hue: hue, glow: 0) }
            .overlay { GlowSpecular(shape: iconShape(size), size: size) }
            .overlay { GlowEdges(shape: iconShape(size), size: size, hue: hue, additive: false) }
            // 外にこぼれる光は画像の色ではなく、設定のグローの色のまま
            .background { GlowUnderLight(size: size) }
        } else {
            // ベース色を指定したアイテムはその色相、それ以外は設定のグローの色（nil）
            let hue = item.baseHSB.map { $0.h / 360 }
            GlowTileBackground(size: size, hue: hue, isOn: isOn)
                .overlay { GlowSymbol(name: item.symbol, size: size, hue: hue, isOn: isOn) }
                .overlay { GlowSpecular(shape: iconShape(size), size: size) }
                .background { GlowUnderLight(size: size, hue: hue) }
        }
    }
}

/// 銀色の記号（オンのときは濃い色）
struct GlowSymbol: View {
    let name: String
    let size: CGFloat
    var hue: Double? = nil
    var isOn = false
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        let image = Image(systemName: name).font(.system(size: size * 0.42, weight: .regular))
        if scheme == .light {
            // ライト: 普段は濃い色の記号、オンでは濃いタイルに白い記号
            if isOn {
                image.foregroundStyle(Color.white)
            } else {
                image.foregroundStyle(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.4),
                                                              Color(hue: hue, saturation: 0.6, brightness: 0.22)],
                                                     startPoint: .top, endPoint: .bottom))
            }
        } else if isOn {
            image.foregroundStyle(Color(hue: hue, saturation: 0.9, brightness: 0.22))
        } else {
            image.foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.68)],
                                                 startPoint: .top, endPoint: .bottom))
        }
    }
}

// MARK: 丸いボタン

/// グローの丸いボタンの下地
struct GlowCircle: View {
    var tint: Color? = nil
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.gradientKey) private var gradient = false
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // ライトの強さに応じて色の濃さ・明るさを変える（強さ 5 でこれまでと同じ）
        let k = GlowPalette.tileScale(intensity)
        let topHue = gradient ? GlowPalette.hue(themeHue, 70) : themeHue / 360
        let bottomHue = gradient ? GlowPalette.hue(themeHue, -30) : themeHue / 360
        let colors: [Color] = scheme == .light
            ? [Color(hue: topHue, saturation: 0.05, brightness: 0.99),
               Color(hue: bottomHue, saturation: min(0.25 * k, 0.55), brightness: 0.94)]
            : [Color(hue: topHue, saturation: 0.9, brightness: 0.08),
               Color(hue: bottomHue, saturation: min(0.85 * (0.75 + 0.25 * k), 1), brightness: min(0.36 * k, 0.7))]
        ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            if let tint { Circle().fill(tint.opacity(0.55)) }
            GlowSurfaceLight(shape: Circle(), size: 40, glow: min(0.35 * k, 0.7))
            GlowEdges(shape: Circle(), size: 44)
        }
    }
}

/// 丸いボタンの下地を、選んだデザインで描き分ける（標準ではこれまでの Liquid Glass のまま）
struct StyledCircleGlass: ViewModifier {
    @AppStorage("uiStyle") private var uiStyle = UIStyle.standard.rawValue
    var tint: Color?
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if uiStyle == UIStyle.glow.rawValue {
            content.background { GlowCircle(tint: tint) }
        } else {
            content.glass(in: Circle(), tint: tint, interactive: interactive)
        }
    }
}

extension View {
    func styledCircleGlass(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(StyledCircleGlass(tint: tint, interactive: interactive))
    }
}

/// 設定画面: グローの色を選ぶ
struct GlowColorPicker: View {
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.gradientKey) private var gradient = false

    private func swatch<S: ShapeStyle>(_ name: String, fill: S, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Color.black)
                    Circle().fill(fill)
                    Circle().strokeBorder(Color.white.opacity(selected ? 0.95 : 0.25), lineWidth: selected ? 2 : 1)
                }
                .frame(width: 40, height: 40)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // アプリアイコンの配色。色相を変えると全体がそろってずれる
                    swatch("グラデ",
                           fill: LinearGradient(colors: GlowPalette.gradientColors(gradient ? themeHue : GlowPalette.gradientCenter),
                                                startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.85),
                           selected: gradient) {
                        if !gradient { themeHue = GlowPalette.gradientCenter }
                        gradient = true
                    }
                    ForEach(GlowPalette.presets) { preset in
                        swatch(preset.name,
                               fill: RadialGradient(colors: [preset.swatch, .clear], center: .bottom,
                                                    startRadius: 0, endRadius: 26),
                               selected: !gradient && themeHue == preset.hue) {
                            gradient = false
                            themeHue = preset.hue
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text(gradient ? "色相（全体）" : "色相")
                Slider(value: $themeHue, in: 0...360, step: 1)
                if gradient {
                    Circle()
                        .fill(LinearGradient(colors: GlowPalette.gradientColors(themeHue),
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(Color(hue: themeHue / 360, saturation: 0.85, brightness: 0.9))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
}

/// 設定画面: 傾きで光を動かすかどうか
/// 設定画面: グローのダーク / ライト
struct GlowBrightnessPicker: View {
    @AppStorage("glowLight") private var glowLight = false

    var body: some View {
        Picker("グローの明るさ", selection: $glowLight) {
            Text("ダーク").tag(false)
            Text("ライト").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

struct GlowMotionSettings: View {
    @AppStorage("glowMotion") private var glowMotion = true
    @AppStorage("glowMotionStrength") private var strength = 1.0
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity
    @AppStorage("glowParallax") private var parallax = 8.0

    var body: some View {
        VStack(alignment: .leading) {
            Text("ライトの強さ: \(Int(intensity)) / 10")
            Slider(value: $intensity, in: 1...10, step: 1)
        }
        Toggle("傾きで光を動かす", isOn: $glowMotion)
        if glowMotion {
            VStack(alignment: .leading) {
                Text("アイコンの浮き上がり（視差）: \(Int(parallax)) pt")
                Slider(value: $parallax, in: 0...20, step: 1)
            }
        }
        if glowMotion {
            VStack(alignment: .leading) {
                Text("動きの強さ: \(Int((strength * 100).rounded()))%")
                Slider(value: $strength, in: 0.3...2, step: 0.1)
            }
        }
    }
}

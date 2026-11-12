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

    /// ライトの強さ（1...10 の 10 段階、@AppStorage）。5 が基準
    static let intensityKey = "glowIntensity"
    static let defaultIntensity: Double = 5
    /// 段階を倍率に直す（5 → 1.0、1 → 0.2、10 → 2.0）
    static func factor(_ level: Double) -> Double { min(max(level, 1), 10) / defaultIntensity }

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
    /// 光や反射など描き直しの重いものが使う。少しなめらかにし、約 30 回/秒まで
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
    private var frame = 0

    private init() {}

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive,
              !UIAccessibility.isReduceMotionEnabled else { return }
        neutral = nil
        smoothed = (0, 0)
        fast = (0, 0)
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let g = motion?.gravity else { return }
            let gx = g.x, gy = g.y, gz = g.z
            Task { @MainActor in self?.update(gx: gx, gy: gy, gz: gz) }
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

        // アイコンの視差: ほぼ遅れなく追従させる（軽い処理なので毎回）
        fast = (fast.x * 0.35 + rawX * 0.65, fast.y * 0.35 + rawY * 0.65)
        GlowParallaxMotion.shared.set(CGSize(width: fast.x, height: fast.y))

        // 光や反射: 少しなめらかにして、描き直しは 2 回に 1 回
        smoothed = (smoothed.x * 0.6 + rawX * 0.4, smoothed.y * 0.6 + rawY * 0.4)
        frame += 1
        guard frame % 2 == 0 else { return }
        let next = CGSize(width: smoothed.x, height: smoothed.y)
        if abs(next.width - tilt.width) > 0.006 || abs(next.height - tilt.height) > 0.006 {
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
    @ObservedObject private var motion = GlowMotion.shared

    /// 真っ黒（RGB 0）ではなく、ほんの少しだけグレーに寄せた地の色
    private static let base = Color(white: 0.04)

    var body: some View {
        let light = GlowLight(motion.tilt)
        let f = GlowPalette.factor(intensity)
        let color = Color(hue: themeHue / 360, saturation: 0.85, brightness: 0.9)
        // 傾きに合わせて光の中心を左右に寄せる（上下は少しだけ）
        let shiftX = light.dx * 0.5
        // 前後に傾けたときも光が上下に動くように（斜めに傾けると斜めに動く）
        let shiftY = light.ty * 0.12
        ZStack {
            Self.base
            // 強いときは色の光が画面全体にうっすら回る
            if f > 1 {
                color.opacity(0.09 * (f - 1))
            }
            RadialGradient(colors: [color.opacity(min(0.55 * pow(f, 0.8), 0.92)), .clear],
                           center: UnitPoint(x: 0.5 + shiftX, y: 1.08 + shiftY),
                           startRadius: 0, endRadius: 620 * (0.55 + 0.45 * f))
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

/// タイルの面に乗る光と影。光の側に明るい反射、反対側に映り込み、傾けたときだけ反対側に影が出る
struct GlowSurfaceLight<S: Shape>: View {
    let shape: S
    let size: CGFloat
    var hue: Double? = nil
    /// 光の側の反射の強さ
    var glow: Double = 0.42
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @ObservedObject private var motion = GlowMotion.shared

    var body: some View {
        let light = GlowLight(motion.tilt)
        let base = hue ?? themeHue / 360
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

/// すりガラスのタイル。光が当たる側が明るい。オンのときは全体が光る（ネガポジ反転）
struct GlowTileBackground: View {
    let size: CGFloat
    /// 色相（0–1）。nil なら設定のグローの色
    var hue: Double? = nil
    var isOn = false
    var dim = false
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        let shape = iconShape(size)
        let colors: [Color] = isOn
            ? [Color(hue: hue, saturation: 0.25, brightness: 0.92), Color(hue: hue, saturation: 0.45, brightness: 1)]
            : [Color(hue: hue, saturation: 0.9, brightness: 0.07),
               Color(hue: hue, saturation: 0.85, brightness: dim ? 0.2 : 0.42)]
        ZStack {
            shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            GlowSurfaceLight(shape: shape, size: size, hue: hue, glow: isOn ? 0.6 : (dim ? 0.12 : 0.42))
            GlowEdges(shape: shape, size: size, hue: hue, dim: dim, additive: !isOn)
        }
        .frame(width: size, height: size)
    }
}

/// タイルの外にこぼれる光。光の側へ出る。
/// ぼかしフィルターは使わず、端で透明になるなだらかな放射グラデーションで境界を見せない
struct GlowUnderLight: View {
    let size: CGFloat
    var hue: Double? = nil
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue
    @AppStorage(GlowPalette.intensityKey) private var intensity = GlowPalette.defaultIntensity
    @ObservedObject private var motion = GlowMotion.shared

    /// 傾きで動く幅（タイルの大きさに対する割合）。大きく動きすぎないよう小さくしている
    private static let travel: CGFloat = 0.12

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        let light = GlowLight(motion.tilt)
        let f = GlowPalette.factor(intensity)
        let color = Color(hue: hue, saturation: 0.7, brightness: 1)
        let peak = min(0.4 * (0.4 + 0.6 * f), 0.75)
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
            // 傾き 0 ではタイルの真下。そこから少しだけ光の側へ寄る
            .offset(x: light.dx * size * Self.travel,
                    y: size * 0.45 + light.ty * size * Self.travel)
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
            .overlay { GlowEdges(shape: iconShape(size), size: size, hue: hue, additive: false) }
            // 外にこぼれる光は画像の色ではなく、設定のグローの色のまま
            .background { GlowUnderLight(size: size) }
        } else {
            // ベース色を指定したアイテムはその色相、それ以外は設定のグローの色（nil）
            let hue = item.baseHSB.map { $0.h / 360 }
            GlowTileBackground(size: size, hue: hue, isOn: isOn)
                .overlay { GlowSymbol(name: item.symbol, size: size, hue: hue, isOn: isOn) }
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

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        let image = Image(systemName: name).font(.system(size: size * 0.42, weight: .regular))
        if isOn {
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

    var body: some View {
        let glowHue = themeHue / 360
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hue: glowHue, saturation: 0.9, brightness: 0.08),
                                                  Color(hue: glowHue, saturation: 0.85, brightness: 0.36)],
                                         startPoint: .top, endPoint: .bottom))
            if let tint { Circle().fill(tint.opacity(0.55)) }
            GlowSurfaceLight(shape: Circle(), size: 40, glow: 0.35)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(GlowPalette.presets) { preset in
                        let selected = themeHue == preset.hue
                        Button {
                            themeHue = preset.hue
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle().fill(Color.black)
                                    Circle().fill(RadialGradient(colors: [preset.swatch, .clear], center: .bottom,
                                                                 startRadius: 0, endRadius: 26))
                                    Circle().strokeBorder(Color.white.opacity(selected ? 0.95 : 0.25),
                                                          lineWidth: selected ? 2 : 1)
                                }
                                .frame(width: 40, height: 40)
                                Text(preset.name)
                                    .font(.caption2)
                                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("色相")
                Slider(value: $themeHue, in: 0...360, step: 1)
                Circle()
                    .fill(Color(hue: themeHue / 360, saturation: 0.85, brightness: 0.9))
                    .frame(width: 20, height: 20)
            }
        }
    }
}

/// 設定画面: 傾きで光を動かすかどうか
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

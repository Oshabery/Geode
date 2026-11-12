import SwiftUI

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

// MARK: 背景

/// 黒地に、下から青い光が差し込む背景
struct GlowBackground: View {
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(hue: themeHue / 360, saturation: 0.85, brightness: 0.9).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.5, y: 1.08), startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Color.white.opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 1.02), startRadius: 0, endRadius: 260)
        }
        .ignoresSafeArea()
    }
}

// MARK: タイル

/// タイルの縁: 下ほど明るい細い縁 + 右下の角に虹色の屈折。ぼかしは使わない（グループ表示を重くしないため）
struct GlowEdges<S: InsettableShape>: View {
    let shape: S
    let size: CGFloat
    var dim = false

    private var prism: AngularGradient {
        AngularGradient(stops: [
            .init(color: .clear, location: 0.00),
            .init(color: Color(hue: 0.62, saturation: 0.9, brightness: 1), location: 0.18),
            .init(color: Color(hue: 0.52, saturation: 0.8, brightness: 1), location: 0.32),
            .init(color: Color(hue: 0.15, saturation: 0.8, brightness: 1), location: 0.50),
            .init(color: Color(hue: 0.07, saturation: 0.9, brightness: 1), location: 0.66),
            .init(color: Color(hue: 0.98, saturation: 0.8, brightness: 0.9), location: 0.80),
            .init(color: .clear, location: 1.00),
        ], center: .center, startAngle: .degrees(0), endAngle: .degrees(90))
    }

    var body: some View {
        ZStack {
            shape.strokeBorder(prism, lineWidth: max(1.5, size * 0.035))
                .opacity(dim ? 0.25 : 0.75)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(dim ? 0.35 : 0.8)],
                                              startPoint: .top, endPoint: .bottom),
                               lineWidth: max(1, size * 0.012))
        }
        .allowsHitTesting(false)
    }
}

/// すりガラスのタイル。下から光が当たったように下側が明るい。オンのときは全体が光る（ネガポジ反転）
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
            shape.fill(RadialGradient(
                colors: [Color(hue: hue, saturation: 0.3, brightness: 1).opacity(isOn ? 0.6 : (dim ? 0.12 : 0.42)), .clear],
                center: .bottom, startRadius: 0, endRadius: size * 0.75))
            shape.fill(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
            GlowEdges(shape: shape, size: size, dim: dim)
        }
        .frame(width: size, height: size)
    }
}

/// タイルの下にこぼれる光（ぼかしの代わりに放射グラデーション）
struct GlowUnderLight: View {
    let size: CGFloat
    var hue: Double? = nil
    @AppStorage(GlowPalette.key) private var themeHue = GlowPalette.defaultHue

    var body: some View {
        let hue = self.hue ?? themeHue / 360
        Ellipse()
            .fill(RadialGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 1).opacity(0.4), .clear],
                                 center: .center, startRadius: 0, endRadius: size * 0.7))
            .frame(width: size * 1.4, height: size * 0.6)
            .offset(y: size * 0.45)
            .allowsHitTesting(false)
    }
}

/// グローのデザインでのアイコン。
/// - シンボル: すりガラスのタイルに銀色の記号。オンでは明るいタイルに濃い記号（ネガポジ反転）
/// - 画像: 色はそのまま、縁と下の光を重ねる。オンでは色を反転
/// - ベース色を指定したアイテムは、その色相のガラスになる
struct GlowIcon: View {
    let item: LaunchItem
    let size: CGFloat
    var isOn = false

    /// ベース色を指定したアイテムはその色相、それ以外は設定のグローの色（nil）
    private var hue: Double? { item.baseHSB.map { $0.h / 360 } }

    var body: some View {
        Group {
            if let file = item.iconFile, let img = loadIconImage(file) {
                let picture = Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(iconShape(size))
                Group {
                    if isOn { picture.colorInvert() } else { picture }
                }
                .overlay {
                    iconShape(size).fill(LinearGradient(colors: [.white.opacity(0.14), .clear],
                                                        startPoint: .top, endPoint: .center))
                }
                .overlay { GlowEdges(shape: iconShape(size), size: size) }
            } else {
                GlowTileBackground(size: size, hue: hue, isOn: isOn)
                    .overlay { GlowSymbol(name: item.symbol, size: size, hue: hue, isOn: isOn) }
            }
        }
        .background { GlowUnderLight(size: size, hue: hue) }
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
            Circle().fill(RadialGradient(colors: [Color(hue: glowHue, saturation: 0.3, brightness: 1).opacity(0.35), .clear],
                                         center: .bottom, startRadius: 0, endRadius: 30))
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

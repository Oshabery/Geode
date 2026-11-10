import SwiftUI
import UIKit

private let iconCache = NSCache<NSString, UIImage>()

func loadIconImage(_ file: String) -> UIImage? {
    if let hit = iconCache.object(forKey: file as NSString) { return hit }
    guard let img = UIImage(contentsOfFile: SharedStorage.iconURL(file).path) else { return nil }
    iconCache.setObject(img, forKey: file as NSString)
    return img
}

/// アプリアイコンと同じ角丸（スクワークル）形状
func iconShape(_ size: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
}

/// ガラスの縁。光が屈折して虹色に分散したような輪郭 + 内側の影で厚みを出す。
struct GlassRim<S: InsettableShape>: View {
    let shape: S
    var lineWidth: CGFloat = 1.5

    private var gradient: AngularGradient {
        let blue = Color(hue: 0.62, saturation: 0.75, brightness: 1)
        let violet = Color(hue: 0.78, saturation: 0.6, brightness: 1)
        let warm = Color(hue: 0.08, saturation: 0.55, brightness: 1)
        let dim = Color.white.opacity(0.06)
        return AngularGradient(stops: [
            .init(color: .white.opacity(0.95), location: 0.00),
            .init(color: blue.opacity(0.9), location: 0.07),
            .init(color: violet.opacity(0.75), location: 0.13),
            .init(color: dim, location: 0.24),
            .init(color: dim, location: 0.40),
            .init(color: warm.opacity(0.85), location: 0.47),
            .init(color: .white.opacity(0.9), location: 0.52),
            .init(color: blue.opacity(0.9), location: 0.60),
            .init(color: dim, location: 0.72),
            .init(color: dim, location: 0.90),
            .init(color: .white.opacity(0.95), location: 1.00),
        ], center: .center, angle: .degrees(200))
    }

    var body: some View {
        ZStack {
            // にじんだ光（色の分散）
            shape.strokeBorder(gradient, lineWidth: lineWidth * 2.5)
                .blur(radius: lineWidth * 2)
                .opacity(0.75)
            // くっきりした縁
            shape.strokeBorder(gradient, lineWidth: lineWidth)
            // 縁のすぐ内側の影（厚み）
            shape.inset(by: lineWidth)
                .strokeBorder(Color.black.opacity(0.35), lineWidth: lineWidth)
                .blur(radius: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

/// ガラスの面の立体感: 上部の映り込みと、下部に抜けてくる光
struct GlassVolume<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(LinearGradient(stops: [
                .init(color: .white.opacity(0.26), location: 0),
                .init(color: .white.opacity(0), location: 0.42),
                .init(color: .white.opacity(0), location: 0.72),
                .init(color: .white.opacity(0.12), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Liquid Glass の面を敷く。透明度の高いガラスに、屈折した縁の光・面の映り込み・落ち影を重ねる。
    /// iOS 26 未満ではマテリアル（すりガラス）で代用。
    @ViewBuilder
    func glass(in shape: some InsettableShape, tint: Color? = nil, interactive: Bool = false,
               rim: CGFloat = 1.5) -> some View {
        let decorated = self
            .overlay { GlassVolume(shape: shape) }
            .overlay { GlassRim(shape: shape, lineWidth: rim) }
        let shadow = shape.fill(Color.black.opacity(0.22)).blur(radius: rim * 5).offset(y: rim * 3)
        if #available(iOS 26.0, *) {
            decorated
                .glassEffect(Glass.clear.tint(tint).interactive(interactive), in: shape)
                .background { shadow }
        } else {
            decorated
                .background {
                    ZStack {
                        shadow
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.45)) }
                    }
                }
        }
    }
}

/// ガラス風アイコン用のハイライト（面の映り込み + 屈折した縁の光）
struct GlassSheen: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            GlassVolume(shape: iconShape(size))
            GlassRim(shape: iconShape(size), lineWidth: max(1, size * 0.022))
        }
    }
}

/// アプリアイコン画像があればそれを、無ければ角丸タイル + SF Symbol を表示。
/// glass = true でガラス風の見た目（ウィジェットでは使わない）。
struct ItemIcon: View {
    let item: LaunchItem
    var size: CGFloat = 60
    var glass = false

    var body: some View {
        if let file = item.iconFile, let img = loadIconImage(file) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(iconShape(size))
                .overlay { if glass { GlassSheen(size: size) } }
                .shadow(color: .black.opacity(glass ? 0.3 : 0), radius: size * 0.08, y: size * 0.045)
        } else if glass {
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.45, weight: .light))
                .frame(width: size, height: size)
                .glass(in: iconShape(size), rim: max(1, size * 0.022))
        } else {
            ZStack {
                iconShape(size).fill(.tint.opacity(0.18))
                Image(systemName: item.symbol)
                    .font(.system(size: size * 0.45, weight: .light))
            }
            .frame(width: size, height: size)
        }
    }
}

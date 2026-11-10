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

extension View {
    /// Liquid Glass の面を敷く。iOS 26 未満ではマテリアル（すりガラス）で代用。
    @ViewBuilder
    func glass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.45)) }
                }
            }
        }
    }
}

/// ガラス風アイコン用のハイライト（上部の映り込み + 縁の光）
struct GlassSheen: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            iconShape(size)
                .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
            iconShape(size)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.08), .white.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: max(1, size * 0.025))
        }
        .allowsHitTesting(false)
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
                .shadow(color: .black.opacity(glass ? 0.2 : 0), radius: size * 0.06, y: size * 0.03)
        } else if glass {
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.45, weight: .light))
                .frame(width: size, height: size)
                .glass(in: iconShape(size))
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

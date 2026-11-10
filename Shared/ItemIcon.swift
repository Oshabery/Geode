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

/// アプリアイコン画像があればそれを、無ければ角丸タイル + SF Symbol を表示。
struct ItemIcon: View {
    let item: LaunchItem
    var size: CGFloat = 60

    var body: some View {
        if let file = item.iconFile, let img = loadIconImage(file) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(iconShape(size))
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

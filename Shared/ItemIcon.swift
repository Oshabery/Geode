import SwiftUI
import UIKit

private let iconCache = NSCache<NSString, UIImage>()

func loadIconImage(_ file: String) -> UIImage? {
    if let hit = iconCache.object(forKey: file as NSString) { return hit }
    guard let img = UIImage(contentsOfFile: SharedStorage.iconURL(file).path) else { return nil }
    iconCache.setObject(img, forKey: file as NSString)
    return img
}

/// アプリアイコン画像があればそれを、無ければ丸枠付きの SF Symbol を表示。
struct ItemIcon: View {
    let item: LaunchItem
    var size: CGFloat = 60

    var body: some View {
        if let file = item.iconFile, let img = loadIconImage(file) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.42, weight: .light))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(lineWidth: 1.5).padding(2))
        }
    }
}

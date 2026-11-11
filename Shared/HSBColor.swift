import SwiftUI

/// HSB カラー。H: 0–360、S: 0–100、B: 0–100。
/// "210,80,95" 形式の文字列（カラーコード）として @AppStorage に保存する。
struct HSBColor: RawRepresentable, Equatable {
    var h: Double
    var s: Double
    var b: Double

    init(h: Double, s: Double, b: Double) {
        self.h = min(max(h, 0), 360)
        self.s = min(max(s, 0), 100)
        self.b = min(max(b, 0), 100)
    }

    /// カンマ・空白など数字以外で区切った 3 つの数値を受け付ける
    init?(rawValue: String) {
        let parts = rawValue
            .split(whereSeparator: { !($0.isNumber || $0 == ".") })
            .compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        self.init(h: parts[0], s: parts[1], b: parts[2])
    }

    var rawValue: String { "\(Int(h.rounded())),\(Int(s.rounded())),\(Int(b.rounded()))" }
    var code: String { "\(Int(h.rounded())), \(Int(s.rounded())), \(Int(b.rounded()))" }
    var color: Color { Color(hue: h / 360, saturation: s / 100, brightness: b / 100) }
    /// 明るく淡い色の上では黒いシンボルの方が読みやすい
    var prefersDarkSymbol: Bool { b > 75 && s < 35 }
}

extension LaunchItem {
    /// アイコンのベース色（未指定なら nil）
    var baseHSB: HSBColor? { baseColor.flatMap(HSBColor.init(rawValue:)) }
}

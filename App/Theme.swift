import SwiftUI

/// 設定のキーと初期値
enum Theme {
    static let defaultBackground = HSBColor(h: 220, s: 30, b: 16)
    static let defaultTint = HSBColor(h: 185, s: 70, b: 85)
    static let defaultGrid = HSBColor(h: 0, s: 0, b: 50)

    static let weights: [(name: String, weight: Font.Weight)] = [
        ("細い", .thin), ("やや細い", .light), ("標準", .regular), ("中", .medium),
        ("やや太い", .semibold), ("太い", .bold), ("極太", .heavy),
    ]
    static let defaultWeight = 2

    static func weight(_ index: Int) -> Font.Weight {
        weights.indices.contains(index) ? weights[index].weight : .regular
    }
}

/// HSB を「カラーコード入力 + スライダー」で編集する
struct HSBEditor: View {
    @Binding var color: HSBColor
    @State private var code = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.color)
                    .frame(width: 52, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.secondary.opacity(0.4)))
                TextField("H, S, B（例: 210, 80, 95）", text: $code)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .foregroundStyle(invalid ? Color.red : Color.primary)
                    .onSubmit(applyCode)
            }
            row("H", value: $color.h, range: 0...360, unit: "°")
            row("S", value: $color.s, range: 0...100, unit: "%")
            row("B", value: $color.b, range: 0...100, unit: "%")
        }
        .onAppear { code = color.code }
        .onChange(of: color) { _, new in
            code = new.code
            invalid = false
        }
    }

    private func row(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(label).font(.subheadline.monospaced()).frame(width: 18)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue.rounded()))\(unit)")
                .font(.subheadline.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func applyCode() {
        if let parsed = HSBColor(rawValue: code) {
            color = parsed
            code = parsed.code
            invalid = false
        } else {
            invalid = true
        }
    }
}

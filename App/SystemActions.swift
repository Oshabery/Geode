import SwiftUI
import AVFoundation

/// アプリ起動以外の「本体の操作」。
/// - ライト: Geode 自身が切り替える（URL は geode://torch）
/// - 消音・Wi-Fi など: iOS はアプリから直接操作できないため、ショートカット App で作ったショートカットを名前で実行する
enum SystemActions {
    static let torchURL = "geode://torch"

    /// Geode 自身が処理する URL なら実行する。handled = false のときは通常どおり外部で開く
    @MainActor
    static func performIfBuiltIn(_ url: URL) -> (handled: Bool, error: String?) {
        guard url.scheme?.lowercased() == "geode", url.host?.lowercased() == "torch" else {
            return (false, nil)
        }
        return (true, toggleTorch())
    }

    /// ライトのオン / オフを切り替える。失敗したらその理由を返す
    static func toggleTorch() -> String? {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return "この端末ではライトを使えません（シミュレータでは常にこの表示になります）。"
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.torchMode == .on {
                device.torchMode = .off
            } else {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            }
            return nil
        } catch {
            return "ライトを切り替えられませんでした。\n\(error.localizedDescription)"
        }
    }

    /// ショートカットの実行に失敗したときに戻ってくる URL（BoardStore.handle がエラーを表示する）
    static let shortcutErrorHost = "shortcut-error"

    /// ショートカットを名前で実行する URL。成功したら geode://（何もしない）、失敗したら geode://shortcut-error に戻る
    static func shortcutURL(_ name: String) -> String {
        var c = URLComponents()
        c.scheme = "shortcuts"
        c.host = "x-callback-url"
        c.path = "/run-shortcut"
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "geode://"),
            URLQueryItem(name: "x-error", value: "geode://\(shortcutErrorHost)?name=\(name)"),
        ]
        return c.string ?? "shortcuts://"
    }
}

/// ショートカット経由の操作のひな形
struct ShortcutPreset: Identifiable, Hashable {
    let title: String
    let symbol: String
    let defaultName: String
    /// ショートカット App で検索するアクション名の目安（iOS のバージョンや言語で違うことがある）
    let hint: String?
    var id: String { title }

    static let all: [ShortcutPreset] = [
        .init(title: "マナーモード（消音）", symbol: "bell.slash", defaultName: "Geode 消音モード", hint: "消音モードを設定"),
        .init(title: "Wi-Fi", symbol: "wifi.slash", defaultName: "Geode Wi-Fi", hint: "Wi-Fi を設定"),
        .init(title: "Bluetooth", symbol: "dot.radiowaves.left.and.right", defaultName: "Geode Bluetooth", hint: "Bluetooth を設定"),
        .init(title: "モバイルデータ通信", symbol: "antenna.radiowaves.left.and.right", defaultName: "Geode モバイルデータ", hint: "モバイルデータ通信を設定"),
        .init(title: "機内モード", symbol: "airplane", defaultName: "Geode 機内モード", hint: "機内モードを設定"),
        .init(title: "低電力モード", symbol: "battery.25", defaultName: "Geode 低電力モード", hint: "低電力モードを設定"),
        .init(title: "集中モード", symbol: "moon", defaultName: "Geode 集中モード", hint: "集中モードを設定"),
        .init(title: "ダークモード", symbol: "circle.lefthalf.filled", defaultName: "Geode ダークモード", hint: "外観を設定"),
        .init(title: "画面の明るさ", symbol: "sun.max", defaultName: "Geode 明るさ", hint: "明るさを設定"),
        .init(title: "その他のショートカット", symbol: "square.stack.3d.up", defaultName: "", hint: nil),
    ]
}

/// 本体の操作を選ぶ画面（アクション編集画面から開く）
struct SystemActionPicker: View {
    let onPick: (PickedApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ShortcutPreset?
    @State private var shortcutName = ""

    private var trimmedName: String { shortcutName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                Button {
                    onPick(PickedApp(name: "ライト", urlString: SystemActions.torchURL,
                                     symbol: "flashlight.on.fill", iconFile: nil))
                    dismiss()
                } label: {
                    Label("ライト（オン / オフ切り替え）", systemImage: "flashlight.on.fill")
                }
            } header: {
                Text("Geode で直接実行")
            } footer: {
                Text("Geode の画面のまま、押すたびにオン / オフが切り替わります。")
            }

            Section {
                ForEach(ShortcutPreset.all) { preset in
                    Button {
                        selected = preset
                        shortcutName = preset.defaultName
                    } label: {
                        HStack {
                            Label(preset.title, systemImage: preset.symbol)
                            Spacer()
                            if selected == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } header: {
                Text("ショートカット経由")
            } footer: {
                Text("iOS はアプリから消音モードや Wi-Fi などを直接操作できません。ショートカット App で作ったショートカットを、Geode から名前で実行します。")
            }

            if let preset = selected {
                Section {
                    TextField("ショートカット名", text: $shortcutName)
                        .autocorrectionDisabled()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 下の「ショートカット App を開く」で、新しいショートカットを作ります。")
                        if let hint = preset.hint {
                            Text("2. 「アクションを追加」で「\(hint)」のような名前のアクションを検索して追加します。iOS のバージョンによって名前が違ったり、無かったりします。オン / オフの指定を「切り替える」にすると、押すたびに入れ替わります。")
                        } else {
                            Text("2. 実行したいアクションを追加します。")
                        }
                        Text("3. ショートカットの名前を「\(trimmedName.isEmpty ? "（上で決めた名前）" : trimmedName)」にします。1 文字でも違うと実行できません。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("ショートカット App を開く") {
                        if let url = URL(string: "shortcuts://create-shortcut") {
                            UIApplication.shared.open(url, options: [:]) { ok in
                                if !ok, let fallback = URL(string: "shortcuts://") {
                                    UIApplication.shared.open(fallback)
                                }
                            }
                        }
                    }
                    Button("このアクションを使う") {
                        let title = preset.hint == nil ? trimmedName : preset.title
                        onPick(PickedApp(name: title, urlString: SystemActions.shortcutURL(trimmedName),
                                         symbol: preset.symbol, iconFile: nil))
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                } header: {
                    Text("「\(preset.title)」の準備")
                }
            }
        }
        .navigationTitle("本体の操作")
        .navigationBarTitleDisplayMode(.inline)
    }
}

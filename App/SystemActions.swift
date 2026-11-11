import SwiftUI
import AVFoundation
import MediaPlayer

/// Geode 自身が実行する操作。URL は geode://<rawValue>
enum DirectKind: String, CaseIterable {
    case torch
    case brightness
    case awake
    case musicPlayPause = "music-playpause"
    case musicNext = "music-next"
    case musicPrevious = "music-previous"
    case copy

    /// オン / オフの状態を読めて、ネガポジ反転で表示するもの
    var isSwitch: Bool {
        switch self {
        case .torch, .brightness, .awake, .musicPlayPause: return true
        default: return false
        }
    }
}

/// アプリ起動以外の「本体の操作」。
/// - Geode で直接: ライト、画面の明るさ、スリープさせない、ミュージックの操作、テキストのコピー
/// - 消音・Wi-Fi など: iOS はアプリから直接操作できないため、ショートカット App で作ったショートカットを名前で実行する
enum SystemActions {
    static let torchURL = "geode://torch"
    /// Geode 自身の操作を実行したときの通知。どこから実行しても BoardStore が状態を読み直す
    static let directActionPerformed = Notification.Name("GeodeDirectActionPerformed")
    private static let brightnessBeforeBoostKey = "brightnessBeforeBoost"

    static func url(_ kind: DirectKind) -> String { "geode://\(kind.rawValue)" }

    /// geode:// の URL のうち、操作を表すもの（ウィジェットの run とショートカットの戻りは除く）
    static func isGeodeActionURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "geode", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return host != "run" && host != shortcutErrorHost
    }

    static func directKind(_ url: URL) -> DirectKind? {
        guard isGeodeActionURL(url), let host = url.host?.lowercased() else { return nil }
        return DirectKind(rawValue: host)
    }

    static func directKind(_ string: String) -> DirectKind? {
        URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(directKind)
    }

    static func isTorchURL(_ string: String) -> Bool { directKind(string) == .torch }

    /// オン / オフを表示するアイテムか（Geode の操作は種類で、ショートカット経由は isToggle で決まる）
    static func isSwitch(_ item: LaunchItem) -> Bool {
        guard item.kind == .action else { return false }
        if let kind = directKind(item.urlString) { return kind.isSwitch }
        return item.isToggle == true
    }

    /// 実際の状態を読む。読めないものは nil
    @MainActor
    static func readState(_ kind: DirectKind) -> Bool? {
        switch kind {
        case .torch: return AVCaptureDevice.default(for: .video)?.torchMode == .on
        case .brightness: return UIScreen.main.brightness >= 0.99
        case .awake: return UIApplication.shared.isIdleTimerDisabled
        case .musicPlayPause: return MPMusicPlayerController.systemMusicPlayer.playbackState == .playing
        default: return nil
        }
    }

    /// Geode 自身が処理する URL なら実行する。handled = false のときは通常どおり外部で開く
    @MainActor
    static func performIfBuiltIn(_ url: URL) -> (handled: Bool, error: String?) {
        guard isGeodeActionURL(url) else { return (false, nil) }
        guard let kind = directKind(url) else {
            return (true, "Geode が知らない操作です。\n\(url.absoluteString)")
        }
        let error = perform(kind, url: url)
        NotificationCenter.default.post(name: directActionPerformed, object: nil)
        return (true, error)
    }

    @MainActor
    private static func perform(_ kind: DirectKind, url: URL) -> String? {
        switch kind {
        case .torch:
            return toggleTorch()
        case .brightness:
            let screen = UIScreen.main
            if screen.brightness >= 0.99 {
                let saved = UserDefaults.standard.object(forKey: brightnessBeforeBoostKey) as? Double ?? 0.5
                screen.brightness = CGFloat(saved)
            } else {
                UserDefaults.standard.set(Double(screen.brightness), forKey: brightnessBeforeBoostKey)
                screen.brightness = 1.0
            }
            return nil
        case .awake:
            UIApplication.shared.isIdleTimerDisabled.toggle()
            return nil
        case .musicPlayPause:
            let player = MPMusicPlayerController.systemMusicPlayer
            if player.playbackState == .playing { player.pause() } else { player.play() }
            return nil
        case .musicNext:
            MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
            return nil
        case .musicPrevious:
            MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
            return nil
        case .copy:
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "text" }?.value ?? ""
            guard !text.isEmpty else { return "コピーするテキストが空です。" }
            UIPasteboard.general.string = text
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return nil
        }
    }

    /// ライトのオン / オフを切り替える。失敗したらその理由を返す
    private static func toggleTorch() -> String? {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return "この端末ではライトを使えません（シミュレータでは常にこの表示になります）。"
        }
        do {
            try device.lockForConfiguration()
        } catch {
            return "ライトを切り替えられませんでした。\n\(error.localizedDescription)"
        }
        defer { device.unlockForConfiguration() }
        if device.torchMode == .on {
            device.torchMode = .off
            return nil
        }
        do {
            try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            return nil
        } catch {
            return "ライトを点けられませんでした。\n\(error.localizedDescription)"
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
            URLQueryItem(name: "x-error", value: "geode://\(shortcutErrorHost)"),
        ]
        return c.string ?? "shortcuts://"
    }
}

/// 一覧に並べる「Geode で直接」の操作
struct DirectAction: Identifiable, Hashable {
    enum Input: Hashable {
        case text, phone, email, phoneOrEmail, web, address

        var placeholder: String {
            switch self {
            case .text: return "コピーするテキスト"
            case .phone: return "電話番号"
            case .email: return "メールアドレス"
            case .phoneOrEmail: return "電話番号またはメールアドレス"
            case .web: return "https://example.com"
            case .address: return "住所や施設名"
            }
        }

        var keyboard: UIKeyboardType {
            switch self {
            case .phone: return .phonePad
            case .email, .phoneOrEmail: return .emailAddress
            case .web: return .URL
            default: return .default
            }
        }
    }

    let id: String
    let title: String
    let symbol: String
    var input: Input? = nil
    var note: String? = nil

    static let switches: [DirectAction] = [
        .init(id: "torch", title: "ライト", symbol: "flashlight.on.fill",
              note: "Geode を離れると消えます。"),
        .init(id: "brightness", title: "画面を最大の明るさに", symbol: "sun.max.fill",
              note: "もう一度押すと元の明るさに戻ります。"),
        .init(id: "awake", title: "画面をスリープさせない", symbol: "eye",
              note: "Geode を表示している間だけ有効です。"),
        .init(id: "music-playpause", title: "ミュージック 再生 / 一時停止", symbol: "playpause.fill",
              note: "Apple のミュージック App の再生だけを操作します。"),
    ]

    static let others: [DirectAction] = [
        .init(id: "music-next", title: "ミュージック 次の曲", symbol: "forward.fill"),
        .init(id: "music-previous", title: "ミュージック 前の曲", symbol: "backward.fill"),
        .init(id: "copy", title: "テキストをコピー", symbol: "doc.on.clipboard", input: .text,
              note: "押すと決めたテキストがクリップボードに入ります。"),
        .init(id: "call", title: "電話をかける", symbol: "phone.fill", input: .phone),
        .init(id: "sms", title: "メッセージを送る", symbol: "message.fill", input: .phone),
        .init(id: "mail", title: "メールを書く", symbol: "envelope.fill", input: .email),
        .init(id: "facetime", title: "FaceTime", symbol: "video.fill", input: .phoneOrEmail),
        .init(id: "web", title: "Web ページを開く", symbol: "safari", input: .web),
        .init(id: "route", title: "マップで経路を表示", symbol: "map", input: .address),
    ]

    /// 入力値から URL を作る。作れなければ nil
    func makeURL(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kind = DirectKind(rawValue: id) {
            if kind == .copy {
                guard !v.isEmpty else { return nil }
                var c = URLComponents()
                c.scheme = "geode"
                c.host = DirectKind.copy.rawValue
                c.queryItems = [URLQueryItem(name: "text", value: v)]
                return c.string
            }
            return SystemActions.url(kind)
        }
        guard !v.isEmpty else { return nil }
        let dial = v.filter { "0123456789+*#".contains($0) }
        switch id {
        case "call": return dial.isEmpty ? nil : "tel:\(dial)"
        case "sms": return dial.isEmpty ? nil : "sms:\(dial)"
        case "mail":
            var c = URLComponents()
            c.scheme = "mailto"
            c.path = v
            return c.string
        case "facetime":
            let target = v.contains("@") ? v.replacingOccurrences(of: " ", with: "") : dial
            return target.isEmpty ? nil : "facetime:\(target)"
        case "web":
            return v.contains("://") ? v : "https://\(v)"
        case "route":
            var c = URLComponents(string: "https://maps.apple.com/")
            c?.queryItems = [URLQueryItem(name: "daddr", value: v)]
            return c?.string
        default: return nil
        }
    }
}

/// ショートカット経由の操作のひな形
struct ShortcutPreset: Identifiable, Hashable {
    let title: String
    let symbol: String
    let defaultName: String
    /// ショートカット App で検索するアクション名の目安（iOS のバージョンや言語で違うことがある）
    let hint: String?
    /// オン / オフのスイッチとして表示するか
    var isSwitch = true
    /// スイッチの初期状態（普段オンのもの）
    var startsOn = false
    var id: String { title }

    static let all: [ShortcutPreset] = [
        .init(title: "ライト（Geode を離れても点いたまま）", symbol: "flashlight.on.fill", defaultName: "Geode ライト", hint: "懐中電灯を設定"),
        .init(title: "マナーモード（消音）", symbol: "bell.slash", defaultName: "Geode 消音モード", hint: "消音モードを設定"),
        .init(title: "Wi-Fi", symbol: "wifi.slash", defaultName: "Geode Wi-Fi", hint: "Wi-Fi を設定", startsOn: true),
        .init(title: "Bluetooth", symbol: "dot.radiowaves.left.and.right", defaultName: "Geode Bluetooth", hint: "Bluetooth を設定", startsOn: true),
        .init(title: "モバイルデータ通信", symbol: "antenna.radiowaves.left.and.right", defaultName: "Geode モバイルデータ", hint: "モバイルデータ通信を設定", startsOn: true),
        .init(title: "機内モード", symbol: "airplane", defaultName: "Geode 機内モード", hint: "機内モードを設定"),
        .init(title: "低電力モード", symbol: "battery.25", defaultName: "Geode 低電力モード", hint: "低電力モードを設定"),
        .init(title: "集中モード", symbol: "moon", defaultName: "Geode 集中モード", hint: "集中モードを設定"),
        .init(title: "ダークモード", symbol: "circle.lefthalf.filled", defaultName: "Geode ダークモード", hint: "外観を設定"),
        .init(title: "画面の明るさ", symbol: "sun.max", defaultName: "Geode 明るさ", hint: "明るさを設定", isSwitch: false),
        .init(title: "その他のショートカット", symbol: "square.stack.3d.up", defaultName: "", hint: nil, isSwitch: false),
    ]
}

/// 本体の操作を選ぶ画面（アクション編集画面から開く）
struct SystemActionPicker: View {
    let onPick: (PickedApp) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Selection: Hashable {
        case direct(DirectAction)
        case shortcut(ShortcutPreset)
    }

    @State private var selected: Selection?
    @State private var value = ""

    private var trimmed: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                ForEach(DirectAction.switches) { directRow($0) }
            } header: {
                Text("Geode で直接実行（オン / オフ）")
            } footer: {
                Text("オンの間はアイコンの色が反転します。ショートカット App は開きません。")
            }

            Section {
                ForEach(DirectAction.others) { directRow($0) }
            } header: {
                Text("Geode で直接実行")
            }

            Section {
                ForEach(ShortcutPreset.all) { preset in
                    Button {
                        selected = .shortcut(preset)
                        value = preset.defaultName
                    } label: {
                        row(title: preset.title, symbol: preset.symbol, checked: selected == .shortcut(preset))
                    }
                }
            } header: {
                Text("ショートカット経由")
            } footer: {
                Text("消音モードや Wi-Fi などは、iOS がアプリからの操作を許していません。ショートカット App で作ったショートカットを、Geode から名前で実行します。")
            }

            if let selected {
                detail(selected)
            }
        }
        .navigationTitle("本体の操作")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, symbol: String, checked: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if checked { Image(systemName: "checkmark") }
        }
    }

    private func directRow(_ action: DirectAction) -> some View {
        Button {
            if action.input == nil, let url = action.makeURL("") {
                pick(action, url: url)
            } else {
                selected = .direct(action)
                value = ""
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                row(title: action.title, symbol: action.symbol, checked: selected == .direct(action))
                if let note = action.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pick(_ action: DirectAction, url: String) {
        let kind = DirectKind(rawValue: action.id)
        onPick(PickedApp(name: action.title, urlString: url, symbol: action.symbol, iconFile: nil,
                         isToggle: kind?.isSwitch ?? false))
        dismiss()
    }

    @ViewBuilder
    private func detail(_ selection: Selection) -> some View {
        switch selection {
        case .direct(let action):
            if let input = action.input {
                Section {
                    TextField(input.placeholder, text: $value)
                        .keyboardType(input.keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("このアクションを使う") {
                        if let url = action.makeURL(trimmed) { pick(action, url: url) }
                    }
                    .disabled(action.makeURL(trimmed) == nil)
                } header: {
                    Text("「\(action.title)」の設定")
                }
            }
        case .shortcut(let preset):
            Section {
                TextField("ショートカット名", text: $value)
                    .autocorrectionDisabled()
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 下の「ショートカット App を開く」で、新しいショートカットを作ります。")
                    if let hint = preset.hint {
                        Text("2. 「アクションを追加」で「\(hint)」のような名前のアクションを検索して追加します。iOS のバージョンによって名前が違ったり、無かったりします。オン / オフの指定を「切り替える」にすると、押すたびに入れ替わります。")
                    } else {
                        Text("2. 実行したいアクションを追加します。")
                    }
                    Text("3. ショートカットの名前を「\(trimmed.isEmpty ? "（上で決めた名前）" : trimmed)」にします。1 文字でも違うと実行できません。")
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
                    let title = preset.hint == nil ? trimmed : preset.title
                    onPick(PickedApp(name: title, urlString: SystemActions.shortcutURL(trimmed),
                                     symbol: preset.symbol, iconFile: nil, isToggle: preset.isSwitch,
                                     startsOn: preset.startsOn))
                    dismiss()
                }
                .disabled(trimmed.isEmpty)
            } header: {
                Text("「\(preset.title)」の準備")
            }
        }
    }
}

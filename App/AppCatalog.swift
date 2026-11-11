import UIKit

/// 既知アプリの URL スキーム辞書。
/// iOS には「インストール済みアプリ一覧」を取得する公開 API が無いため、
/// この辞書 + canOpenURL で「入っているか」を判定する。
/// サードパーティのスキームを追加したら project.yml の LSApplicationQueriesSchemes にも追加すること(最大50)。
struct CatalogApp: Identifiable, Hashable, Codable {
    var name: String
    var scheme: String               // 空 = スキーム未登録（実機一覧から取り込んだだけのアプリ）
    var bundleId: String? = nil      // App Store からアイコンを引くキー
    var iconSearch: String? = nil    // bundleId が不明なとき、この語で App Store 検索してアイコンを取る
    var symbol: String = "app"
    var system = false               // 標準アプリ: 判定せず常に候補に出す
    var id: String { scheme.isEmpty ? "bundle:" + (bundleId ?? name) : scheme }
}

enum AppCatalog {
    static let all: [CatalogApp] = [
        // --- Apple 標準（非公式スキーム含む。OS 更新で変わる可能性あり） ---
        .init(name: "設定", scheme: "App-prefs:", symbol: "gearshape", system: true),
        .init(name: "写真", scheme: "photos-redirect://", symbol: "photo.on.rectangle", system: true),
        .init(name: "カメラ", scheme: "camera://", symbol: "camera", system: true),
        .init(name: "App Store", scheme: "itms-apps://", symbol: "bag", system: true),
        .init(name: "メッセージ", scheme: "sms:", symbol: "message", system: true),
        .init(name: "メール", scheme: "message://", bundleId: "com.apple.mobilemail", symbol: "envelope", system: true),
        .init(name: "Safari 検索", scheme: "x-web-search://", symbol: "safari", system: true),
        .init(name: "マップ", scheme: "maps://", bundleId: "com.apple.Maps", symbol: "map", system: true),
        .init(name: "ミュージック", scheme: "music://", bundleId: "com.apple.Music", symbol: "music.note", system: true),
        .init(name: "メモ", scheme: "mobilenotes://", bundleId: "com.apple.mobilenotes", symbol: "note.text", system: true),
        .init(name: "リマインダー", scheme: "x-apple-reminderkit://", bundleId: "com.apple.reminders", symbol: "checklist", system: true),
        .init(name: "カレンダー", scheme: "calshow://", bundleId: "com.apple.mobilecal", symbol: "calendar", system: true),
        .init(name: "ファイル", scheme: "shareddocuments://", bundleId: "com.apple.DocumentsApp", symbol: "folder", system: true),
        .init(name: "ショートカット", scheme: "shortcuts://", bundleId: "com.apple.shortcuts", symbol: "square.stack.3d.up", system: true),
        .init(name: "Wallet", scheme: "shoebox://", symbol: "wallet.pass", system: true),
        .init(name: "FaceTime", scheme: "facetime://", bundleId: "com.apple.facetime", symbol: "video", system: true),
        .init(name: "Watch", scheme: "itms-watchs://", bundleId: "com.apple.Bridge", symbol: "applewatch", system: true),
        // --- サードパーティ（canOpenURL で検出） ---
        .init(name: "Apple Store", scheme: "applestore://", bundleId: "com.apple.store.Jolly", symbol: "bag"),
        .init(name: "LINE", scheme: "line://", bundleId: "jp.naver.line", symbol: "bubble.left"),
        .init(name: "X (Twitter)", scheme: "twitter://", bundleId: "com.atebits.Tweetie2", symbol: "bird"),
        .init(name: "Instagram", scheme: "instagram://", bundleId: "com.burbn.instagram", symbol: "camera.aperture"),
        .init(name: "Facebook", scheme: "fb://", bundleId: "com.facebook.Facebook", symbol: "person.2"),
        .init(name: "Threads", scheme: "barcelona://", bundleId: "com.burbn.barcelona", symbol: "at"),
        .init(name: "YouTube", scheme: "youtube://", bundleId: "com.google.ios.youtube", symbol: "play.rectangle"),
        .init(name: "Google Maps", scheme: "comgooglemaps://", bundleId: "com.google.Maps", symbol: "mappin.and.ellipse"),
        .init(name: "Google Drive", scheme: "googledrive://", bundleId: "com.google.Drive", symbol: "externaldrive"),
        .init(name: "Gmail", scheme: "googlegmail://", bundleId: "com.google.Gmail", symbol: "envelope"),
        .init(name: "Chrome", scheme: "googlechrome://", bundleId: "com.google.chrome.ios", symbol: "globe"),
        .init(name: "Google", scheme: "google://", bundleId: "com.google.GoogleMobile", symbol: "magnifyingglass"),
        .init(name: "Spotify", scheme: "spotify://", bundleId: "com.spotify.client", symbol: "music.note.list"),
        .init(name: "Amazon", scheme: "com.amazon.mobile.shopping://", bundleId: "com.amazon.Amazon", symbol: "cart"),
        .init(name: "Kindle", scheme: "kindle://", bundleId: "com.amazon.Lassen", symbol: "book"),
        .init(name: "PayPay", scheme: "paypay://", bundleId: "jp.ne.paypay.iosapp", symbol: "yensign.circle"),
        .init(name: "メルカリ", scheme: "mercari://", bundleId: "com.kouzoh.mercari", symbol: "shippingbox"),
        .init(name: "Slack", scheme: "slack://", bundleId: "com.tinyspeck.chatlyio", symbol: "number"),
        .init(name: "Discord", scheme: "discord://", bundleId: "com.hammerandchisel.discord", symbol: "gamecontroller"),
        .init(name: "Notion", scheme: "notion://", bundleId: "notion.id", symbol: "doc.text"),
        .init(name: "ChatGPT", scheme: "chatgpt://", bundleId: "com.openai.chat", symbol: "sparkles"),
        .init(name: "Claude", scheme: "claude://", bundleId: "com.anthropic.claude", symbol: "sparkle"),
        .init(name: "Netflix", scheme: "nflx://", bundleId: "com.netflix.Netflix", symbol: "tv"),
        .init(name: "Zoom", scheme: "zoomus://", bundleId: "us.zoom.videomeetings", symbol: "video"),
        .init(name: "Teams", scheme: "msteams://", bundleId: "com.microsoft.skype.teams", symbol: "person.3"),
        .init(name: "WhatsApp", scheme: "whatsapp://", bundleId: "net.whatsapp.WhatsApp", symbol: "phone.bubble"),
        .init(name: "Telegram", scheme: "tg://", bundleId: "ph.telegra.Telegraph", symbol: "paperplane"),
        .init(name: "Lightroom", scheme: "lightroom://", bundleId: "com.adobe.lrmobile", symbol: "camera.filters"),
        // ↓ 2 件のスキームは推定値（未検証）。開けない場合は URL 欄で修正する
        .init(name: "Leica FOTOS", scheme: "leicafotos://", iconSearch: "Leica FOTOS", symbol: "camera.circle"),
        .init(name: "VOX Player", scheme: "vox://", bundleId: "com.coppertino.VoxMobile", iconSearch: "VOX Music Player", symbol: "speaker.wave.2.circle"),
        // ↓ ゲーム 3 件のスキームも推定値（未検証）
        .init(name: "アークナイツ", scheme: "arknights://", iconSearch: "アークナイツ", symbol: "gamecontroller"),
        .init(name: "エンドフィールド", scheme: "endfield://", iconSearch: "アークナイツ：エンドフィールド", symbol: "gamecontroller"),
        .init(name: "ポケポケ", scheme: "pokemontcgp://", iconSearch: "Pokémon Trading Card Game Pocket", symbol: "rectangle.portrait.on.rectangle.portrait"),
        .init(name: "Uber", scheme: "uber://", bundleId: "com.ubercab.UberClient", symbol: "car"),
        .init(name: "Twitch", scheme: "twitch://", bundleId: "tv.twitch", symbol: "play.tv"),
        .init(name: "Pinterest", scheme: "pinterest://", bundleId: "pinterest", symbol: "pin"),
        .init(name: "Things", scheme: "things://", bundleId: "com.culturedcode.ThingsiPhone", symbol: "checkmark.square"),
        .init(name: "Bear", scheme: "bear://", bundleId: "net.shinyfrog.bear-iOS", symbol: "pencil.line"),
        .init(name: "Obsidian", scheme: "obsidian://", bundleId: "md.obsidian", symbol: "diamond"),
        .init(name: "GitHub", scheme: "github://", bundleId: "com.github.stormbreaker.prod", symbol: "chevron.left.forwardslash.chevron.right"),
    ]

    @MainActor
    static func isInstalled(_ app: CatalogApp) -> Bool {
        if app.system { return true }
        guard let url = URL(string: app.scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    @MainActor
    static func installed() -> [CatalogApp] { all.filter(isInstalled) }

    static func scheme(forBundleId id: String) -> String? {
        all.first { $0.bundleId == id }?.scheme
    }
}

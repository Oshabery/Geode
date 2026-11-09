import UIKit

/// iTunes Search API からアプリアイコンを取得して共有コンテナへ保存する。
enum IconService {
    struct StoreApp: Decodable, Identifiable {
        let trackId: Int
        let trackName: String
        let bundleId: String
        let artworkUrl512: URL?
        let artworkUrl100: URL?
        var id: Int { trackId }
        var artwork: URL? { artworkUrl512 ?? artworkUrl100 }
    }
    private struct Response: Decodable { let results: [StoreApp] }

    private static var country: String { Locale.current.region?.identifier ?? "JP" }

    static func lookup(bundleId: String) async -> StoreApp? {
        var c = URLComponents(string: "https://itunes.apple.com/lookup")!
        c.queryItems = [.init(name: "bundleId", value: bundleId), .init(name: "country", value: country)]
        return (try? await fetch(c.url!))?.first
    }

    static func search(_ term: String) async -> [StoreApp] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: "software"),
                        .init(name: "country", value: country), .init(name: "limit", value: "20")]
        return (try? await fetch(c.url!)) ?? []
    }

    private static func fetch(_ url: URL) async throws -> [StoreApp] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Response.self, from: data).results
    }

    /// bundleId → 保存済みアイコンのファイル名
    static func icon(forBundleId bundleId: String) async -> String? {
        guard let app = await lookup(bundleId: bundleId), let url = app.artwork else { return nil }
        return await download(url)
    }

    /// 辞書アプリのアイコン: bundleId で引き、だめなら名前検索
    static func icon(for app: CatalogApp) async -> String? {
        if let id = app.bundleId, let file = await icon(forBundleId: id) { return file }
        if let term = app.iconSearch, let url = await search(term).first?.artwork { return await download(url) }
        return nil
    }

    static func download(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        return save(image)
    }

    /// ウィジェットのメモリ制限に配慮して 180px に縮小して保存
    static func save(_ image: UIImage) -> String? {
        let side: CGFloat = 180
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale = max(side / image.size.width, side / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        let resized = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        guard let png = resized.pngData() else { return nil }
        let name = UUID().uuidString + ".png"
        do {
            try png.write(to: SharedStorage.iconURL(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}

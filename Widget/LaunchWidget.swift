import WidgetKit
import SwiftUI
import AppIntents

// MARK: 設定（どの階層を表示するか）

struct GroupEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "グループ"
    static let defaultQuery = GroupQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct GroupQuery: EntityQuery {
    private func all() -> [GroupEntity] {
        SharedStorage.loadBoard().groups.map { GroupEntity(id: $0.id.uuidString, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [GroupEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [GroupEntity] { all() }
}

struct SelectSourceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "表示内容"
    static let description = IntentDescription("ホーム階層、または選んだグループの中身を表示します。")

    @Parameter(title: "グループ（未選択ならホーム階層）")
    var group: GroupEntity?
}

// MARK: タイムライン

struct LaunchEntry: TimelineEntry {
    let date: Date
    let items: [LaunchItem]
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: .now, items: []) }

    func snapshot(for configuration: SelectSourceIntent, in context: Context) async -> LaunchEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectSourceIntent, in context: Context) async -> Timeline<LaunchEntry> {
        // アプリ側で保存のたびに reloadAllTimelines するので定期更新は不要
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SelectSourceIntent) -> LaunchEntry {
        let board = SharedStorage.loadBoard()
        var slots = board.slots
        if let gid = configuration.group?.id,
           let group = board.slots.values.first(where: { $0.id.uuidString == gid }) {
            slots = group.children
        }
        return LaunchEntry(date: .now, items: slots.sorted { $0.key < $1.key }.map(\.value))
    }
}

// MARK: 表示

struct LaunchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LaunchEntry

    private func url(_ item: LaunchItem) -> URL {
        URL(string: "geode://run?id=\(item.id.uuidString)")!
    }

    var body: some View {
        Group {
            if entry.items.isEmpty {
                Text("アプリでアクションを追加してください")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else if family == .systemSmall {
                // small は領域全体で 1 リンクのみ（WidgetKit の制約）
                let item = entry.items[0]
                VStack(spacing: 8) {
                    ItemIcon(item: item, size: 72)
                    Text(item.name).font(.caption).lineLimit(1)
                }
                .widgetURL(url(item))
            } else {
                let columns = 4
                let count = family == .systemLarge ? 16 : 8
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 10) {
                    ForEach(entry.items.prefix(count)) { item in
                        Link(destination: url(item)) {
                            VStack(spacing: 4) {
                                ItemIcon(item: item, size: 50)
                                Text(item.name).font(.system(size: 10)).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.tint)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct LaunchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LaunchWidget", intent: SelectSourceIntent.self, provider: Provider()) { entry in
            LaunchWidgetView(entry: entry)
        }
        .configurationDisplayName("Geode")
        .description("ホーム画面からアクションを直接起動します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct LaunchWidgetBundle: WidgetBundle {
    var body: some Widget { LaunchWidget() }
}

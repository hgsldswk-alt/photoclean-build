import SwiftUI
import WidgetKit

struct CleanupEntry: TimelineEntry {
    let date: Date
    let data: AppData
}

struct CleanupProvider: TimelineProvider {
    func placeholder(in context: Context) -> CleanupEntry {
        var data = AppData(); data.entitlement.purchasedPro = true; data.widgetNewCount = 386; data.widgetUnreviewed = 224
        return CleanupEntry(date: Date(), data: data)
    }
    func getSnapshot(in context: Context, completion: @escaping (CleanupEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : CleanupEntry(date: Date(), data: (try? Store.load()) ?? AppData()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CleanupEntry>) -> Void) {
        let now = Date(), data = (try? Store.load()) ?? AppData()
        completion(Timeline(entries: [CleanupEntry(date: now, data: data)], policy: .after(now.addingTimeInterval(3600))))
    }
}

struct CleanupWidgetView: View {
    let entry: CleanupEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    private var key: String { CalendarKey.month(entry.date) }
    private var current: Bool { entry.data.widgetMonth == key }
    private var count: Int { current ? entry.data.widgetNewCount : 0 }
    private var unseen: Int { current ? entry.data.widgetUnreviewed : 0 }
    private var ink: Color { Color(red: 34/255, green: 48/255, blue: 74/255) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.t("相册清理"), systemImage: "rectangle.stack").font(.caption.bold())
            if entry.data.entitlement.hasPro(at: entry.date) {
                let freed = entry.data.stats.monthly[key] ?? CleanupTotal()
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(freed.bytes > 0 ? Bytes.format(freed.bytes) : count.formatted())
                            .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                        Text(freed.bytes > 0 ? L.t("本月已整理空间") : L.t("本月新照片")).font(.caption)
                    }
                    if family == .systemMedium {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(unseen.formatted()).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(L.t("张还未整理")).font(.caption)
                        }
                    }
                }
                Text(freed.bytes > 0 ? L.t("清空「最近删除」后释放") : L.f("%@ 张还未整理", unseen.formatted())).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(L.t("给手机一点空间")).font(.headline)
                Text(L.t("买断后可添加整理小组件")).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(colorScheme == .dark ? Color.white : ink)
        .containerBackground(for: .widget) {
            colorScheme == .dark ? Color(red: 18/255, green: 20/255, blue: 23/255) : Color(red: 247/255, green: 246/255, blue: 243/255)
        }
        .widgetURL(URL(string: "photoclean://swipe?month=" + key))
    }
}

@main struct PhotoCleanWidget: Widget {
    let kind = "PhotoCleanWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CleanupProvider()) { CleanupWidgetView(entry: $0) }
            .configurationDisplayName(L.t("相册清理"))
            .description(L.t("本月照片与整理进度，一眼看到。"))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

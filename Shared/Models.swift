import Foundation

struct PhotoAsset: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var created: Date
    var modified: Date
    var width: Int = 3024
    var height: Int = 4032
    var bytes: Int64 = 0
    var approximate = false
    var isVideo = false
    var duration: Double = 0
    var screenshot = false
    var favorite = false
    var live = false
    var burst: String?
    var burstPick = false
    var sharpness: Double = 0
    var pixels: Int64 { Int64(width) * Int64(height) }
    var cacheKey: String { id + "|" + String(modified.timeIntervalSince1970) }
}

enum CalendarKey {
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func month(_ date: Date, calendar: Calendar = .current) -> String { String(day(date, calendar: calendar).prefix(7)) }
    static func monthDate(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), (1...9999).contains(year), (1...12).contains(month) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }
    static func monthTitle(_ key: String) -> String {
        guard let date = monthDate(key) else { return key }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return f.string(from: date)
    }
}

struct PhotoMonth: Identifiable, Sendable {
    let id: String
    let assets: [PhotoAsset]
    func reviewed(_ ids: Set<String>) -> Int { assets.filter { ids.contains($0.id) }.count }
}

enum Category: String, CaseIterable, Identifiable, Hashable {
    case similar, duplicates, screenshots, videos
    var id: String { rawValue }
    var title: String {
        switch self {
        case .similar: return L.t("相似照片")
        case .duplicates: return L.t("重复照片")
        case .screenshots: return L.t("截图")
        case .videos: return L.t("大视频")
        }
    }
    var symbol: String {
        switch self {
        case .similar: return "square.on.square"
        case .duplicates: return "square.stack.3d.up"
        case .screenshots: return "viewfinder"
        case .videos: return "play.rectangle"
        }
    }
}

struct PhotoGroup: Identifiable, Sendable {
    let assets: [PhotoAsset]
    let bestID: String
    var id: String { assets.map(\.id).sorted().joined(separator: "|") }
    var selectedIDs: Set<String> { Set(assets.filter { $0.id != bestID && !$0.favorite }.map(\.id)) }
}

enum Bytes {
    static func format(_ value: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]; f.includesActualByteCount = false
        return f.string(fromByteCount: max(0, value))
    }
    static func total(_ assets: [PhotoAsset]) -> Int64 { assets.reduce(0) { $0 + max(0, $1.bytes) } }
    static func label(_ assets: [PhotoAsset]) -> String {
        let value = format(total(assets))
        return assets.contains(where: \.approximate) ? L.f("约 %@", value) : value
    }
}

enum ShareText {
    static var hashtags: String { hashtags(language: Bundle.main.preferredLocalizations.first ?? "en") }
    static func hashtags(language: String) -> String {
        let language = language.replacingOccurrences(of: "_", with: "-").lowercased()
        if language.hasPrefix("zh") {
            if language.contains("hant") || language.contains("-tw") || language.contains("-hk") || language.contains("-mo") {
                return "#相簿清理 #iPhone容量不足 #斷捨離"
            }
            return "#相册清理 #iPhone内存不足 #断舍离"
        }
        return "#photocleaner #iphonestorage #declutter"
    }
    static func caption(bytes: Int64, count: Int) -> String {
        L.f("我整理了 %@ 张照片，为手机减负 %@。", String(count), Bytes.format(bytes)) + "\n" + hashtags
    }
    static func downloadURL(id: String?) -> URL? {
        guard let id, !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), id != "0" else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id)
    }
}

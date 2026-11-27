import Foundation

enum DemoCatalog {
    enum Scene: Int, CaseIterable, Sendable {
        case sunset, lake, stillLife, hill, flower, city, clouds, food, mountain, night
    }
    struct Appearance: Equatable, Sendable {
        let scene: Scene
        let seed: UInt64
        let screenshot: Bool
    }

    static func appearance(_ asset: PhotoAsset) -> Appearance {
        let index = Int(asset.id.split(separator: "-").last ?? "0") ?? 0
        let local = index % 172
        let grouped = !asset.isVideo && (local < 12 || (40..<46).contains(local))
        let duplicate = grouped && local < 12 && index / 4 % 3 == 0
        let group = (40..<46).contains(local) ? index / 172 * 43 + 10 : index / 4
        let sceneIndex = asset.isVideo ? index + 5 : (grouped ? group + (duplicate ? 2 : 0) : index)
        let seed = duplicate ? UInt64(group + 1) * 7919 : UInt64(index + 1) * 104729
        return Appearance(scene: Scene(rawValue: sceneIndex % Scene.allCases.count) ?? .sunset,
                          seed: seed, screenshot: asset.screenshot)
    }

    static func makeAssets(now: Date, calendar: Calendar = .current) -> [PhotoAsset] {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var assets: [PhotoAsset] = []
        for month in 0..<14 {
            let base = calendar.date(byAdding: .month, value: -month, to: start) ?? start
            let next = calendar.date(byAdding: .month, value: 1, to: base) ?? now
            let end = min(now, next.addingTimeInterval(-1))
            let availableDays = max(1, calendar.dateComponents([.day], from: base, to: end).day.map { $0 + 1 } ?? 1)
            for n in 0..<172 {
                let day = (n / 8) % availableDays
                let dayStart = calendar.date(byAdding: .day, value: day, to: base) ?? base
                let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
                let upper = min(end, nextDay.addingTimeInterval(-1))
                let anchor = min(dayStart.addingTimeInterval(10 * 3600), upper)
                let date = max(dayStart, anchor.addingTimeInterval(-Double(7 - n % 8) * 55))
                let index = month * 172 + n
                let screenshot = n >= 12 && !(40..<46).contains(n) && n % 13 == 0
                assets.append(PhotoAsset(id: "demo-\(index)", created: date, modified: date,
                    bytes: Int64(2_400_000 + (index % 17) * 410_000), screenshot: screenshot,
                    favorite: n % 23 == 0, live: !screenshot && n % 11 == 0,
                    burst: (40..<46).contains(n) ? "burst-\(month)" : nil, burstPick: n == 42,
                    sharpness: Double(index % 31)))
            }
        }
        for n in 0..<12 {
            let date = now.addingTimeInterval(-Double(n + 1) * 86400 - 7200)
            assets.append(PhotoAsset(id: "video-\(n)", created: date, modified: date, width: 3840, height: 2160,
                bytes: Int64(780_000_000 - n * 39_000_000), isVideo: true, duration: Double(48 + n * 17)))
        }
        return assets.sorted { $0.created == $1.created ? $0.id < $1.id : $0.created > $1.created }
    }
}

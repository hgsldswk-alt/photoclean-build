import UIKit
import Photos
import AVFoundation

@MainActor final class DemoLibrary: PhotoLibrary {
    var onChange: (() -> Void)?
    private var assets: [PhotoAsset]
    private let denied: Bool
    private let cache = NSCache<NSString, UIImage>()
    init(denied: Bool, now: Date = Date()) {
        self.denied = denied; assets = Self.makeAssets(now: now); cache.countLimit = 80; cache.totalCostLimit = 48 * 1024 * 1024
    }
    func authorization() async -> LibraryAccess { denied ? .denied : .authorized }
    func requestAuthorization() async -> LibraryAccess { await authorization() }
    func fetch(onBatch: @escaping @MainActor ([PhotoAsset]) async -> Void) async throws -> [PhotoAsset] { assets }
    func thumbnail(_ asset: PhotoAsset, size: CGSize, network: Bool) async -> UIImage? {
        let pixels = CGSize(width: max(1, size.width.rounded(.up)), height: max(1, size.height.rounded(.up)))
        let width = Int(pixels.width), height = Int(pixels.height)
        let keyText: String = "\(asset.cacheKey)|\(width)x\(height)"
        let key = keyText as NSString
        if let image = cache.object(forKey: key) { return image }
        let appearance = DemoCatalog.appearance(asset)
        let image = await Task.detached(priority: .userInitiated) {
            DemoSceneRenderer.draw(appearance, size: pixels)
        }.value
        cache.setObject(image, forKey: key, cost: Int(pixels.width * pixels.height * 4))
        return image
    }
    func delete(_ photos: [PhotoAsset]) async throws -> Bool {
        let ids = Set(photos.map(\.id)); assets.removeAll { ids.contains($0.id) }; return true
    }
    func playerItem(_ asset: PhotoAsset) async -> AVPlayerItem? { nil }
    func livePhoto(_ asset: PhotoAsset) async -> PHLivePhoto? { nil }
    func preheat(_ assets: [PhotoAsset]) {}
    func selectMore(from controller: UIViewController) {}
    nonisolated static func makeAssets(now: Date) -> [PhotoAsset] {
        DemoCatalog.makeAssets(now: now)
    }
    nonisolated static func distance(_ a: PhotoAsset, _ b: PhotoAsset) -> Float? {
        guard let x = Int(a.id.split(separator: "-").last ?? ""), let y = Int(b.id.split(separator: "-").last ?? "") else { return nil }
        if x % 172 < 12 && y % 172 < 12 && x / 4 == y / 4 { return x / 4 % 3 == 0 ? 0.018 : 0.19 }
        return 0.9
    }
}

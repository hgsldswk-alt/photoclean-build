import UIKit
import Photos
import AVFoundation

enum LibraryAccess: Equatable {
    case notDetermined, denied, restricted, limited, authorized
    var readable: Bool { self == .authorized || self == .limited }
}

@MainActor protocol PhotoLibrary: AnyObject {
    var onChange: (() -> Void)? { get set }
    func authorization() async -> LibraryAccess
    func requestAuthorization() async -> LibraryAccess
    func fetch(onBatch: @escaping @MainActor ([PhotoAsset]) async -> Void) async throws -> [PhotoAsset]
    func thumbnail(_ asset: PhotoAsset, size: CGSize, network: Bool) async -> UIImage?
    func delete(_ assets: [PhotoAsset]) async throws -> Bool
    func playerItem(_ asset: PhotoAsset) async -> AVPlayerItem?
    func livePhoto(_ asset: PhotoAsset) async -> PHLivePhoto?
    func preheat(_ assets: [PhotoAsset])
    func selectMore(from controller: UIViewController)
}

private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    let changed: @Sendable () -> Void
    init(changed: @escaping @Sendable () -> Void) { self.changed = changed }
    func photoLibraryDidChange(_ changeInstance: PHChange) { changed() }
}

private final class ImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var finished = false
    private var request: PHImageRequestID?
    func bind(_ c: CheckedContinuation<UIImage?, Never>) {
        lock.lock()
        if finished { lock.unlock(); c.resume(returning: nil) }
        else { continuation = c; lock.unlock() }
    }
    func setRequest(_ id: PHImageRequestID, manager: PHImageManager) {
        lock.lock(); request = id; let stop = finished; lock.unlock()
        if stop { manager.cancelImageRequest(id) }
    }
    func finish(_ image: UIImage?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: image)
    }
    func cancel(manager: PHImageManager) {
        lock.lock(); let id = request; lock.unlock()
        finish(nil); if let id { manager.cancelImageRequest(id) }
    }
}

@MainActor final class PhotoKitLibrary: PhotoLibrary {
    var onChange: (() -> Void)?
    private let manager = PHCachingImageManager()
    private var observer: LibraryObserver?
    private var preheated: [PHAsset] = []
    init() {
        let observer = LibraryObserver { [weak self] in Task { @MainActor in self?.onChange?() } }
        self.observer = observer; PHPhotoLibrary.shared().register(observer)
    }
    deinit { if let observer { PHPhotoLibrary.shared().unregisterChangeObserver(observer) } }
    private static func access(_ status: PHAuthorizationStatus) -> LibraryAccess {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .limited: return .limited
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }
    func authorization() async -> LibraryAccess { Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    func requestAuthorization() async -> LibraryAccess {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.access(status)
    }
    func fetch(onBatch: @escaping @MainActor ([PhotoAsset]) async -> Void) async throws -> [PhotoAsset] {
        let worker = Task.detached(priority: .userInitiated) { () async throws -> [PhotoAsset] in
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let sizeFile = base?.appendingPathComponent("PhotoClean/resource-sizes.json")
            var sizes = ResourceSizeCache.load(sizeFile)
            let options = PHFetchOptions(); options.includeAllBurstAssets = true
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            var source: [PHAsset] = []; source.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in source.append(asset) }
            var photos = source.map { asset in
                PhotoAsset(id: asset.localIdentifier, created: asset.creationDate ?? .distantPast,
                    modified: asset.modificationDate ?? asset.creationDate ?? .distantPast,
                    width: asset.pixelWidth, height: asset.pixelHeight,
                    bytes: Int64(Double(asset.pixelWidth) * Double(asset.pixelHeight) * 0.35), approximate: true,
                    isVideo: asset.mediaType == .video, duration: asset.duration,
                    screenshot: asset.mediaSubtypes.contains(.photoScreenshot), favorite: asset.isFavorite,
                    live: asset.mediaSubtypes.contains(.photoLive), burst: asset.burstIdentifier,
                    burstPick: asset.representsBurst || asset.burstSelectionTypes.contains(.userPick) || asset.burstSelectionTypes.contains(.autoPick))
            }
            let previousCount = sizes.entries.count
            sizes.retain(photos)
            for i in photos.indices { _ = sizes.apply(to: &photos[i]) }
            await onBatch(photos)
            var lookedUp = 0
            for i in source.indices {
                try Task.checkCancellation()
                guard sizes.entries[photos[i].cacheKey] == nil else { continue }
                let resources = PHAssetResource.assetResources(for: source[i])
                var chosen: [PHAssetResource] = []
                if source[i].mediaType == .video {
                    if let resource = resources.first(where: { $0.type == .fullSizeVideo }) ?? resources.first(where: { $0.type == .video }) { chosen.append(resource) }
                } else {
                    if let resource = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) { chosen.append(resource) }
                    if source[i].mediaSubtypes.contains(.photoLive), let paired = resources.first(where: { $0.type == .fullSizePairedVideo }) ?? resources.first(where: { $0.type == .pairedVideo }) { chosen.append(paired) }
                }
                var total: Int64 = 0
                var complete = !chosen.isEmpty && (!source[i].mediaSubtypes.contains(.photoLive) || chosen.count >= 2)
                for resource in chosen {
                    if let size = resource.value(forKey: "fileSize") as? Int64, size > 0 { total += size }
                    else { complete = false }
                }
                if total > 0 { photos[i].bytes = total; photos[i].approximate = !complete }
                sizes.entries[photos[i].cacheKey] = ResourceSizeCache.Entry(bytes: photos[i].bytes, approximate: photos[i].approximate)
                lookedUp += 1
                if lookedUp % 2_000 == 0 {
                    try? sizes.save(sizeFile)
                    await onBatch(photos)
                }
            }
            try Task.checkCancellation()
            if lookedUp > 0 || sizes.entries.count != previousCount { try? sizes.save(sizeFile) }
            return photos
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    private func source(_ asset: PhotoAsset) -> PHAsset? { PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil).firstObject }
    func thumbnail(_ asset: PhotoAsset, size: CGSize, network: Bool) async -> UIImage? {
        guard let source = self.source(asset), !Task.isCancelled else { return nil }
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = network
        options.deliveryMode = .highQualityFormat; options.resizeMode = .fast
        let box = ImageRequestBox(), manager = manager
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { c in
                box.bind(c)
                let id = manager.requestImage(for: source, targetSize: size, contentMode: .aspectFit, options: options) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    box.finish(image)
                }
                box.setRequest(id, manager: manager)
            }
        }, onCancel: { box.cancel(manager: manager) })
    }
    func delete(_ assets: [PhotoAsset]) async throws -> Bool {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assets.map(\.id), options: nil)
        guard fetched.count == assets.count else { throw CocoaError(.fileNoSuchFile) }
        return try await withCheckedThrowingContinuation { c in
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.deleteAssets(fetched) }) { success, error in
                if let error {
                    let ns = error as NSError
                    if ns.domain == PHPhotosErrorDomain && ns.code == PHPhotosError.Code.userCancelled.rawValue { c.resume(returning: false) }
                    else { c.resume(throwing: error) }
                } else { c.resume(returning: success) }
            }
        }
    }
    func playerItem(_ asset: PhotoAsset) async -> AVPlayerItem? {
        guard let source = self.source(asset) else { return nil }
        let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { c in
            manager.requestPlayerItem(forVideo: source, options: options) { item, _ in c.resume(returning: item) }
        }
    }
    func livePhoto(_ asset: PhotoAsset) async -> PHLivePhoto? {
        guard let source = self.source(asset) else { return nil }
        let options = PHLivePhotoRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { c in
            manager.requestLivePhoto(for: source, targetSize: CGSize(width: 1200, height: 1600), contentMode: .aspectFit, options: options) { photo, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                c.resume(returning: photo)
            }
        }
    }
    func preheat(_ assets: [PhotoAsset]) {
        let size = CGSize(width: 1200, height: 1600)
        manager.stopCachingImages(for: preheated, targetSize: size, contentMode: .aspectFit, options: nil)
        preheated = assets.compactMap { self.source($0) }
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true
        manager.startCachingImages(for: preheated, targetSize: size, contentMode: .aspectFit, options: options)
    }
    func selectMore(from controller: UIViewController) { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) }
}

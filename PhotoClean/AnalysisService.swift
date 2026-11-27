import Foundation
import UIKit
import Vision
import ImageIO

actor AnalysisService {
    private let directory: URL?
    private var days = AnalysisDays()
    private var throttle = ProgressThrottle()
    init(demo: Bool) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = demo ? nil : base?.appendingPathComponent("PhotoClean/features", isDirectory: true)
    }
    func run(assets: [PhotoAsset], library: any PhotoLibrary, demo: Bool,
             refreshPending: @escaping @MainActor () -> Bool = { false },
             progress: @escaping @MainActor (AnalysisResult) -> Void) async throws -> AnalysisResult {
        let calendar = Calendar.current
        let inputs = AnalysisDay.newestFirst(assets, calendar: calendar)
        days.reconcile(inputs)
        let total = inputs.reduce(0) { $0 + $1.assets.count }
        var state = days.result(total: total)
        var month: String?
        var cache = FeatureMonthFile(url: nil)
        let monthKeys = Dictionary(grouping: assets.filter { !$0.isVideo }) { CalendarKey.month($0.created, calendar: calendar) }
            .mapValues { Set($0.map(\.cacheKey)) }
        if let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "bin" && monthKeys[file.deletingPathExtension().lastPathComponent] == nil {
                try? FileManager.default.removeItem(at: file)
            }
        }
        for day in inputs {
            try Task.checkCancellation()
            let key = String(day.id.prefix(7))
            if key != month {
                month = key
                cache = FeatureMonthFile(url: directory?.appendingPathComponent(key + ".bin"))
                let valid = monthKeys[key] ?? []
                if !cache.keys.isSubset(of: valid) { try cache.rewrite(keeping: valid, adding: [:]) }
            }
            guard days.completed[day.id] == nil else { continue }
            let result = try await analyze(day, cache: &cache, validKeys: monthKeys[key] ?? [], library: library,
                                           demo: demo, calendar: calendar, prior: state, progress: progress)
            days.record(day, result: result)
            state.similar.append(contentsOf: result.similar)
            state.duplicates.append(contentsOf: result.duplicates)
            state.analyzed += result.analyzed
            state.skippedCloud += result.skippedCloud
            state.failed += result.failed
            await publish(state, progress: progress)
            if await refreshPending() { return state }
            await Task.yield()
        }
        try Task.checkCancellation()
        state.complete = true
        if let directory {
            let legacy = directory.deletingLastPathComponent().appendingPathComponent("features-v2.jsonl")
            try? FileManager.default.removeItem(at: legacy)
        }
        let delay = throttle.delay(at: ProcessInfo.processInfo.systemUptime)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        await publish(state, progress: progress)
        return state
    }
    private func publish(_ state: AnalysisResult, progress: @MainActor (AnalysisResult) -> Void) async {
        if throttle.take(at: ProcessInfo.processInfo.systemUptime) { await progress(state) }
    }
    private func analyze(_ day: AnalysisDay, cache: inout FeatureMonthFile, validKeys: Set<String>,
                         library: any PhotoLibrary, demo: Bool, calendar: Calendar, prior: AnalysisResult,
                         progress: @escaping @MainActor (AnalysisResult) -> Void) async throws -> AnalysisResult {
        var photos = day.assets
        var prints: [String: FeatureEntry] = [:]
        var additions: [String: FeatureEntry] = [:]
        var checkpoint = ProcessInfo.processInfo.systemUptime
        var result = AnalysisResult(total: photos.count)
        do {
            for i in photos.indices {
                try Task.checkCancellation()
                let asset = photos[i]
                if demo { /* Demo distances need no image feature vectors. */ }
                else if let entry = cache.entry(for: asset.cacheKey) {
                    prints[asset.id] = entry; photos[i].sharpness = entry.sharpness
                } else if let image = await library.thumbnail(asset, size: CGSize(width: 256, height: 256), network: false), let cg = image.cgImage {
                    try Task.checkCancellation()
                    let entry = autoreleasepool { Self.feature(cg, orientation: image.imageOrientation) }
                    if let entry {
                        prints[asset.id] = entry; additions[asset.cacheKey] = entry; photos[i].sharpness = entry.sharpness
                    } else { result.failed += 1 }
                } else { result.skippedCloud += 1 }
                result.analyzed = i + 1
                if (i + 1) % 32 == 0 {
                    if !additions.isEmpty && ProcessInfo.processInfo.systemUptime - checkpoint >= 30 {
                        try cache.rewrite(keeping: validKeys, adding: additions)
                        additions.removeAll()
                        checkpoint = ProcessInfo.processInfo.systemUptime
                    }
                    var partial = prior
                    partial.analyzed += result.analyzed; partial.failed += result.failed; partial.skippedCloud += result.skippedCloud
                    await publish(partial, progress: progress)
                    await Task.yield()
                }
            }
            if !additions.isEmpty { try cache.rewrite(keeping: validKeys, adding: additions) }
            try Task.checkCancellation()
            let groups = AnalysisCore.classify(photos, calendar: calendar) { a, b in
                if demo { return DemoLibrary.distance(a, b) }
                guard !Task.isCancelled, let x = prints[a.id], let y = prints[b.id] else { return nil }
                return FeatureVector.distance(x.vector, y.vector)
            }
            try Task.checkCancellation()
            result.similar = groups.similar; result.duplicates = groups.duplicates; result.complete = true
            return result
        } catch {
            if !additions.isEmpty { try? cache.rewrite(keeping: validKeys, adding: additions) }
            throw error
        }
    }
    private static func feature(_ image: CGImage, orientation: UIImage.Orientation) -> FeatureEntry? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        do {
            try VNImageRequestHandler(cgImage: image, orientation: Self.orientation(orientation), options: [:]).perform([request])
            guard let observation = request.results?.first else { return nil }
            let type: FeatureVector.Element
            switch observation.elementType {
            case .float: type = .float
            case .double: type = .double
            default: return nil
            }
            guard let vector = FeatureVector.read(observation.data, count: observation.elementCount, element: type) else { return nil }
            return FeatureEntry(vector: vector, sharpness: sharpness(image))
        } catch { return nil }
    }
    private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    private static func sharpness(_ image: CGImage) -> Double {
        let side = 40
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))); return true
        }
        guard drawn else { return 0 }
        var sum = 0.0, squares = 0.0, count = 0.0
        for y in 1..<(side - 1) { for x in 1..<(side - 1) {
            let i = y * side + x
            let value = Double(Int(pixels[i-1]) + Int(pixels[i+1]) + Int(pixels[i-side]) + Int(pixels[i+side]) - 4 * Int(pixels[i]))
            sum += value; squares += value * value; count += 1
        } }
        return max(0, squares / count - pow(sum / count, 2))
    }
}

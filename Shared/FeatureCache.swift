import Foundation

struct FeatureEntry: Equatable, Sendable {
    let vector: [Float]
    let sharpness: Double
}

enum FeatureVector {
    enum Element: Equatable { case float, double }
    static func read(_ data: Data, count: Int, element: Element) -> [Float]? {
        let stride = element == .float ? MemoryLayout<Float>.size : MemoryLayout<Double>.size
        guard count > 0, count <= 65_536, data.count == count * stride else { return nil }
        var values = [Float](); values.reserveCapacity(count)
        for offset in Swift.stride(from: 0, to: data.count, by: stride) {
            let value: Float
            if element == .float {
                var number: Float = 0
                _ = withUnsafeMutableBytes(of: &number) { data.copyBytes(to: $0, from: offset..<(offset + stride)) }
                value = number
            } else {
                var number: Double = 0
                _ = withUnsafeMutableBytes(of: &number) { data.copyBytes(to: $0, from: offset..<(offset + stride)) }
                value = Float(number)
            }
            guard value.isFinite else { return nil }
            values.append(value)
        }
        return values
    }
    static func distance(_ a: [Float], _ b: [Float]) -> Float? {
        guard !a.isEmpty, a.count == b.count else { return nil }
        var sum = 0.0
        for i in a.indices {
            let delta = Double(a[i]) - Double(b[i])
            sum += delta * delta
        }
        let value = Float(sum.squareRoot())
        return value.isFinite ? value : nil
    }
}

private struct BinaryReader {
    let data: Data
    var offset = 0
    mutating func integer<T: FixedWidthInteger>(_ type: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard size <= data.count - offset else { return nil }
        var value: T = 0
        for i in 0..<size { value |= T(data[offset + i]) << (i * 8) }
        offset += size
        return value
    }
    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, count <= data.count - offset else { return nil }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

enum FeatureCacheCodec {
    private static let magic = Data("PCF3REV2".utf8)
    static func header(count: Int) -> Data {
        var data = magic
        data.appendInteger(UInt32(count))
        return data
    }
    private static func checksum(_ data: Data, range: Range<Int>) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data[range] { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        return value
    }
    static func record(key: String, entry: FeatureEntry) -> Data {
        let keyData = Data(key.utf8)
        var data = Data()
        data.appendInteger(UInt32(keyData.count)); data.append(keyData)
        data.appendInteger(UInt32(entry.vector.count)); data.appendInteger(entry.sharpness.bitPattern)
        for value in entry.vector { data.appendInteger(value.bitPattern) }
        data.appendInteger(checksum(data, range: 0..<data.count))
        return data
    }
    static func index(_ data: Data) -> [String: Range<Int>]? {
        var reader = BinaryReader(data: data)
        guard reader.bytes(magic.count) == magic, let count = reader.integer(UInt32.self),
              count <= 1_000_000, Int(count) <= max(0, (data.count - 12) / 29) else { return nil }
        var index: [String: Range<Int>] = [:]
        for _ in 0..<Int(count) {
            let start = reader.offset
            guard let keyCount = reader.integer(UInt32.self), keyCount > 0, keyCount <= 65_536,
                  let keyData = reader.bytes(Int(keyCount)), let key = String(data: keyData, encoding: .utf8),
                  index[key] == nil, let elements = reader.integer(UInt32.self), elements > 0, elements <= 65_536,
                  let sharpness = reader.integer(UInt64.self), Double(bitPattern: sharpness).isFinite,
                  Int(elements) * 4 <= data.count - reader.offset else { return nil }
            reader.offset += Int(elements) * 4
            let end = reader.offset
            guard let expected = reader.integer(UInt64.self), checksum(data, range: start..<end) == expected else { return nil }
            index[key] = start..<reader.offset
        }
        return reader.offset == data.count ? index : nil
    }
    static func entry(_ record: Data) -> FeatureEntry? {
        var reader = BinaryReader(data: record)
        guard let keyCount = reader.integer(UInt32.self), reader.bytes(Int(keyCount)) != nil,
              let count = reader.integer(UInt32.self), count > 0, count <= 65_536,
              let bits = reader.integer(UInt64.self) else { return nil }
        var vector: [Float] = []; vector.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let bits = reader.integer(UInt32.self) else { return nil }
            let value = Float(bitPattern: bits)
            guard value.isFinite else { return nil }
            vector.append(value)
        }
        return FeatureEntry(vector: vector, sharpness: Double(bitPattern: bits))
    }
    static func encode(_ entries: [String: FeatureEntry]) -> Data {
        var data = header(count: entries.count)
        for key in entries.keys.sorted() {
            if let entry = entries[key] { data.append(record(key: key, entry: entry)) }
        }
        return data
    }
    static func decode(_ data: Data) -> [String: FeatureEntry]? {
        guard let index = index(data) else { return nil }
        var entries: [String: FeatureEntry] = [:]
        for (key, range) in index {
            guard let entry = entry(data.subdata(in: range)) else { return nil }
            entries[key] = entry
        }
        return entries
    }
}

struct FeatureMonthFile {
    let url: URL?
    private var handle: FileHandle?
    private var index: [String: Range<Int>] = [:]
    init(url: URL?) {
        self.url = url
        guard let url, let source = try? FileHandle(forReadingFrom: url) else { return }
        if let records = try? Self.readIndex(source) {
            handle = source; index = records
        } else { try? source.close() }
    }
    private static func readIndex(_ source: FileHandle) throws -> [String: Range<Int>] {
        let length = try source.seekToEnd()
        try source.seek(toOffset: 0)
        guard let header = try source.read(upToCount: 12), header.count == 12 else { throw CocoaError(.fileReadCorruptFile) }
        var reader = BinaryReader(data: header)
        guard reader.bytes(8) == Data("PCF3REV2".utf8), let count = reader.integer(UInt32.self), count <= 1_000_000,
              length >= 12, UInt64(count) <= (length - 12) / 29 else { throw CocoaError(.fileReadCorruptFile) }
        var result: [String: Range<Int>] = [:]
        var offset = 12
        for _ in 0..<Int(count) {
            guard var record = try source.read(upToCount: 4), record.count == 4 else { throw CocoaError(.fileReadCorruptFile) }
            var keyReader = BinaryReader(data: record)
            guard let keyCount = keyReader.integer(UInt32.self), keyCount > 0, keyCount <= 65_536,
                  let key = try source.read(upToCount: Int(keyCount)), key.count == Int(keyCount),
                  let metadata = try source.read(upToCount: 12), metadata.count == 12 else { throw CocoaError(.fileReadCorruptFile) }
            var metadataReader = BinaryReader(data: metadata)
            guard let elements = metadataReader.integer(UInt32.self), elements > 0, elements <= 65_536,
                  let vector = try source.read(upToCount: Int(elements) * 4 + 8), vector.count == Int(elements) * 4 + 8 else { throw CocoaError(.fileReadCorruptFile) }
            record.append(key); record.append(metadata); record.append(vector)
            var single = FeatureCacheCodec.header(count: 1); single.append(record)
            guard let indexed = FeatureCacheCodec.index(single), let key = indexed.keys.first, result[key] == nil else { throw CocoaError(.fileReadCorruptFile) }
            result[key] = offset..<(offset + record.count)
            offset += record.count
        }
        guard UInt64(offset) == length else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    var keys: Set<String> { Set(index.keys) }
    private func record(for key: String) throws -> Data {
        guard let range = index[key], let handle else { throw CocoaError(.fileReadCorruptFile) }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        guard let bytes = try handle.read(upToCount: range.count), bytes.count == range.count else { throw CocoaError(.fileReadCorruptFile) }
        return bytes
    }
    func entry(for key: String) -> FeatureEntry? {
        guard let record = try? record(for: key) else { return nil }
        return FeatureCacheCodec.entry(record)
    }
    mutating func rewrite(keeping valid: Set<String>, adding entries: [String: FeatureEntry]) throws {
        guard let url else { return }
        let keys = Set(index.keys).union(entries.keys).intersection(valid)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FeatureCacheCodec.header(count: keys.count).write(to: temporary, options: .completeFileProtectionUntilFirstUserAuthentication)
        let handle = try FileHandle(forWritingTo: temporary)
        var nextIndex: [String: Range<Int>] = [:]
        var offset = 12
        do {
            try handle.seekToEnd()
            for key in keys.sorted() {
                let record: Data
                if let entry = entries[key] { record = FeatureCacheCodec.record(key: key, entry: entry) }
                else { record = try self.record(for: key) }
                try handle.write(contentsOf: record)
                nextIndex[key] = offset..<(offset + record.count); offset += record.count
            }
            try handle.synchronize(); try handle.close()
        } catch { try? handle.close(); throw error }
        if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: url) }
        self.handle = try FileHandle(forReadingFrom: url)
        index = nextIndex
    }
}

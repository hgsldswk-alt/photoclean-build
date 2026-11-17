import Foundation

struct StorageUsage {
    let used: Double
    let reclaimable: Double
    let free: Double
    init(total: Int64, free: Int64, reclaimable: Int64) {
        guard total > 0 else { used = 0; self.reclaimable = 0; self.free = 1; return }
        let capacity = Double(total)
        let available = min(capacity, max(0, Double(free)))
        let occupied = capacity - available
        let recoverable = min(occupied, max(0, Double(reclaimable)))
        used = (occupied - recoverable) / capacity
        self.reclaimable = recoverable / capacity
        self.free = available / capacity
    }
}

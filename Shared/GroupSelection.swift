import Foundation

struct GroupSelection {
    var selected: Set<String> = []
    private var seen: Set<String> = []
    mutating func update(_ groups: [PhotoGroup]) {
        let valid = Set(groups.flatMap { $0.assets.map(\.id) })
        selected.formUnion(Set(groups.flatMap { $0.selectedIDs }).subtracting(seen))
        selected.formIntersection(valid)
        seen.formUnion(valid)
    }
    mutating func keepAll(_ group: PhotoGroup) {
        let ids = Set(group.assets.map(\.id))
        selected.subtract(ids); seen.formUnion(ids)
    }
}

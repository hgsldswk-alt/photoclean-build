import Foundation

struct SwipeSession {
    struct Step {
        let index: Int
        let basket: Bool
    }
    private(set) var photos: [PhotoAsset] = []
    private(set) var index = 0
    private(set) var initialReviewed = 0
    private(set) var history: [Step] = []
    private(set) var loaded = false
    var current: PhotoAsset? { photos.indices.contains(index) ? photos[index] : nil }
    func loading(fetching: Bool) -> Bool { !loaded || (current == nil && fetching) }
    mutating func sync(_ all: [PhotoAsset], reviewed: Set<String>, fetching: Bool) {
        guard !all.isEmpty || !fetching else { return }
        if !loaded {
            loaded = true
            initialReviewed = all.filter { reviewed.contains($0.id) }.count
            photos = all.filter { !reviewed.contains($0.id) }
            return
        }
        let latest = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let completed = photos.prefix(index).compactMap { latest[$0.id] }
        if completed.count != index { history = [] }
        index = completed.count
        let known = Set(completed.map(\.id))
        photos = completed + all.filter { !reviewed.contains($0.id) && !known.contains($0.id) }
        initialReviewed = all.filter { reviewed.contains($0.id) && !known.contains($0.id) }.count
    }
    mutating func advance(_ id: String, wasBasket: Bool) -> Bool {
        guard current?.id == id else { return false }
        history.append(Step(index: index, basket: wasBasket)); index += 1
        return true
    }
    mutating func undo() -> (photo: PhotoAsset, basket: Bool)? {
        guard let step = history.popLast(), photos.indices.contains(step.index) else { return nil }
        index = step.index
        return (photos[index], step.basket)
    }
}

import Foundation

@MainActor final class RefreshDebouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?
    init(delay: Duration = .seconds(2)) { self.delay = delay }
    deinit { task?.cancel() }
    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        let delay = delay
        task = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

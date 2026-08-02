import Foundation

/// Coalesces repeated calls into a single action after a quiet period.
/// Main-actor bound; the action always runs on the main actor.
@MainActor
final class Debouncer {
    private let delay: TimeInterval
    private let action: () async -> Void
    private var task: Task<Void, Never>?

    init(delay: TimeInterval, action: @escaping () async -> Void) {
        self.delay = delay
        self.action = action
    }

    func schedule() {
        task?.cancel()
        task = Task { [delay, weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Runs the action immediately, cancelling any pending run.
    func fireNow() async {
        task?.cancel()
        task = nil
        await action()
    }
}

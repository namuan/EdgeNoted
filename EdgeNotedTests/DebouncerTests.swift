import Testing

@testable import EdgeNoted

@Suite("Debouncer")
@MainActor
struct DebouncerTests {
    @Test("Coalesces multiple schedules into one action")
    func coalesces() async throws {
        let counter = Counter()
        let debouncer = Debouncer(delay: 0.05) {
            await counter.increment()
        }
        debouncer.schedule()
        debouncer.schedule()
        debouncer.schedule()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await counter.value == 1)
    }

    @Test("Cancelling prevents the action from running")
    func cancel() async throws {
        let counter = Counter()
        let debouncer = Debouncer(delay: 0.05) {
            await counter.increment()
        }
        debouncer.schedule()
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await counter.value == 0)
    }

    @Test("Fire-now runs the action immediately")
    func fireNow() async throws {
        let counter = Counter()
        let debouncer = Debouncer(delay: 10) {
            await counter.increment()
        }
        debouncer.schedule()
        await debouncer.fireNow()
        #expect(await counter.value == 1)
    }
}

/// A tiny sendable counter usable across the test's actor boundaries.
private actor Counter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int { count }
}

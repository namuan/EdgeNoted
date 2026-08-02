import Foundation
import Testing

@testable import EdgeNoted

@Suite("AppleScript executor")
struct AppleScriptExecutorTests {
    @Test("Unknown commands return without contacting Notes or Reminders")
    func unknownCommand() async throws {
        let output = try await AppleScriptExecutor.shared.run(command: "bogus")
        #expect(output == "ERR:unknown-cmd")
    }

    @Test("Executing many commands in sequence is stable and does not crash")
    func repeatedRuns() async throws {
        for _ in 0..<5 {
            let output = try await AppleScriptExecutor.shared.run(command: "bogus")
            #expect(output == "ERR:unknown-cmd")
        }
    }

    @Test("A timeout path is bounded and does not crash")
    func timeoutPath() async throws {
        // The "note" command targets Apple Notes, but the executor is invoked
        // with a sub-second timeout so it can never reach a running app. This
        // exercises the terminate-and-reap path that previously crashed with
        // `-[NSConcreteTask dealloc]` (SIGABRT).
        let started = Date()
        do {
            _ = try await AppleScriptExecutor.shared.run(command: "note", arguments: ["bogus-id"], timeout: 0.2)
            Issue.record("Expected a timeout error")
        } catch {
            #expect(error is ScriptError)
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 10)
    }
}

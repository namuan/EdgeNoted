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

    @Test("Notes commands remain and Reminders commands were removed")
    func reminderCommandsRemoved() {
        let script = AppleScriptExecutor.script

        #expect(script.contains("else if cmd is \"notes\""))
        #expect(script.contains("else if cmd is \"note\""))
        #expect(!script.contains("command=reminders"))
        #expect(!script.contains("cmd is \"lists\""))
        #expect(!script.contains("cmd is \"reminders\""))
        #expect(!script.contains("cmd is \"reminder-create\""))
        #expect(!script.contains("cmd is \"reminder-update\""))
        #expect(!script.contains("cmd is \"reminder-delete\""))
    }
}

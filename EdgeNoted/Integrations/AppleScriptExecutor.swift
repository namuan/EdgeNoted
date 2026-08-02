import Foundation

/// Errors surfaced by the AppleScript bridge.
enum ScriptError: LocalizedError, Equatable {
    case timedOut
    case permissionDenied
    case appNotRunning(String)
    case executionFailed(String)
    case malformedOutput(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return
                "Timed out talking to Apple Notes or Reminders. If this is the first launch, approve EdgeNoted in System Settings > Privacy & Security > Automation and try again."
        case .permissionDenied:
            return
                "EdgeNoted is not allowed to control Apple Notes or Reminders. Grant access in System Settings > Privacy & Security > Automation, then try again."
        case .appNotRunning(let message):
            return "Apple Notes or Reminders is unavailable: \(message)"
        case .executionFailed(let message):
            return "AppleScript error: \(message)"
        case .malformedOutput(let message):
            return "Unexpected response from AppleScript: \(message)"
        }
    }
}

/// Runs the fixed AppleScript bridge through `/usr/bin/osascript`.
///
/// The script itself is a constant string; every piece of user data is passed
/// as a positional argument (argv), so note text is never interpolated into
/// AppleScript source. Structured results are returned as JSON on stdout.
actor AppleScriptExecutor {
    /// Wraps non-Sendable Process/Pipe values so they can cross into
    /// @Sendable task-group closures. The values are only touched on the
    /// single serial path inside `run`.
    private final class Box<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    static let shared = AppleScriptExecutor()

    /// The full bridge script. It dispatches on its first argument and returns
    /// JSON via NSJSONSerialization (Foundation is imported as a framework).
    static let script: String = """
        use framework "Foundation"

        on jsonFromObject(theObject)
            set jsonData to current application's NSJSONSerialization's dataWithJSONObject:theObject options:0 |error|:(missing value)
            if jsonData is missing value then return "{}"
            set theString to current application's NSString's alloc's initWithData:jsonData encoding:(current application's NSUTF8StringEncoding)
            return theString as text
        end jsonFromObject

        on run argv
            if (count of argv) is 0 then
                return "ERR:noargs"
            end if
            set cmd to item 1 of argv
            if cmd is "folders" then
                tell application "Notes"
                    set outList to {}
                    repeat with f in folders
                        try
                            set end of outList to {idStr:(id of f), nameStr:(name of f)}
                        end try
                    end repeat
                    return my jsonFromObject(outList)
                end tell
            else if cmd is "notes" then
                set folderKey to item 2 of argv
                tell application "Notes"
                    set outList to {}
                    try
                        if folderKey is "ALL" then
                            set theNotes to every note
                        else
                            set theNotes to every note of folder folderKey
                        end if
                        repeat with n in theNotes
                            try
                                set end of outList to {idStr:(id of n), nameStr:(name of n)}
                            end try
                        end repeat
                    end try
                    return my jsonFromObject(outList)
                end tell
            else if cmd is "note" then
                set noteID to item 2 of argv
                tell application "Notes"
                    try
                        set theNote to first note whose id is noteID
                        set theBody to body of theNote
                        set theName to name of theNote
                        set theMod to modification date of theNote
                        set epoch to theMod's timeIntervalSince1970() as real
                        return my jsonFromObject({idStr:noteID, nameStr:theName, bodyStr:theBody, modEpoch:epoch})
                    on error errMsg
                        return my jsonFromObject({errorStr:errMsg})
                    end try
                end tell
            else if cmd is "search" then
                set query to item 2 of argv
                tell application "Notes"
                    set outList to {}
                    try
                        set theNotes to every note whose name contains query
                        repeat with n in theNotes
                            try
                                set end of outList to {idStr:(id of n), nameStr:(name of n)}
                            end try
                        end repeat
                    end try
                    return my jsonFromObject(outList)
                end tell
            else if cmd is "create" then
                set folderKey to item 2 of argv
                set theName to item 3 of argv
                set theBody to item 4 of argv
                tell application "Notes"
                    try
                        if folderKey is "ALL" then
                            set theNote to make new note at end of notes with properties {name:theName, body:theBody}
                        else
                            set theNote to make new note at folder folderKey with properties {name:theName, body:theBody}
                        end if
                        return my jsonFromObject({idStr:(id of theNote), nameStr:theName})
                    on error errMsg
                        return my jsonFromObject({errorStr:errMsg})
                    end try
                end tell
            else if cmd is "update" then
                set noteID to item 2 of argv
                set theName to item 3 of argv
                set theBody to item 4 of argv
                tell application "Notes"
                    try
                        set theNote to first note whose id is noteID
                        set name of theNote to theName
                        set body of theNote to theBody
                        return "OK"
                    on error errMsg
                        return "ERR:" & errMsg
                    end try
                end tell
            else if cmd is "lists" then
                tell application "Reminders"
                    set outList to {}
                    repeat with l in lists
                        try
                            set end of outList to {idStr:(id of l), nameStr:(name of l)}
                        end try
                    end repeat
                    return my jsonFromObject(outList)
                end tell
            else if cmd is "reminders" then
                set listName to item 2 of argv
                tell application "Reminders"
                    set outList to {}
                    try
                        repeat with r in (every reminder of list listName)
                            set dueStr to ""
                            set priStr to ""
                            try
                                set d to due date of r
                                set dueStr to ((d's timeIntervalSince1970()) as real) as text
                            end try
                            try
                                set priStr to (priority of r) as text
                            end try
                            set end of outList to {idStr:(id of r), nameStr:(name of r), doneStr:((completed of r) as text), dueStr:dueStr, priStr:priStr}
                        end repeat
                    end try
                    return my jsonFromObject(outList)
                end tell
            else if cmd is "reminder-create" then
                set listName to item 2 of argv
                set theName to item 3 of argv
                tell application "Reminders"
                    try
                        set theList to first list whose name is listName
                        set theNew to make new reminder at end of theList with properties {name:theName}
                        return my jsonFromObject({idStr:(id of theNew), nameStr:theName})
                    on error errMsg
                        return my jsonFromObject({errorStr:errMsg})
                    end try
                end tell
            else if cmd is "reminder-update" then
                set remID to item 2 of argv
                set theName to item 3 of argv
                set doneFlag to item 4 of argv
                set dueEpoch to item 5 of argv
                set priLevel to item 6 of argv
                tell application "Reminders"
                    try
                        set theR to first reminder whose id is remID
                        if theName is not "" then set name of theR to theName
                        if doneFlag is not "" then set completed of theR to (doneFlag is "1")
                    if priLevel is not "" then set priority of theR to (priLevel as integer)
                    if dueEpoch is "clear" then
                        set due date of theR to missing value
                    else if dueEpoch is not "" then
                        set dueDate to current application's NSDate's dateWithTimeIntervalSince1970:(dueEpoch as real)
                        set due date of theR to dueDate
                    end if
                        return "OK"
                    on error errMsg
                        return "ERR:" & errMsg
                    end try
                end tell
            else if cmd is "reminder-delete" then
                set remID to item 2 of argv
                tell application "Reminders"
                    try
                        set theR to first reminder whose id is remID
                        delete theR
                        return "OK"
                    on error errMsg
                        return "ERR:" & errMsg
                    end try
                end tell
            end if
            return "ERR:unknown-cmd"
        end run
        """

    /// Runs one bridge command with arguments and returns the trimmed stdout.
    func run(command: String, arguments: [String] = [], timeout: TimeInterval = 25) async throws -> String {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.script, command] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let unsafeProcess = Box(process)
        let unsafeStdout = Box(stdout)
        let unsafeStderr = Box(stderr)

        var collected: (output: Data, error: Data)?
        var collectedError: Error?

        do {
            collected = try await withThrowingTaskGroup(of: (Data, Data).self) { group in
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    unsafeProcess.value.terminate()
                    throw ScriptError.timedOut
                }
                group.addTask {
                    async let out = unsafeStdout.value.fileHandleForReading.readToEnd()
                    async let err = unsafeStderr.value.fileHandleForReading.readToEnd()
                    let outputData = try await out ?? Data()
                    let errorData = try await err ?? Data()
                    return (outputData, errorData)
                }
                guard let first = try await group.next() else {
                    throw ScriptError.executionFailed("No response from osascript")
                }
                group.cancelAll()
                return first
            }
        } catch {
            collectedError = error
        }

        // Critical: reap the task before the Process can be deallocated.
        // Deallocating an NSConcreteTask that is still considered running
        // raises an NSInternalInconsistencyException and aborts the app
        // (previously triggered by the 25s timeout path). The pipes above are
        // drained, so this returns promptly once the process exits, or shortly
        // after terminate() takes effect on the timeout path.
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        if let collectedError {
            await Log.event(
                level: .error,
                category: .bridge,
                message: "AppleScript command failed",
                metadata: [
                    "command": command,
                    "args": String(arguments.count),
                    "elapsedMs": String(elapsedMs),
                    "error": Self.errorKind(collectedError),
                ]
            )
            throw collectedError
        }

        if let collected {
            if process.terminationStatus != 0 {
                let message = String(bytes: collected.error, encoding: .utf8) ?? ""
                let classified = Self.classifyError(message)
                await Log.event(
                    level: .error,
                    category: .bridge,
                    message: "AppleScript command error",
                    metadata: [
                        "command": command,
                        "args": String(arguments.count),
                        "elapsedMs": String(elapsedMs),
                        "status": String(process.terminationStatus),
                        "outputBytes": String(collected.output.count),
                        "errorBytes": String(collected.error.count),
                        "error": Self.errorKind(classified),
                    ]
                )
                throw classified
            }
            let text = String(bytes: collected.output, encoding: .utf8) ?? ""
            await Log.event(
                level: .debug,
                category: .bridge,
                message: "AppleScript command ok",
                metadata: [
                    "command": command,
                    "args": String(arguments.count),
                    "elapsedMs": String(elapsedMs),
                    "status": String(process.terminationStatus),
                    "outputBytes": String(collected.output.count),
                    "errorBytes": String(collected.error.count),
                ]
            )
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let failure = ScriptError.executionFailed("No output from osascript")
        await Log.event(
            level: .error,
            category: .bridge,
            message: "AppleScript command produced no output",
            metadata: [
                "command": command,
                "elapsedMs": String(elapsedMs),
            ]
        )
        throw failure
    }

    private static func errorKind(_ error: Error) -> String {
        if let scriptError = error as? ScriptError {
            switch scriptError {
            case .timedOut: return "timedOut"
            case .permissionDenied: return "permissionDenied"
            case .appNotRunning: return "appNotRunning"
            case .executionFailed: return "executionFailed"
            case .malformedOutput: return "malformedOutput"
            }
        }
        return "unknown"
    }

    private static func classifyError(_ message: String) -> ScriptError {
        if message.contains("-1743") || message.lowercased().contains("not authorized") {
            return .permissionDenied
        }
        if message.lowercased().contains("isn't running") || message.lowercased().contains("not running") {
            return .appNotRunning(message)
        }
        return .executionFailed(message)
    }
}

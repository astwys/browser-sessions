import Darwin
import Foundation
import BrowserSessionsCore

@MainActor
func runProcessTableTests(_ harness: inout TestHarness) async {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    process.environment = ["BROWSER_SESSIONS_TEST_SECRET": "hunter2"]
    do {
        try process.run()
    } catch {
        harness.expect(false, "spawn sleep for process table test")
        return
    }
    defer {
        process.terminate()
        process.waitUntilExit()
    }
    let pid = process.processIdentifier

    let record = ProcessTable.record(pid: pid)
    harness.expectEqual(record?.executablePath, "/bin/sleep", "process table reads executable path")
    harness.expectEqual(record?.commandLine, "/bin/sleep 30", "process table reads argv without the environment")
    harness.expectEqual(record?.parentPID, getpid(), "process table reads parent PID")
    harness.expect(record.map { abs($0.startTime.timeIntervalSinceNow) < 5 } == true, "process table reads start time")
    harness.expect(ProcessTable.all().contains { $0.pid == pid }, "full table includes the spawned process")
    harness.expectEqual(ProcessTable.record(pid: 1), nil, "other users' processes are not read")
}

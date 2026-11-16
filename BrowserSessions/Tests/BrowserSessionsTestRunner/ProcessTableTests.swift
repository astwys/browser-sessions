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

    // KERN_PROCARGS2 layout: argc, exec path, NUL padding, argv, environment.
    func procArgs(argc: Int32, _ strings: String) -> [String] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array("/usr/local/bin/node\0\0\0".utf8) + Array(strings.utf8)
        return bytes.withUnsafeBytes { ProcessTable.arguments(procArgs: $0) }
    }
    harness.expectEqual(
        procArgs(argc: 3, "node\0server.js\0--port=3000\0SECRET=hunter2\0"),
        ["node", "server.js", "--port=3000"],
        "argv parsing stops at argc"
    )
    // A rewritten title covers the old argv; argc still says 3, so the next strings are the environment.
    harness.expectEqual(
        procArgs(argc: 3, "my-worker title that is as long as the old argv\0SECRET=hunter2\0PATH=/usr/bin\0"),
        ["my-worker title that is as long as the old argv"],
        "argv parsing never reads the environment behind a rewritten title"
    )
}

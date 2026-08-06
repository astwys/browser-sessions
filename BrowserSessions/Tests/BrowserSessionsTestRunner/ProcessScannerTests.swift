import Foundation
import BrowserSessionsCore

@MainActor
func runProcessScannerTests(_ harness: inout TestHarness) async {
    await testScannerClassifiesPSOutput(&harness)
}

@MainActor
private func testScannerClassifiesPSOutput(_ harness: inout TestHarness) async {
    final class Capture: @unchecked Sendable {
        var executable = ""
        var arguments: [String] = []
    }
    let capture = Capture()
    let runner = MockCommandRunner { executable, arguments in
        capture.executable = executable
        capture.arguments = arguments
        return CommandResult(exitCode: 0, stdout: CmdlineFixtures.psOutput, stderr: "", timedOut: false)
    }
    let scanner = ProcessScanner(commandRunner: runner)
    let entries = await scanner.scan()
    harness.expectEqual(capture.executable, "ps", "scanner executable")
    harness.expectEqual(capture.arguments, ["-axo", "pid=,ppid=,lstart=,command=", "-ww"], "scanner ps arguments")
    harness.expectEqual(entries.count, 1, "scanner excludes crashpad")
    harness.expectEqual(entries.first?.confidence, .low, "scanner classifies remote debugging port as low")
    harness.expectEqual(entries.first?.processIdentity?.pid, 101, "scanner populates identity pid")
    harness.expect(entries.first?.id.isEmpty == false, "scanner creates stable id")
}

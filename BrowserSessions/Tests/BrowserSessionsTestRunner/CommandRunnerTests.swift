import Foundation
import BrowserSessionsCore

@MainActor
func runCommandRunnerTests(_ harness: inout TestHarness) async {
    await testReturnsWhileBackgroundChildHoldsPipes(&harness)
    await testKillsCommandThatIgnoresSIGTERM(&harness)
    await testLargeOutputArrivesInOrder(&harness)
    await testMissingExecutableExits127(&harness)
}

@MainActor
private func testReturnsWhileBackgroundChildHoldsPipes(_ harness: inout TestHarness) async {
    let clock = ContinuousClock()
    var result: CommandResult?
    let elapsed = await clock.measure {
        result = await CommandRunner().run(executable: "sh", arguments: ["-c", "(sleep 3) & echo hi"], timeout: .seconds(2))
    }
    harness.expect(elapsed < .seconds(1), "background child holding stdout does not block (took \(elapsed))")
    harness.expectEqual(result?.stdout, "hi\n", "output written before exit is captured")
    harness.expectEqual(result?.timedOut, false, "exited command is not a timeout")
}

@MainActor
private func testKillsCommandThatIgnoresSIGTERM(_ harness: inout TestHarness) async {
    let clock = ContinuousClock()
    var result: CommandResult?
    let elapsed = await clock.measure {
        result = await CommandRunner().run(executable: "sh", arguments: ["-c", "trap '' TERM; sleep 3"], timeout: .milliseconds(300))
    }
    harness.expect(elapsed < .seconds(2), "SIGTERM-ignoring command is killed (took \(elapsed))")
    harness.expectEqual(result?.timedOut, true, "killed command reports timeout")
}

@MainActor
private func testLargeOutputArrivesInOrder(_ harness: inout TestHarness) async {
    let result = await CommandRunner().run(executable: "seq", arguments: ["1", "100000"], timeout: .seconds(5))
    let expected = (1...100_000).map(String.init).joined(separator: "\n") + "\n"
    harness.expect(result.stdout == expected, "output larger than the pipe buffer arrives complete and in order")
}

@MainActor
private func testMissingExecutableExits127(_ harness: inout TestHarness) async {
    let result = await CommandRunner().run(executable: "browser-sessions-no-such-command", arguments: [], timeout: .seconds(2))
    harness.expectEqual(result.exitCode, 127, "missing executable exits 127")
}

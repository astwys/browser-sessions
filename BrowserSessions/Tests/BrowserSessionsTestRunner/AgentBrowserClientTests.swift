import Foundation
import BrowserSessionsCore

@MainActor
func runAgentBrowserClientTests(_ harness: inout TestHarness) async {
    await testListSessionsParsesTwoEntries(&harness)
    await testMalformedJSONReturnsError(&harness)
    await testUnavailableWhenNotOnPath(&harness)
    await testTimeoutReturnsUnavailable(&harness)
    await testUnavailableSanitizesStderr(&harness)
    await testCloseSuccess(&harness)
    await testCloseErrorSanitizesMessage(&harness)
    await testCloseUsesGlobalSessionFlagOrder(&harness)
    await testStableSessionIDs(&harness)
    await runAgentBrowserIntegrationTestsIfEnabled(&harness)
}

@MainActor
private func testListSessionsParsesTwoEntries(_ harness: inout TestHarness) async {
    final class Capture: @unchecked Sendable {
        var executable = ""
        var arguments: [String] = []
    }
    let capture = Capture()
    let runner = MockCommandRunner { executable, arguments in
        capture.executable = executable
        capture.arguments = arguments
        return CommandResult(exitCode: 0, stdout: AgentBrowserJSONFixtures.listTwoSessions, stderr: "", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.listSessions()
    harness.expectEqual(capture.executable, "agent-browser", "list executable")
    harness.expectEqual(capture.arguments, ["session", "list", "--json"], "list argv")
    guard case .available(let entries) = result else {
        harness.expect(false, "expected available list result")
        return
    }
    harness.expectEqual(entries.count, 2, "entry count")
    harness.expectEqual(entries.map(\.sessionName), ["alpha", "beta"], "session names")
}

@MainActor
private func testMalformedJSONReturnsError(_ harness: inout TestHarness) async {
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 0, stdout: AgentBrowserJSONFixtures.malformed, stderr: "", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.listSessions()
    guard case .error(let message) = result else {
        harness.expect(false, "expected parse error")
        return
    }
    harness.expectEqual(message, "invalid session list JSON", "malformed json message")
}

@MainActor
private func testUnavailableWhenNotOnPath(_ harness: inout TestHarness) async {
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 127, stdout: "", stderr: "env: agent-browser: No such file or directory", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.listSessions()
    guard case .unavailable(let reason) = result else {
        harness.expect(false, "expected unavailable")
        return
    }
    harness.expectEqual(reason, "agent-browser not found on PATH", "missing cli reason")
}

@MainActor
private func testTimeoutReturnsUnavailable(_ harness: inout TestHarness) async {
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: -1, stdout: "", stderr: "command timed out", timedOut: true)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.listSessions()
    guard case .unavailable(let reason) = result else {
        harness.expect(false, "expected timeout unavailable")
        return
    }
    harness.expectEqual(reason, "agent-browser timed out", "timeout reason")
}

@MainActor
private func testUnavailableSanitizesStderr(_ harness: inout TestHarness) async {
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 2, stdout: "", stderr: "failed --token abc123 https://example.com/path?secret=value", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.listSessions()
    guard case .unavailable(let reason) = result else {
        harness.expect(false, "expected unavailable")
        return
    }
    harness.expect(reason.contains("abc123") == false, "stderr token redacted")
    harness.expect(reason.contains("secret=value") == false, "stderr URL query redacted")
}

@MainActor
private func testCloseSuccess(_ harness: inout TestHarness) async {
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 0, stdout: AgentBrowserJSONFixtures.closeSuccess, stderr: "", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.closeSession(name: "alpha")
    harness.expectEqual(result, .success, "close success")
}

@MainActor
private func testCloseErrorSanitizesMessage(_ harness: inout TestHarness) async {
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 0, stdout: "{\"success\":false,\"error\":\"bad --password swordfish\"}", stderr: "", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    let result = await client.closeSession(name: "alpha")
    guard case .error(let message) = result else {
        harness.expect(false, "expected close error")
        return
    }
    harness.expect(message.contains("swordfish") == false, "close error redacted")
}

@MainActor
private func testCloseUsesGlobalSessionFlagOrder(_ harness: inout TestHarness) async {
    final class Capture: @unchecked Sendable {
        var executable = ""
        var arguments: [String] = []
    }
    let capture = Capture()
    let runner = MockCommandRunner { executable, arguments in
        capture.executable = executable
        capture.arguments = arguments
        return CommandResult(exitCode: 0, stdout: AgentBrowserJSONFixtures.closeSuccess, stderr: "", timedOut: false)
    }
    let client = AgentBrowserClient(commandRunner: runner)
    _ = await client.closeSession(name: "alpha")
    harness.expectEqual(capture.executable, "agent-browser", "close executable")
    harness.expectEqual(capture.arguments, ["--session", "alpha", "close", "--json"], "close argv order")
}

@MainActor
private func testStableSessionIDs(_ harness: inout TestHarness) async {
    let first = DetectedEntry.agentBrowserSession(name: "alpha")
    let second = DetectedEntry.agentBrowserSession(name: "alpha")
    let other = DetectedEntry.agentBrowserSession(name: "beta")
    harness.expectEqual(first.id, second.id, "stable id for same session")
    harness.expect(first.id != other.id, "different ids for different sessions")
}

@MainActor
private func runAgentBrowserIntegrationTestsIfEnabled(_ harness: inout TestHarness) async {
    guard ProcessInfo.processInfo.environment["BROWSER_SESSIONS_INTEGRATION"] == "1" else { return }
    let which = await CommandRunner().run(executable: "which", arguments: ["agent-browser"], timeout: .seconds(2))
    guard which.succeeded, !which.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fputs("SKIP integration: agent-browser not on PATH\n", stderr)
        return
    }
    let client = AgentBrowserClient()
    let list = await client.listSessions()
    switch list {
    case .available:
        break
    case .unavailable(let reason):
        harness.expect(false, "integration list unavailable: \(reason)")
    case .error(let message):
        harness.expect(false, "integration list error: \(message)")
    }
}

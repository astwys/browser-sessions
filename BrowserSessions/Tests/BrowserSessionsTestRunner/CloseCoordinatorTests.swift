import Foundation
import BrowserSessionsCore

private struct CloseMockAgentBrowserClient: AgentBrowserClientProtocol {
    let closeResult: AgentBrowserCloseResult

    func listSessions() async -> AgentBrowserListResult { .available([]) }
    func getURL(session: String) async -> String? { nil }
    func closeSession(name: String) async -> AgentBrowserCloseResult { closeResult }
}

private struct MockIdentityReader: ProcessIdentityReading {
    let identity: ProcessIdentity?
    func currentIdentity(pid: Int32) async -> ProcessIdentity? { identity }
}

private final class MockProcessKiller: ProcessKilling, @unchecked Sendable {
    var killedPIDs: [Int32] = []
    let result: ProcessKillResult

    init(result: ProcessKillResult = .success) {
        self.result = result
    }

    func terminate(pid: Int32) -> ProcessKillResult {
        killedPIDs.append(pid)
        return result
    }
}

@MainActor
func runCloseCoordinatorTests(_ harness: inout TestHarness) async {
    await testKnownSessionCloseInvokesAgentBrowser(&harness)
    await testHighProcessRevalidatesThenKillsPID(&harness)
    await testLowProcessIsNotClosable(&harness)
    await testStaleTargetDoesNotKill(&harness)
    await testProcessKillerRejectsInvalidPID(&harness)
    await testProcessKillerTerminatesSpawnedChildOnly(&harness)
}

@MainActor
private func testKnownSessionCloseInvokesAgentBrowser(_ harness: inout TestHarness) async {
    let coordinator = CloseCoordinator(
        agentBrowserClient: CloseMockAgentBrowserClient(closeResult: .success),
        identityReader: MockIdentityReader(identity: nil),
        processKiller: MockProcessKiller()
    )
    let outcome = await coordinator.close(DetectedEntry.agentBrowserSession(name: "alpha"))
    harness.expectEqual(outcome, .success, "known session close succeeds")
}

@MainActor
private func testHighProcessRevalidatesThenKillsPID(_ harness: inout TestHarness) async {
    let identity = makeCloseIdentity()
    let killer = MockProcessKiller()
    let coordinator = CloseCoordinator(
        agentBrowserClient: CloseMockAgentBrowserClient(closeResult: .success),
        identityReader: MockIdentityReader(identity: identity),
        processKiller: killer
    )
    let entry = DetectedEntry.process(identity: identity, confidence: .high, displayName: "Chrome")
    let outcome = await coordinator.close(entry)
    harness.expectEqual(outcome, .success, "high process close succeeds")
    harness.expectEqual(killer.killedPIDs, [identity.pid], "kills browser PID only")
}

@MainActor
private func testLowProcessIsNotClosable(_ harness: inout TestHarness) async {
    let identity = makeCloseIdentity()
    let killer = MockProcessKiller()
    let coordinator = CloseCoordinator(
        agentBrowserClient: CloseMockAgentBrowserClient(closeResult: .success),
        identityReader: MockIdentityReader(identity: identity),
        processKiller: killer
    )
    let entry = DetectedEntry.process(identity: identity, confidence: .low, displayName: "Chrome")
    let outcome = await coordinator.close(entry)
    harness.expectEqual(outcome, .notClosable, "low process is inspect-only")
    harness.expectEqual(killer.killedPIDs, [], "low process not killed")
}

@MainActor
private func testStaleTargetDoesNotKill(_ harness: inout TestHarness) async {
    let original = makeCloseIdentity()
    let changed = makeCloseIdentity(startTime: Date(timeIntervalSince1970: 20))
    let killer = MockProcessKiller()
    let coordinator = CloseCoordinator(
        agentBrowserClient: CloseMockAgentBrowserClient(closeResult: .success),
        identityReader: MockIdentityReader(identity: changed),
        processKiller: killer
    )
    let entry = DetectedEntry.process(identity: original, confidence: .high, displayName: "Chrome")
    let outcome = await coordinator.close(entry)
    harness.expectEqual(outcome, .staleTarget, "changed identity aborts")
    harness.expectEqual(killer.killedPIDs, [], "stale process not killed")
}

@MainActor
private func testProcessKillerRejectsInvalidPID(_ harness: inout TestHarness) async {
    let result = ProcessKiller().terminate(pid: 0)
    guard case .failed = result else {
        harness.expect(false, "invalid PID rejected")
        return
    }
}

@MainActor
private func testProcessKillerTerminatesSpawnedChildOnly(_ harness: inout TestHarness) async {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    do {
        try process.run()
    } catch {
        harness.expect(false, "spawn sleep for killer integration")
        return
    }
    let result = ProcessKiller().terminate(pid: process.processIdentifier)
    harness.expectEqual(result, .success, "kill spawned child")
    process.waitUntilExit()
    harness.expect(process.terminationStatus != 0, "spawned child terminated by signal")
}

private func makeCloseIdentity(startTime: Date = Date(timeIntervalSince1970: 10)) -> ProcessIdentity {
    ProcessIdentity(
        pid: 9876,
        parentPID: 42,
        startTime: startTime,
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        commandLine: CmdlineFixtures.playwrightPipe,
        signalTokens: ["--remote-debugging-pipe"]
    )
}

import Foundation
import BrowserSessionsCore

@MainActor
func runDegradationBannerTests(_ harness: inout TestHarness) async {
    testSnapshotCarriesDegradedReason(&harness)
    await testCliMissingProducesDegradedSnapshot(&harness)
}

@MainActor
private func testSnapshotCarriesDegradedReason(_ harness: inout TestHarness) {
    let snapshot = DetectionSnapshot(entries: [], degradedReason: "agent-browser not found on PATH")
    harness.expectEqual(snapshot.degradedReason, "agent-browser not found on PATH", "snapshot carries degraded reason")
    harness.expectEqual(snapshot.totalCount, 0, "degraded empty snapshot has zero rows")
}

@MainActor
private func testCliMissingProducesDegradedSnapshot(_ harness: inout TestHarness) async {
    let records = [ProcessFixtures.agentBrowserDaemon, ProcessFixtures.record(321, parent: 1, ProcessFixtures.chromeApp + "/MacOS/Google Chrome", "--remote-debugging-port=9222")]
    let engine = DetectionEngine(
        agentBrowserClient: DegradationMockAgentBrowserClient(),
        listProcesses: { records }
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.degradedReason, "agent-browser not found on PATH", "cli missing reason")
    harness.expectEqual(snapshot.totalCount, 1, "process rows remain visible during degradation")
}

private struct DegradationMockAgentBrowserClient: AgentBrowserClientProtocol {
    func listSessions() async -> AgentBrowserListResult { .unavailable(reason: "agent-browser not found on PATH") }
    func closeSession(name: String) async -> AgentBrowserCloseResult { .unavailable(reason: "agent-browser not found on PATH") }
}

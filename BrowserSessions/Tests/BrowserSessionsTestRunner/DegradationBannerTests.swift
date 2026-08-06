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
    let process = DetectedEntry.process(
        identity: ProcessIdentity(
            pid: 321,
            parentPID: 1,
            startTime: Date(timeIntervalSince1970: 10),
            executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            commandLine: CmdlineFixtures.remoteDebuggingOnly,
            signalTokens: ["--remote-debugging-port="]
        ),
        confidence: .low,
        displayName: "Google Chrome"
    )
    let engine = DetectionEngine(
        agentBrowserClient: DegradationMockAgentBrowserClient(),
        processScanner: DegradationMockProcessScanner(entries: [process])
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.degradedReason, "agent-browser not found on PATH", "cli missing reason")
    harness.expectEqual(snapshot.totalCount, 1, "process rows remain visible during degradation")
}

private struct DegradationMockAgentBrowserClient: AgentBrowserClientProtocol {
    func listSessions() async -> AgentBrowserListResult { .unavailable(reason: "agent-browser not found on PATH") }
    func getURL(session: String) async -> String? { nil }
    func closeSession(name: String) async -> AgentBrowserCloseResult { .unavailable(reason: "agent-browser not found on PATH") }
}

private struct DegradationMockProcessScanner: ProcessScanning {
    let entries: [DetectedEntry]
    func scan() async -> [DetectedEntry] { entries }
    func scan(records: [ProcessRecord]) -> [DetectedEntry] { entries }
}

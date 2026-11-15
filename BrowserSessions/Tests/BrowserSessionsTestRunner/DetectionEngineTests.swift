import Foundation
import BrowserSessionsCore

private struct MockAgentBrowserClient: AgentBrowserClientProtocol {
    final class Calls: @unchecked Sendable {
        var count = 0
    }

    let result: AgentBrowserListResult
    var calls = Calls()

    func listSessions() async -> AgentBrowserListResult {
        calls.count += 1
        return result
    }
    func closeSession(name: String) async -> AgentBrowserCloseResult { .success }
}

private struct MockAgentBrowserProcessResolver: AgentBrowserProcessResolving {
    var metadata: [String: AgentBrowserProcessMetadata] = [:]
    func metadata(for sessionNames: [String], records: [ProcessRecord]) -> [String: AgentBrowserProcessMetadata] { metadata }
}

@MainActor
func runDetectionEngineTests(_ harness: inout TestHarness) async {
    await testDetectionEngineMergesSessionsAndProcesses(&harness)
    await testDetectionEngineEnrichesKnownSessionWithProcessMetadata(&harness)
    await testDetectionEngineShowsOneRowPerRealBrowser(&harness)
    await testDetectionEngineCarriesDegradedReason(&harness)
    await testDetectionEngineAsksCLIOnlyWhenDaemonsChange(&harness)
    await testSessionMonitorPublishesEngineSnapshot(&harness)
}

@MainActor
private func testDetectionEngineMergesSessionsAndProcesses(_ harness: inout TestHarness) async {
    let records = [
        ProcessFixtures.agentBrowserDaemon,
        ProcessFixtures.record(10, parent: 1, "/usr/local/bin/node", "/repo/node_modules/.bin/playwright test"),
        ProcessFixtures.record(11, parent: 10, ProcessFixtures.chromeApp + "/MacOS/Google Chrome", "--remote-debugging-pipe")
    ]
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .available([DetectedEntry.agentBrowserSession(name: "alpha")])),
        listProcesses: { records },
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver()
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.totalCount, 2, "merged count")
    harness.expectEqual(snapshot.knownSessions.count, 1, "known section count")
    harness.expectEqual(snapshot.highConfidenceProcesses.count, 1, "high process section count")
    harness.expectEqual(snapshot.lowConfidenceProcesses.count, 0, "low process section count")
    harness.expectEqual(snapshot.highConfidenceProcesses.first?.parentProcessSummary, "/usr/local/bin/node /repo/node_modules/.bin/playwright test", "process parent summary")
    harness.expectEqual(snapshot.highConfidenceProcesses.first?.signalReason, "--remote-debugging-pipe, playwright", "process signal reason")
}

@MainActor
private func testDetectionEngineEnrichesKnownSessionWithProcessMetadata(_ harness: inout TestHarness) async {
    let browserIdentity = ProcessIdentity(
        pid: 321,
        parentPID: 320,
        startTime: Date(timeIntervalSince1970: 10),
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        commandLine: CmdlineFixtures.remoteDebuggingOnly,
        signalTokens: ["--remote-debugging-port="]
    )
    let metadata = AgentBrowserProcessMetadata(
        sessionName: "alpha",
        agentPID: 320,
        engine: "chrome",
        version: "0.29.0",
        streamPort: "50995",
        browserIdentity: browserIdentity,
        browserCommandLineSnippet: "Google Chrome --remote-debugging-port=0",
        agentProcessSummary: "agent-browser daemon"
    )
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .available([DetectedEntry.agentBrowserSession(name: "alpha")])),
        listProcesses: { [ProcessFixtures.agentBrowserDaemon] },
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver(metadata: ["alpha": metadata])
    )
    let snapshot = await engine.snapshot()
    let known = snapshot.knownSessions.first
    harness.expectEqual(known?.processIdentity?.pid, 321, "known session carries browser pid")
    harness.expectEqual(known?.parentProcessSummary, "agent-browser daemon", "known session carries agent process summary")
    harness.expect(known?.signalReason?.contains("PID 320") == true, "known session carries daemon pid detail")
    harness.expect(known?.signalReason?.contains("engine chrome") == true, "known session carries engine detail")
}

/// The regression from the review: two browsers (chrome-devtools-mcp's Chrome and an agent-browser
/// session) used to produce 32 rows.
@MainActor
private func testDetectionEngineShowsOneRowPerRealBrowser(_ harness: inout TestHarness) async {
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .available([DetectedEntry.agentBrowserSession(name: "alpha")])),
        listProcesses: { ProcessFixtures.realWorldTable },
        agentBrowserProcessResolver: AgentBrowserProcessResolver(stateDirectory: temporaryStateDirectory(pid: "600"))
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.totalCount, 2, "two browsers, two rows")
    harness.expectEqual(snapshot.knownSessions.first?.processIdentity?.pid, 601, "agent-browser row owns its browser PID")
    harness.expectEqual(snapshot.highConfidenceProcesses.map { $0.processIdentity?.pid }, [502], "chrome-devtools-mcp browser is one high row")
    harness.expectEqual(snapshot.lowConfidenceProcesses.count, 0, "agent-browser's browser is not repeated as a process row")
}

@MainActor
private func testDetectionEngineCarriesDegradedReason(_ harness: inout TestHarness) async {
    let records = [ProcessFixtures.agentBrowserDaemon, ProcessFixtures.record(456, parent: 1, ProcessFixtures.chromeApp + "/MacOS/Google Chrome", "--remote-debugging-port=9222")]
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .unavailable(reason: "agent-browser missing")),
        listProcesses: { records },
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver()
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.totalCount, 1, "processes still count when cli unavailable")
    harness.expectEqual(snapshot.degradedReason, "agent-browser missing", "degraded reason")
    harness.expectEqual(snapshot.lowConfidenceProcesses.count, 1, "low process survives degradation")
}

@MainActor
private func testDetectionEngineAsksCLIOnlyWhenDaemonsChange(_ harness: inout TestHarness) async {
    final class Table: @unchecked Sendable {
        var records: [ProcessRecord] = []
    }
    let table = Table()
    let client = MockAgentBrowserClient(result: .available([DetectedEntry.agentBrowserSession(name: "alpha")]))
    let engine = DetectionEngine(
        agentBrowserClient: client,
        listProcesses: { table.records },
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver()
    )

    let idle = await engine.snapshot()
    harness.expectEqual(client.calls.count, 0, "no agent-browser process: the CLI is not spawned")
    harness.expectEqual(idle.knownSessions.count, 0, "no agent-browser process: no sessions")

    table.records = [ProcessFixtures.agentBrowserDaemon]
    _ = await engine.snapshot()
    let unchanged = await engine.snapshot()
    harness.expectEqual(client.calls.count, 1, "unchanged daemons reuse the last session list")
    harness.expectEqual(unchanged.knownSessions.map(\.sessionName), ["alpha"], "cached list is still shown")

    table.records = [ProcessFixtures.agentBrowserDaemon, ProcessFixtures.record(700, parent: 1, "/opt/homebrew/bin/agent-browser", "")]
    _ = await engine.snapshot()
    harness.expectEqual(client.calls.count, 2, "a new daemon triggers a fresh session list")
}

@MainActor
private func testSessionMonitorPublishesEngineSnapshot(_ harness: inout TestHarness) async {
    let entry = DetectedEntry.agentBrowserSession(name: "alpha")
    let monitor = SessionMonitor(snapshotProvider: { DetectionSnapshot(entries: [entry]) }, autostart: false)
    await monitor.pollOnce()
    harness.expectEqual(monitor.snapshot.totalCount, 1, "monitor publishes provider snapshot")
    harness.expectEqual(monitor.snapshot.entries.first?.id, entry.id, "monitor preserves row id")
}

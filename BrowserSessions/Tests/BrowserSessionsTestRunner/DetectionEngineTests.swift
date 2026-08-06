import Foundation
import BrowserSessionsCore

private struct MockAgentBrowserClient: AgentBrowserClientProtocol {
    let result: AgentBrowserListResult
    var urls: [String: String] = [:]

    func listSessions() async -> AgentBrowserListResult { result }
    func getURL(session: String) async -> String? { urls[session] }
    func closeSession(name: String) async -> AgentBrowserCloseResult { .success }
}

private struct MockProcessSnapshotProvider: ProcessSnapshotProviding {
    let records: [ProcessRecord]
    func records() async -> [ProcessRecord] { records }
}

private struct MockProcessScanner: ProcessScanning {
    let entries: [DetectedEntry]
    func scan() async -> [DetectedEntry] { entries }
    func scan(records: [ProcessRecord]) -> [DetectedEntry] { entries }
}

private struct MockAgentBrowserProcessResolver: AgentBrowserProcessResolving {
    var metadata: [String: AgentBrowserProcessMetadata] = [:]
    func metadata(for sessionNames: [String]) async -> [String: AgentBrowserProcessMetadata] { metadata }
    func metadata(for sessionNames: [String], records: [ProcessRecord]) async -> [String: AgentBrowserProcessMetadata] { metadata }
}

@MainActor
func runDetectionEngineTests(_ harness: inout TestHarness) async {
    await testDetectionEngineMergesSessionsAndProcesses(&harness)
    await testDetectionEngineEnrichesKnownSessionWithProcessMetadata(&harness)
    await testDetectionEngineSuppressesKnownSessionProcessDuplicate(&harness)
    await testDetectionEngineDoesNotProbeKnownSessionURL(&harness)
    await testDetectionEngineCarriesDegradedReason(&harness)
    await testSessionMonitorPublishesEngineSnapshot(&harness)
}

@MainActor
private func testDetectionEngineMergesSessionsAndProcesses(_ harness: inout TestHarness) async {
    let known = [DetectedEntry.agentBrowserSession(name: "alpha")]
    let process = makeProcessEntry(pid: 123, confidence: .high)
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .available(known)),
        processSnapshotProvider: MockProcessSnapshotProvider(records: []),
        processScanner: MockProcessScanner(entries: [process]),
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver()
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.totalCount, 2, "merged count")
    harness.expectEqual(snapshot.knownSessions.count, 1, "known section count")
    harness.expectEqual(snapshot.highConfidenceProcesses.count, 1, "high process section count")
    harness.expectEqual(snapshot.lowConfidenceProcesses.count, 0, "low process section count")
    harness.expectEqual(snapshot.highConfidenceProcesses.first?.parentProcessSummary, "node playwright test", "process parent summary")
    harness.expectEqual(snapshot.highConfidenceProcesses.first?.signalReason, "--remote-debugging-port=", "process signal reason")
}

@MainActor
private func testDetectionEngineEnrichesKnownSessionWithProcessMetadata(_ harness: inout TestHarness) async {
    let browserIdentity = makeProcessIdentity(pid: 321)
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
        processSnapshotProvider: MockProcessSnapshotProvider(records: []),
        processScanner: MockProcessScanner(entries: []),
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver(metadata: ["alpha": metadata])
    )
    let snapshot = await engine.snapshot()
    let known = snapshot.knownSessions.first
    harness.expectEqual(known?.processIdentity?.pid, 321, "known session carries browser pid")
    harness.expectEqual(known?.parentProcessSummary, "agent-browser daemon", "known session carries agent process summary")
    harness.expect(known?.signalReason?.contains("agent PID 320") == true, "known session carries agent pid detail")
    harness.expect(known?.signalReason?.contains("engine chrome") == true, "known session carries engine detail")
}

@MainActor
private func testDetectionEngineSuppressesKnownSessionProcessDuplicate(_ harness: inout TestHarness) async {
    let process = makeProcessEntry(pid: 654, confidence: .low)
    let metadata = AgentBrowserProcessMetadata(
        sessionName: "alpha",
        agentPID: 653,
        browserIdentity: process.processIdentity
    )
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .available([DetectedEntry.agentBrowserSession(name: "alpha")])),
        processSnapshotProvider: MockProcessSnapshotProvider(records: []),
        processScanner: MockProcessScanner(entries: [process]),
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver(metadata: ["alpha": metadata])
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.totalCount, 1, "known browser process is not duplicated as a process row")
    harness.expectEqual(snapshot.knownSessions.count, 1, "known section keeps enriched row")
    harness.expectEqual(snapshot.lowConfidenceProcesses.count, 0, "duplicate low process row suppressed")
}

@MainActor
private func testDetectionEngineDoesNotProbeKnownSessionURL(_ harness: inout TestHarness) async {
    let known = [DetectedEntry.agentBrowserSession(name: "alpha")]
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .available(known), urls: ["alpha": "https://example.com/path?token=secret"]),
        processSnapshotProvider: MockProcessSnapshotProvider(records: []),
        processScanner: MockProcessScanner(entries: []),
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver()
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.knownSessions.first?.url, nil, "known session URL is not probed during polling because get url can recreate closed sessions")
}

@MainActor
private func testDetectionEngineCarriesDegradedReason(_ harness: inout TestHarness) async {
    let process = makeProcessEntry(pid: 456, confidence: .low)
    let engine = DetectionEngine(
        agentBrowserClient: MockAgentBrowserClient(result: .unavailable(reason: "agent-browser missing")),
        processSnapshotProvider: MockProcessSnapshotProvider(records: []),
        processScanner: MockProcessScanner(entries: [process]),
        agentBrowserProcessResolver: MockAgentBrowserProcessResolver()
    )
    let snapshot = await engine.snapshot()
    harness.expectEqual(snapshot.totalCount, 1, "processes still count when cli unavailable")
    harness.expectEqual(snapshot.degradedReason, "agent-browser missing", "degraded reason")
    harness.expectEqual(snapshot.lowConfidenceProcesses.count, 1, "low process survives degradation")
}

@MainActor
private func testSessionMonitorPublishesEngineSnapshot(_ harness: inout TestHarness) async {
    let entry = DetectedEntry.agentBrowserSession(name: "alpha")
    let monitor = SessionMonitor(snapshotProvider: { DetectionSnapshot(entries: [entry]) }, autostart: false)
    await monitor.pollOnce()
    harness.expectEqual(monitor.snapshot.totalCount, 1, "monitor publishes provider snapshot")
    harness.expectEqual(monitor.snapshot.entries.first?.id, entry.id, "monitor preserves row id")
}

private func makeProcessEntry(pid: Int32, confidence: ConfidenceTier) -> DetectedEntry {
    let identity = makeProcessIdentity(pid: pid)
    return DetectedEntry.process(
        identity: identity,
        confidence: confidence,
        displayName: "Google Chrome",
        parentProcessSummary: "node playwright test"
    )
}

private func makeProcessIdentity(pid: Int32) -> ProcessIdentity {
    ProcessIdentity(
        pid: pid,
        parentPID: 1,
        startTime: Date(timeIntervalSince1970: 10),
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        commandLine: CmdlineFixtures.remoteDebuggingOnly,
        signalTokens: ["--remote-debugging-port="]
    )
}

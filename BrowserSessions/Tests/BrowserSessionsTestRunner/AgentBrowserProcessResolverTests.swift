import Foundation
import BrowserSessionsCore

@MainActor
func runAgentBrowserProcessResolverTests(_ harness: inout TestHarness) async {
    testResolverConnectsSessionPidToBrowserChild(&harness)
    testResolverIgnoresUnsafeSessionNames(&harness)
}

@MainActor
private func testResolverConnectsSessionPidToBrowserChild(_ harness: inout TestHarness) {
    let stateDirectory = temporaryStateDirectory(pid: "600")
    write("chrome", to: stateDirectory.appendingPathComponent("alpha.engine"))
    write("0.43.0", to: stateDirectory.appendingPathComponent("alpha.version"))
    write("50995", to: stateDirectory.appendingPathComponent("alpha.stream"))

    let resolver = AgentBrowserProcessResolver(stateDirectory: stateDirectory)
    let metadata = resolver.metadata(for: ["alpha"], records: ProcessFixtures.realWorldTable)["alpha"]

    harness.expectEqual(metadata?.agentPID, 600, "resolver reads agent pid")
    harness.expectEqual(metadata?.engine, "chrome", "resolver reads engine")
    harness.expectEqual(metadata?.version, "0.43.0", "resolver reads version")
    harness.expectEqual(metadata?.streamPort, "50995", "resolver reads stream port")
    harness.expectEqual(metadata?.browserIdentity?.pid, 601, "resolver finds browser child pid")
    harness.expectEqual(metadata?.browserCommandLineSnippet, URLSanitizer.sanitizedCommandLineSnippet(ProcessFixtures.realWorldTable[7].commandLine), "resolver carries sanitized browser command")
}

@MainActor
private func testResolverIgnoresUnsafeSessionNames(_ harness: inout TestHarness) {
    let resolver = AgentBrowserProcessResolver(stateDirectory: temporaryStateDirectory(pid: "600"))
    let metadata = resolver.metadata(for: ["../alpha"], records: ProcessFixtures.realWorldTable)
    harness.expectEqual(metadata.count, 0, "unsafe session names do not read state files")
}

/// A state directory holding `alpha.pid`.
func temporaryStateDirectory(pid: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserSessionsTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    write(pid, to: url.appendingPathComponent("alpha.pid"))
    return url
}

private func write(_ value: String, to url: URL) {
    try? value.write(to: url, atomically: true, encoding: .utf8)
}

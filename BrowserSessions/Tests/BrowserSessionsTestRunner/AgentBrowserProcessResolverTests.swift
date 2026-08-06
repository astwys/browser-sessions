import Foundation
import BrowserSessionsCore

@MainActor
func runAgentBrowserProcessResolverTests(_ harness: inout TestHarness) async {
    await testResolverConnectsSessionPidToBrowserChild(&harness)
    await testResolverIgnoresUnsafeSessionNames(&harness)
}

@MainActor
private func testResolverConnectsSessionPidToBrowserChild(_ harness: inout TestHarness) async {
    let stateDirectory = temporaryStateDirectory()
    write("900", to: stateDirectory.appendingPathComponent("alpha.pid"))
    write("chrome", to: stateDirectory.appendingPathComponent("alpha.engine"))
    write("0.29.0", to: stateDirectory.appendingPathComponent("alpha.version"))
    write("50995", to: stateDirectory.appendingPathComponent("alpha.stream"))

    let psOutput = """
      900     1 Mon Jun 22 15:54:29 2026 /opt/homebrew/bin/agent-browser-daemon
      901   900 Mon Jun 22 15:54:30 2026 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=0 --user-data-dir=/tmp/agent-browser-profile
    """
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 0, stdout: psOutput, stderr: "", timedOut: false)
    }
    let resolver = AgentBrowserProcessResolver(commandRunner: runner, stateDirectory: stateDirectory)
    let metadata = await resolver.metadata(for: ["alpha"])["alpha"]

    harness.expectEqual(metadata?.agentPID, 900, "resolver reads agent pid")
    harness.expectEqual(metadata?.engine, "chrome", "resolver reads engine")
    harness.expectEqual(metadata?.version, "0.29.0", "resolver reads version")
    harness.expectEqual(metadata?.streamPort, "50995", "resolver reads stream port")
    harness.expectEqual(metadata?.browserIdentity?.pid, 901, "resolver finds browser child pid")
    harness.expect(metadata?.browserCommandLineSnippet?.contains("--remote-debugging-port=0") == true, "resolver carries sanitized browser command")
}

@MainActor
private func testResolverIgnoresUnsafeSessionNames(_ harness: inout TestHarness) async {
    let stateDirectory = temporaryStateDirectory()
    write("900", to: stateDirectory.appendingPathComponent("alpha.pid"))
    let runner = MockCommandRunner { _, _ in
        CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
    }
    let resolver = AgentBrowserProcessResolver(commandRunner: runner, stateDirectory: stateDirectory)
    let metadata = await resolver.metadata(for: ["../alpha"])
    harness.expectEqual(metadata.count, 0, "unsafe session names do not read state files")
}

private func temporaryStateDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserSessionsTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ value: String, to url: URL) {
    try? value.write(to: url, atomically: true, encoding: .utf8)
}

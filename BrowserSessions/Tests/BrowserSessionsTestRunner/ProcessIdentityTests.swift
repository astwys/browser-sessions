import Foundation
import BrowserSessionsCore

@MainActor
func runProcessIdentityTests(_ harness: inout TestHarness) async {
    testIdentityMatchesSameTuple(&harness)
    testIdentityRejectsStartTimeDrift(&harness)
    testIdentityRejectsExecutableChange(&harness)
    testIdentityRejectsCommandLineChange(&harness)
    testIdentityMatchesParentDerivedSignals(&harness)
    await testIdentityReaderIncludesParentSignals(&harness)
    testProcessStableID(&harness)
    testPSOutputParsing(&harness)
    testWhitespacePSOutputParsing(&harness)
}

private func makeIdentity(pid: Int32 = 42, startTime: Date = Date(timeIntervalSince1970: 100), executablePath: String = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", commandLine: String = CmdlineFixtures.remoteDebuggingOnly, tokens: [String] = ["--remote-debugging-port="]) -> ProcessIdentity {
    ProcessIdentity(pid: pid, parentPID: 1, startTime: startTime, executablePath: executablePath, commandLine: commandLine, signalTokens: tokens)
}

@MainActor
private func testIdentityMatchesSameTuple(_ harness: inout TestHarness) {
    harness.expect(makeIdentity().matches(current: makeIdentity()), "same tuple matches")
}

@MainActor
private func testIdentityRejectsStartTimeDrift(_ harness: inout TestHarness) {
    let original = makeIdentity()
    let current = makeIdentity(startTime: Date(timeIntervalSince1970: 104))
    harness.expect(original.matches(current: current) == false, "start time drift fails")
}

@MainActor
private func testIdentityRejectsExecutableChange(_ harness: inout TestHarness) {
    let original = makeIdentity()
    let current = makeIdentity(executablePath: "/Applications/Chromium.app/Contents/MacOS/Chromium")
    harness.expect(original.matches(current: current) == false, "executable basename change fails")
}

@MainActor
private func testIdentityRejectsCommandLineChange(_ harness: inout TestHarness) {
    let original = makeIdentity(commandLine: CmdlineFixtures.remoteDebuggingOnly)
    let current = makeIdentity(commandLine: CmdlineFixtures.remoteDebuggingOnly + " --user-data-dir=/tmp/other")
    harness.expect(original.matches(current: current) == false, "command line change fails")
}

@MainActor
private func testIdentityMatchesParentDerivedSignals(_ harness: inout TestHarness) {
    let original = makeIdentity(commandLine: CmdlineFixtures.headlessOnly, tokens: ["playwright"])
    let current = makeIdentity(commandLine: CmdlineFixtures.headlessOnly, tokens: ["playwright"])
    harness.expect(original.matches(current: current), "parent-derived signal token matches via current signal tokens")
}

@MainActor
private func testIdentityReaderIncludesParentSignals(_ harness: inout TestHarness) async {
    let childLine = "301   300 Mon Jun 22 15:54:30 2026 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new"
    let runner = MockCommandRunner { _, arguments in
        if arguments.contains("301") {
            return CommandResult(exitCode: 0, stdout: childLine, stderr: "", timedOut: false)
        }
        if arguments.contains("300") {
            return CommandResult(exitCode: 0, stdout: CmdlineFixtures.parentPlaywright, stderr: "", timedOut: false)
        }
        return CommandResult(exitCode: 1, stdout: "", stderr: "", timedOut: false)
    }
    let identity = await ProcessIdentityReader(commandRunner: runner).currentIdentity(pid: 301)
    harness.expectEqual(identity?.signalTokens, ["playwright"], "identity reader carries parent-derived signal tokens")
}

@MainActor
private func testProcessStableID(_ harness: inout TestHarness) {
    let identity = makeIdentity()
    let first = DetectedEntry.process(identity: identity, confidence: .low, displayName: "Chrome")
    let second = DetectedEntry.process(identity: identity, confidence: .low, displayName: "Chrome")
    harness.expectEqual(first.id, second.id, "process id stable")
    harness.expect(first.isClosable == false, "low not closable")
    let high = DetectedEntry.process(identity: identity, confidence: .high, displayName: "Chrome")
    harness.expect(high.isClosable, "high closable")
}

@MainActor
private func testPSOutputParsing(_ harness: inout TestHarness) {
    let now = Date(timeIntervalSince1970: 1_000)
    let records = ProcessArguments.parsePSOutput(CmdlineFixtures.psOutput, now: now)
    harness.expectEqual(records.count, 2, "ps record count")
    harness.expectEqual(records.first?.pid, 101, "ps pid")
    harness.expectEqual(records.first?.parentPID, 1, "ps ppid")
    harness.expectEqual(records.first?.startTime, Date(timeIntervalSince1970: 988), "ps etimes to start")
}

@MainActor
private func testWhitespacePSOutputParsing(_ harness: inout TestHarness) {
    let records = ProcessArguments.parsePSOutput(CmdlineFixtures.whitespacePSOutput)
    harness.expectEqual(records.count, 2, "whitespace ps record count")
    harness.expectEqual(records.first?.pid, 201, "whitespace ps pid")
    harness.expectEqual(records.first?.parentPID, 1, "whitespace ps ppid")
    harness.expectEqual(records.first?.executablePath, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "infer executable with app path spaces")
    harness.expect(records.first?.commandLine.contains("--remote-debugging-port=9222") == true, "preserve command line args")
}

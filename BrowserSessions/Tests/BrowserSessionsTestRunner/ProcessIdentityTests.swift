import Foundation
import BrowserSessionsCore

@MainActor
func runProcessIdentityTests(_ harness: inout TestHarness) async {
    testIdentityMatchesSameTuple(&harness)
    testIdentityRejectsStartTimeDrift(&harness)
    testIdentityRejectsSubSecondStartTimeDrift(&harness)
    testIdentityRejectsExecutableChange(&harness)
    testIdentityRejectsCommandLineChange(&harness)
    testIdentityMatchesParentDerivedSignals(&harness)
    testIdentityReaderIncludesParentSignals(&harness)
    testProcessStableID(&harness)
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
private func testIdentityRejectsSubSecondStartTimeDrift(_ harness: inout TestHarness) {
    let original = makeIdentity()
    let current = makeIdentity(startTime: Date(timeIntervalSince1970: 100.000_001))
    harness.expect(original.matches(current: current) == false, "a reused PID started within the same second fails")
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
private func testIdentityReaderIncludesParentSignals(_ harness: inout TestHarness) {
    let records: [Int32: ProcessRecord] = [
        301: ProcessFixtures.record(301, parent: 300, ProcessFixtures.chromeApp + "/MacOS/Google Chrome", "--headless=new"),
        300: ProcessRecord(pid: 300, parentPID: 1, startTime: Date(timeIntervalSince1970: 1), executablePath: "/usr/local/bin/node", commandLine: CmdlineFixtures.parentPlaywright)
    ]
    let identity = ProcessIdentityReader(lookup: { records[$0] }).currentIdentity(pid: 301)
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

import Foundation
import BrowserSessionsCore

@MainActor
func runProcessScannerTests(_ harness: inout TestHarness) async {
    testScannerListsEachBrowserOnce(&harness)
    testScannerToleratesDuplicatePIDs(&harness)
    testLauncherNames(&harness)
}

@MainActor
private func testLauncherNames(_ harness: inout TestHarness) {
    func launcher(_ parent: String?) -> String? {
        DetectedEntry(id: "x", source: .process, sessionName: "x", parentProcessSummary: parent).launcherName
    }
    harness.expectEqual(launcher("/usr/local/bin/node node_modules/.bin/playwright test a.spec.ts"), "playwright", "interpreter runs a script: name the script")
    harness.expectEqual(launcher("node --inspect /srv/run-tests.mjs"), "run-tests", "interpreter flags are skipped")
    harness.expectEqual(launcher("chrome-devtools-mcp"), "chrome-devtools-mcp", "plain program name")
    harness.expectEqual(launcher("/bin/zsh -l"), "zsh", "path is reduced to the program")
    harness.expectEqual(launcher(nil), nil, "no parent, no launcher")
}

@MainActor
private func testScannerListsEachBrowserOnce(_ harness: inout TestHarness) {
    let entries = ProcessScanner.entries(from: ProcessFixtures.realWorldTable)
    harness.expectEqual(entries.map { $0.processIdentity?.pid }, [502, 601], "one row per browser; helpers, crashpad and the MCP server are excluded")
    harness.expectEqual(entries.map(\.confidence), [.high, .low], "pipe browser is high, plain headless browser is low")
    harness.expectEqual(entries.first?.signalReason, "--remote-debugging-pipe", "signals come from the browser's own arguments")
    harness.expectEqual(entries.first?.parentProcessSummary, "chrome-devtools-mcp", "parent summary shows the launcher")
}

@MainActor
private func testScannerToleratesDuplicatePIDs(_ harness: inout TestHarness) {
    let browser = ProcessFixtures.realWorldTable[2]
    let entries = ProcessScanner.entries(from: [browser, browser])
    harness.expectEqual(entries.count, 2, "duplicate PIDs do not crash the scanner")
}

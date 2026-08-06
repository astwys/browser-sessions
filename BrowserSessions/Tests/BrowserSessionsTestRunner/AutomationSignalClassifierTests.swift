import Foundation
import BrowserSessionsCore

@MainActor
func runAutomationSignalClassifierTests(_ harness: inout TestHarness) async {
    testPlaywrightPipeIsHigh(&harness)
    testRemoteDebuggingPortOnlyIsLow(&harness)
    testHeadlessOnlyIsLow(&harness)
    testPuppeteerSignalsAreHigh(&harness)
    testParentPlaywrightIsHigh(&harness)
    testCrashpadIsExcluded(&harness)
    testRegularChromeIsLowByVisibilityPosture(&harness)
    testURLSanitizer(&harness)
}

@MainActor
private func testPlaywrightPipeIsHigh(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Users/me/Library/Caches/ms-playwright/chromium/Chromium", commandLine: CmdlineFixtures.playwrightPipe)
    harness.expectEqual(classification?.tier, .high, "playwright pipe is high")
    harness.expect(classification?.signalTokens.contains("--remote-debugging-pipe") == true, "captures pipe signal")
}

@MainActor
private func testRemoteDebuggingPortOnlyIsLow(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", commandLine: CmdlineFixtures.remoteDebuggingOnly)
    harness.expectEqual(classification?.tier, .low, "remote debugging port only is low")
    harness.expect(classification?.signalTokens.contains("--remote-debugging-port=") == true, "captures port signal")
}

@MainActor
private func testHeadlessOnlyIsLow(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", commandLine: CmdlineFixtures.headlessOnly)
    harness.expectEqual(classification?.tier, .low, "headless only is low")
}

@MainActor
private func testPuppeteerSignalsAreHigh(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Users/me/.cache/puppeteer/chrome/Google Chrome for Testing", commandLine: CmdlineFixtures.puppeteer)
    harness.expectEqual(classification?.tier, .high, "puppeteer cache path + automation high")
}

@MainActor
private func testParentPlaywrightIsHigh(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", commandLine: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", parentCommandLine: CmdlineFixtures.parentPlaywright)
    harness.expectEqual(classification?.tier, .high, "playwright parent high")
}

@MainActor
private func testCrashpadIsExcluded(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Applications/Google Chrome.app/Contents/Frameworks/chrome_crashpad_handler", commandLine: CmdlineFixtures.crashpad)
    harness.expectEqual(classification, nil, "crashpad excluded")
}

@MainActor
private func testRegularChromeIsLowByVisibilityPosture(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", commandLine: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    harness.expectEqual(classification?.tier, .low, "regular browser listed low by visibility posture")
}

@MainActor
private func testURLSanitizer(_ harness: inout TestHarness) {
    harness.expectEqual(URLSanitizer.displayString(for: "https://example.com/path?token=secret"), "example.com", "domain only")
    let snippet = URLSanitizer.sanitizedCommandLineSnippet("chrome https://example.com/?token=secret&ok=1", maxLength: 200)
    harness.expect(snippet.contains("secret") == false, "redacts query values")
}

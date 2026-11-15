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
    testBrowserHelpersAreExcluded(&harness)
    testToolsNamedAfterChromeAreNotBrowsers(&harness)
    testParentPathMentioningPlaywrightIsNotHigh(&harness)
    testPlaywrightFirefoxContentProcessIsExcluded(&harness)
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
private func testBrowserHelpersAreExcluded(_ harness: inout TestHarness) {
    let renderer = ProcessFixtures.realWorldTable[4]
    let classification = AutomationSignalClassifier.classify(
        executablePath: renderer.executablePath,
        commandLine: renderer.commandLine,
        parentCommandLine: ProcessFixtures.realWorldTable[2].commandLine
    )
    harness.expectEqual(classification, nil, "renderer helper does not inherit its browser's signals")
}

@MainActor
private func testToolsNamedAfterChromeAreNotBrowsers(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(executablePath: "/opt/homebrew/bin/chrome-devtools-mcp", commandLine: "chrome-devtools-mcp --headless")
    harness.expectEqual(classification, nil, "chrome-devtools-mcp is not a browser")
}

@MainActor
private func testParentPathMentioningPlaywrightIsNotHigh(_ harness: inout TestHarness) {
    let classification = AutomationSignalClassifier.classify(
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        commandLine: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        parentCommandLine: "/Applications/Zed.app/Contents/MacOS/zed /Users/me/git/playwright-demo"
    )
    harness.expectEqual(classification?.tier, .low, "a parent that merely mentions playwright is not an automation signal")
}

@MainActor
private func testPlaywrightFirefoxContentProcessIsExcluded(_ harness: inout TestHarness) {
    let firefox = "/Users/me/Library/Caches/ms-playwright/firefox-1449/firefox/Nightly.app/Contents/MacOS/firefox"
    let main = AutomationSignalClassifier.classify(executablePath: firefox, commandLine: firefox + " -no-remote -headless -juggler-pipe")
    let content = AutomationSignalClassifier.classify(executablePath: firefox, commandLine: firefox + " -contentproc -childID 1 -isForBrowser")
    harness.expectEqual(main?.tier, .high, "playwright firefox main process is high")
    harness.expectEqual(content, nil, "playwright firefox content process is excluded")
}

@MainActor
private func testURLSanitizer(_ harness: inout TestHarness) {
    let snippet = URLSanitizer.sanitizedCommandLineSnippet("chrome https://example.com/?token=secret&ok=1", maxLength: 200)
    harness.expect(snippet.contains("secret") == false, "redacts query values")
}

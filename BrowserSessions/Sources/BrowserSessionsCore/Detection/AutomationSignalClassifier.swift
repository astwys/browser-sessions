import Foundation

public struct ProcessClassification: Equatable, Sendable {
    public let tier: ConfidenceTier
    public let signalTokens: [String]
    public let displayName: String

    public init(tier: ConfidenceTier, signalTokens: [String], displayName: String) {
        self.tier = tier
        self.signalTokens = signalTokens
        self.displayName = displayName
    }
}

public enum AutomationSignalClassifier {
    /// Executable names of browser main processes. Matched exactly, so helpers
    /// ("Google Chrome Helper (Renderer)") and tools that merely mention Chrome ("chrome-devtools-mcp")
    /// are not browsers.
    private static let browserExecutables: Set<String> = [
        "Google Chrome", "Google Chrome Beta", "Google Chrome Dev", "Google Chrome Canary",
        "Google Chrome for Testing", "Chromium", "chrome", "chrome-headless-shell", "headless_shell",
        "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev", "Microsoft Edge Canary"
    ]

    /// Markers of the Node process that launched a browser through Playwright or Puppeteer. These are
    /// package paths rather than bare names, so an editor opened in `~/git/playwright-demo` does not count.
    private static let playwrightParentMarkers = ["playwright-core", "@playwright/", "node_modules/playwright", "node_modules/.bin/playwright"]
    private static let puppeteerParentMarkers = ["puppeteer-core", "node_modules/puppeteer", "node_modules/.bin/puppeteer"]

    private static let playwrightProfileMarkers = ["playwright_chromiumdev_profile", "playwright_firefoxdev_profile", "playwright_webkitdev_profile"]
    private static let lowSignalFlags = ["--remote-debugging-port=", "--headless", "--user-data-dir"]

    /// Classifies one process. Signals come from the process's own executable and arguments; the parent
    /// only contributes "launched by Playwright/Puppeteer". Children of a browser therefore never
    /// inherit its signals.
    public static func classify(
        executablePath: String,
        commandLine: String,
        parentCommandLine: String? = nil
    ) -> ProcessClassification? {
        let basename = (executablePath as NSString).lastPathComponent
        let path = executablePath.lowercased()
        let arguments = commandLine.lowercased()

        guard isHelper(path: path, arguments: arguments) == false,
              browserExecutables.contains(basename) || path.contains("/ms-playwright/")
        else { return nil }

        var highTokens: Set<String> = []
        if path.contains("/ms-playwright/") { highTokens.insert("ms-playwright") }
        if arguments.contains("--remote-debugging-pipe") { highTokens.insert("--remote-debugging-pipe") }
        for marker in playwrightProfileMarkers where arguments.contains(marker) {
            highTokens.insert(marker)
        }
        if (path + " " + arguments).contains("puppeteer") && arguments.contains("--enable-automation") {
            highTokens.formUnion(["puppeteer", "--enable-automation"])
        }
        if let parent = parentCommandLine?.lowercased() {
            if playwrightParentMarkers.contains(where: parent.contains) { highTokens.insert("playwright") }
            if puppeteerParentMarkers.contains(where: parent.contains) { highTokens.insert("puppeteer") }
        }
        if highTokens.isEmpty == false {
            return ProcessClassification(tier: .high, signalTokens: highTokens.sorted(), displayName: basename)
        }

        let lowTokens = lowSignalFlags.filter { arguments.contains($0) }
        return ProcessClassification(tier: .low, signalTokens: lowTokens.isEmpty ? [basename] : lowTokens, displayName: basename)
    }

    /// Renderer, GPU, utility and crashpad processes belong to a browser that is listed on its own.
    private static func isHelper(path: String, arguments: String) -> Bool {
        path.contains("/helpers/")
            || path.contains(".xpc/")
            || arguments.contains(" --type=")
            || arguments.contains(" -contentproc")
    }
}

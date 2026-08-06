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
    private static let browserBasenames = ["Google Chrome", "Chromium", "Chrome", "Microsoft Edge"]
    private static let excludedBasenames = ["chrome_crashpad_handler", "crashpad_handler"]

    public static func classify(
        executablePath: String,
        commandLine: String,
        parentCommandLine: String? = nil
    ) -> ProcessClassification? {
        let basename = URL(fileURLWithPath: executablePath).lastPathComponent
        let haystack = ([executablePath, commandLine, parentCommandLine].compactMap { $0 }).joined(separator: " ").lowercased()
        let parent = parentCommandLine?.lowercased() ?? ""

        if excludedBasenames.contains(where: { basename.localizedCaseInsensitiveContains($0) }) {
            return nil
        }

        let isBrowser = browserBasenames.contains { basename.localizedCaseInsensitiveContains($0) }
            || haystack.contains("ms-playwright")
        guard isBrowser else { return nil }

        var highTokens: [String] = []
        if haystack.contains("/library/caches/ms-playwright/") || haystack.contains("ms-playwright") {
            highTokens.append("ms-playwright")
        }
        if haystack.contains("--remote-debugging-pipe") {
            highTokens.append("--remote-debugging-pipe")
        }
        for token in ["playwright_chromiumdev_profile", "playwright_firefoxdev_profile", "playwright_webkitdev_profile"] where haystack.contains(token) {
            highTokens.append(token)
        }
        if parent.contains("playwright") || parent.contains("@playwright/test") || parent.contains("playwright-core") {
            highTokens.append("playwright")
        }
        if haystack.contains("puppeteer") && haystack.contains("--enable-automation") {
            highTokens.append("puppeteer")
            highTokens.append("--enable-automation")
        }
        if parent.contains("puppeteer") {
            highTokens.append("puppeteer")
        }

        if highTokens.isEmpty == false {
            return ProcessClassification(tier: .high, signalTokens: Array(Set(highTokens)).sorted(), displayName: basename)
        }

        var lowTokens: [String] = []
        for token in ["--remote-debugging-port=", "--headless", "--headless=new", "--user-data-dir"] where haystack.contains(token) {
            lowTokens.append(token)
        }
        if lowTokens.isEmpty { lowTokens.append(basename) }
        return ProcessClassification(tier: .low, signalTokens: Array(Set(lowTokens)).sorted(), displayName: basename)
    }
}

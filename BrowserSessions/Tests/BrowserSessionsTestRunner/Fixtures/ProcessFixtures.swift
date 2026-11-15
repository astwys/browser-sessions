import Foundation
import BrowserSessionsCore

/// Process shapes captured from a real machine running chrome-devtools-mcp and one agent-browser session.
/// Before helper exclusion, the full capture produced 32 rows for these two browsers.
enum ProcessFixtures {
    static let chromeApp = "/Applications/Google Chrome.app/Contents"
    static let chromeHelpers = chromeApp + "/Frameworks/Google Chrome Framework.framework/Versions/153.0.8010.36/Helpers"
    static let testingApp = "/Users/me/.agent-browser/browsers/chrome-153.0.8010.36/Google Chrome for Testing.app/Contents"
    static let testingHelpers = testingApp + "/Frameworks/Google Chrome for Testing Framework.framework/Versions/153.0.8010.36/Helpers"

    static func record(_ pid: Int32, parent: Int32?, _ executablePath: String, _ arguments: String) -> ProcessRecord {
        ProcessRecord(
            pid: pid,
            parentPID: parent,
            startTime: Date(timeIntervalSince1970: 1_000 + TimeInterval(pid)),
            executablePath: executablePath,
            commandLine: arguments.isEmpty ? executablePath : executablePath + " " + arguments
        )
    }

    static let agentBrowserDaemon = record(600, parent: 1, "/opt/homebrew/Cellar/agent-browser/0.43.0/libexec/bin/agent-browser", "")

    static let realWorldTable: [ProcessRecord] = [
        // chrome-devtools-mcp: the npm wrapper, the Node server (its process title is rewritten), and the Chrome it drives.
        ProcessRecord(pid: 500, parentPID: 1, startTime: Date(timeIntervalSince1970: 1_500), executablePath: "/opt/homebrew/Cellar/node/25.0.0/bin/node", commandLine: "npm exec chrome-devtools-mcp@latest --isolated --headless"),
        ProcessRecord(pid: 501, parentPID: 500, startTime: Date(timeIntervalSince1970: 1_501), executablePath: "/opt/homebrew/bin/chrome-devtools-mcp", commandLine: "chrome-devtools-mcp"),
        record(502, parent: 501, chromeApp + "/MacOS/Google Chrome", "--allow-pre-commit-input --enable-automation --remote-debugging-pipe --user-data-dir=/Users/me/.cache/chrome-devtools-mcp/chrome-profile"),
        record(503, parent: 502, chromeHelpers + "/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper", "--type=utility --utility-sub-type=network.mojom.NetworkService --enable-automation"),
        record(504, parent: 502, chromeHelpers + "/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", "--type=renderer --enable-automation --remote-debugging-pipe"),
        record(505, parent: 502, chromeHelpers + "/chrome_crashpad_handler", "--monitor-self"),
        // agent-browser: the daemon and its Chrome for Testing.
        agentBrowserDaemon,
        record(601, parent: 600, testingApp + "/MacOS/Google Chrome for Testing", "--headless=new --remote-debugging-port=0 --user-data-dir=/var/folders/xy/agent-browser-profile"),
        record(602, parent: 601, testingHelpers + "/Google Chrome for Testing Helper (GPU).app/Contents/MacOS/Google Chrome for Testing Helper (GPU)", "--type=gpu-process --headless=new --user-data-dir=/var/folders/xy/agent-browser-profile"),
        record(603, parent: 601, testingHelpers + "/Google Chrome for Testing Helper (Renderer).app/Contents/MacOS/Google Chrome for Testing Helper (Renderer)", "--type=renderer --headless=new --remote-debugging-port=0")
    ]
}

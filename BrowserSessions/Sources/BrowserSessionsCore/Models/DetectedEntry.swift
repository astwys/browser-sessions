import Foundation

public enum EntrySource: String, Sendable, Codable {
    case agentBrowser
    case process
}

public struct DetectedEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let source: EntrySource
    public let sessionName: String
    public let processIdentity: ProcessIdentity?
    public let confidence: ConfidenceTier?
    public let displayName: String
    public let commandLineSnippet: String?
    public let parentProcessSummary: String?
    public let signalReason: String?

    public init(
        id: String,
        source: EntrySource,
        sessionName: String,
        processIdentity: ProcessIdentity? = nil,
        confidence: ConfidenceTier? = nil,
        displayName: String? = nil,
        commandLineSnippet: String? = nil,
        parentProcessSummary: String? = nil,
        signalReason: String? = nil
    ) {
        self.id = id
        self.source = source
        self.sessionName = sessionName
        self.processIdentity = processIdentity
        self.confidence = confidence
        self.displayName = displayName ?? sessionName
        self.commandLineSnippet = commandLineSnippet
        self.parentProcessSummary = parentProcessSummary
        self.signalReason = signalReason
    }

    /// The program that started this browser, from its parent's command line: "zsh", "chrome-devtools-mcp",
    /// or for a script run by an interpreter, the script ("playwright" for `node …/.bin/playwright test`).
    public var launcherName: String? {
        let words = parentProcessSummary?.split(separator: " ").map(String.init) ?? []
        guard let first = words.first else { return nil }
        let program = URL(fileURLWithPath: first).lastPathComponent
        let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]
        if interpreters.contains(program), let script = words.dropFirst().first(where: { $0.hasPrefix("-") == false }) {
            return URL(fileURLWithPath: script).deletingPathExtension().lastPathComponent
        }
        return program
    }

    public var isClosable: Bool {
        source == .agentBrowser || confidence?.isClosable == true
    }

    public static func agentBrowserSession(
        name: String,
        processIdentity: ProcessIdentity? = nil,
        commandLineSnippet: String? = nil,
        parentProcessSummary: String? = nil,
        signalReason: String? = nil
    ) -> DetectedEntry {
        DetectedEntry(
            id: "agent-browser:\(name)",
            source: .agentBrowser,
            sessionName: name,
            processIdentity: processIdentity,
            displayName: name,
            commandLineSnippet: commandLineSnippet,
            parentProcessSummary: parentProcessSummary,
            signalReason: signalReason
        )
    }

    public static func process(
        identity: ProcessIdentity,
        confidence: ConfidenceTier,
        displayName: String,
        commandLineSnippet: String? = nil,
        parentProcessSummary: String? = nil,
        signalReason: String? = nil
    ) -> DetectedEntry {
        DetectedEntry(
            id: "pid:\(identity.pid)@\(identity.startTime.timeIntervalSince1970)",
            source: .process,
            sessionName: "pid:\(identity.pid)",
            processIdentity: identity,
            confidence: confidence,
            displayName: displayName,
            commandLineSnippet: commandLineSnippet,
            parentProcessSummary: parentProcessSummary,
            signalReason: signalReason ?? identity.signalTokens.joined(separator: ", ")
        )
    }
}

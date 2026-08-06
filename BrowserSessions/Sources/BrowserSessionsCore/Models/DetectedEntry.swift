import CryptoKit
import Foundation

public enum EntrySource: String, Sendable, Codable {
    case agentBrowser
    case process
}

public struct DetectedEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let source: EntrySource
    public let sessionName: String
    public let url: String?
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
        url: String? = nil,
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
        self.url = url
        self.processIdentity = processIdentity
        self.confidence = confidence
        self.displayName = displayName ?? sessionName
        self.commandLineSnippet = commandLineSnippet
        self.parentProcessSummary = parentProcessSummary
        self.signalReason = signalReason
    }

    public var isClosable: Bool {
        source == .agentBrowser || confidence?.isClosable == true
    }

    public static func agentBrowserSession(
        name: String,
        url: String? = nil,
        processIdentity: ProcessIdentity? = nil,
        commandLineSnippet: String? = nil,
        parentProcessSummary: String? = nil,
        signalReason: String? = nil
    ) -> DetectedEntry {
        DetectedEntry(
            id: stableID(source: .agentBrowser, sessionName: name),
            source: .agentBrowser,
            sessionName: name,
            url: URLSanitizer.displayString(for: url),
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
        let signalHash = identity.signalTokens.joined(separator: ",")
        let id = stableProcessID(pid: identity.pid, startTime: identity.startTime, signalHash: signalHash)
        return DetectedEntry(
            id: id,
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

    public static func stableID(source: EntrySource, sessionName: String) -> String {
        let input = source.rawValue + sessionName
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func stableProcessID(pid: Int32, startTime: Date, signalHash: String) -> String {
        let input = "pid:\(pid)\(startTime.timeIntervalSince1970)\(signalHash)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

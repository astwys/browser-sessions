import CryptoKit
import Foundation

public enum EntrySource: String, Sendable, Codable {
    case agentBrowser
}

public struct DetectedEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let source: EntrySource
    public let sessionName: String
    public let url: String?

    public init(id: String, source: EntrySource, sessionName: String, url: String? = nil) {
        self.id = id
        self.source = source
        self.sessionName = sessionName
        self.url = url
    }

    public static func agentBrowserSession(name: String, url: String? = nil) -> DetectedEntry {
        DetectedEntry(
            id: stableID(source: .agentBrowser, sessionName: name),
            source: .agentBrowser,
            sessionName: name,
            url: url
        )
    }

    public static func stableID(source: EntrySource, sessionName: String) -> String {
        let input = source.rawValue + sessionName
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

public struct AgentBrowserProcessMetadata: Equatable, Sendable {
    public let sessionName: String
    public let agentPID: Int32
    public let engine: String?
    public let version: String?
    public let streamPort: String?
    public let browserIdentity: ProcessIdentity?
    public let browserCommandLineSnippet: String?
    public let agentProcessSummary: String?

    public init(
        sessionName: String,
        agentPID: Int32,
        engine: String? = nil,
        version: String? = nil,
        streamPort: String? = nil,
        browserIdentity: ProcessIdentity? = nil,
        browserCommandLineSnippet: String? = nil,
        agentProcessSummary: String? = nil
    ) {
        self.sessionName = sessionName
        self.agentPID = agentPID
        self.engine = engine
        self.version = version
        self.streamPort = streamPort
        self.browserIdentity = browserIdentity
        self.browserCommandLineSnippet = browserCommandLineSnippet
        self.agentProcessSummary = agentProcessSummary
    }
}

public protocol AgentBrowserProcessResolving: Sendable {
    func metadata(for sessionNames: [String], records: [ProcessRecord]) -> [String: AgentBrowserProcessMetadata]
}

/// Links each agent-browser session to its daemon and browser processes through the daemon's
/// state files in `~/.agent-browser`.
public struct AgentBrowserProcessResolver: AgentBrowserProcessResolving, Sendable {
    private let stateDirectory: URL

    public init(
        stateDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-browser")
    ) {
        self.stateDirectory = stateDirectory
    }

    public func metadata(for sessionNames: [String], records: [ProcessRecord]) -> [String: AgentBrowserProcessMetadata] {
        guard sessionNames.isEmpty == false else { return [:] }
        let recordsByPID = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let childrenByParent = Dictionary(grouping: records, by: { $0.parentPID ?? -1 })
        var resolved: [String: AgentBrowserProcessMetadata] = [:]

        for sessionName in sessionNames {
            guard let agentPID = readString(sessionName: sessionName, suffix: "pid").flatMap(Int32.init) else { continue }
            let agentRecord = recordsByPID[agentPID]
            let browser = childrenByParent[agentPID, default: []].lazy.compactMap { record in
                AutomationSignalClassifier.classify(
                    executablePath: record.executablePath,
                    commandLine: record.commandLine,
                    parentCommandLine: agentRecord?.commandLine
                ).map { (record, $0) }
            }.first
            let browserIdentity = browser.map { record, classification in
                ProcessIdentity(
                    pid: record.pid,
                    parentPID: record.parentPID,
                    startTime: record.startTime,
                    executablePath: record.executablePath,
                    commandLine: record.commandLine,
                    signalTokens: classification.signalTokens
                )
            }

            resolved[sessionName] = AgentBrowserProcessMetadata(
                sessionName: sessionName,
                agentPID: agentPID,
                engine: readString(sessionName: sessionName, suffix: "engine"),
                version: readString(sessionName: sessionName, suffix: "version"),
                streamPort: readString(sessionName: sessionName, suffix: "stream"),
                browserIdentity: browserIdentity,
                browserCommandLineSnippet: browser.map { URLSanitizer.sanitizedCommandLineSnippet($0.0.commandLine) },
                agentProcessSummary: agentRecord.map { URLSanitizer.sanitizedCommandLineSnippet($0.commandLine, maxLength: 80) }
            )
        }

        return resolved
    }

    private func readString(sessionName: String, suffix: String) -> String? {
        guard isSafeSessionName(sessionName) else { return nil }
        let file = "\(sessionName).\(suffix)"
        let value = try? String(contentsOf: stateDirectory.appendingPathComponent(file), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func isSafeSessionName(_ sessionName: String) -> Bool {
        sessionName.isEmpty == false
            && sessionName.contains("/") == false
            && sessionName.contains("\\") == false
            && sessionName.contains("..") == false
    }
}

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
    func metadata(for sessionNames: [String]) async -> [String: AgentBrowserProcessMetadata]
    func metadata(for sessionNames: [String], records: [ProcessRecord]) async -> [String: AgentBrowserProcessMetadata]
}

public struct AgentBrowserProcessResolver: AgentBrowserProcessResolving, Sendable {
    private let commandRunner: any CommandRunning
    private let stateDirectory: URL

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        stateDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-browser")
    ) {
        self.commandRunner = commandRunner
        self.stateDirectory = stateDirectory
    }

    public func metadata(for sessionNames: [String]) async -> [String: AgentBrowserProcessMetadata] {
        guard sessionNames.isEmpty == false else { return [:] }
        let result = await commandRunner.run(
            executable: "ps",
            arguments: ["-axo", "pid=,ppid=,lstart=,command=", "-ww"],
            timeout: .seconds(2)
        )
        guard result.succeeded else { return [:] }
        return await metadata(for: sessionNames, records: ProcessArguments.parsePSOutput(result.stdout))
    }

    public func metadata(for sessionNames: [String], records: [ProcessRecord]) async -> [String: AgentBrowserProcessMetadata] {
        guard sessionNames.isEmpty == false else { return [:] }
        let recordsByPID = Dictionary(uniqueKeysWithValues: records.map { ($0.pid, $0) })
        let childrenByParent = Dictionary(grouping: records, by: { $0.parentPID ?? -1 })
        var resolved: [String: AgentBrowserProcessMetadata] = [:]

        for sessionName in sessionNames {
            guard let agentPID = readInt32(sessionName: sessionName, suffix: "pid") else { continue }
            let agentRecord = recordsByPID[agentPID]
            let browserRecord = childrenByParent[agentPID]?.first { record in
                AutomationSignalClassifier.classify(
                    executablePath: record.executablePath,
                    commandLine: record.commandLine,
                    parentCommandLine: agentRecord?.commandLine
                ) != nil
            }
            let classification = browserRecord.flatMap { record in
                AutomationSignalClassifier.classify(
                    executablePath: record.executablePath,
                    commandLine: record.commandLine,
                    parentCommandLine: agentRecord?.commandLine
                )
            }
            let browserIdentity = browserRecord.map { record in
                ProcessIdentity(
                    pid: record.pid,
                    parentPID: record.parentPID,
                    startTime: record.startTime,
                    executablePath: record.executablePath,
                    commandLine: record.commandLine,
                    signalTokens: classification?.signalTokens ?? ["agent-browser"]
                )
            }

            resolved[sessionName] = AgentBrowserProcessMetadata(
                sessionName: sessionName,
                agentPID: agentPID,
                engine: readString(sessionName: sessionName, suffix: "engine"),
                version: readString(sessionName: sessionName, suffix: "version"),
                streamPort: readString(sessionName: sessionName, suffix: "stream"),
                browserIdentity: browserIdentity,
                browserCommandLineSnippet: browserRecord.map { URLSanitizer.sanitizedCommandLineSnippet($0.commandLine) },
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

    private func readInt32(sessionName: String, suffix: String) -> Int32? {
        readString(sessionName: sessionName, suffix: suffix).flatMap(Int32.init)
    }

    private func isSafeSessionName(_ sessionName: String) -> Bool {
        sessionName.isEmpty == false
            && sessionName.contains("/") == false
            && sessionName.contains("\\") == false
            && sessionName.contains("..") == false
    }
}

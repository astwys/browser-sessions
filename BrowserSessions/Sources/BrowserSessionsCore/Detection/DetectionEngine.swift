import Foundation

public struct DetectionEngine: Sendable {
    private let agentBrowserClient: any AgentBrowserClientProtocol
    private let listProcesses: @Sendable () -> [ProcessRecord]
    private let agentBrowserProcessResolver: any AgentBrowserProcessResolving

    public init(
        agentBrowserClient: any AgentBrowserClientProtocol = AgentBrowserClient(),
        listProcesses: @escaping @Sendable () -> [ProcessRecord] = ProcessTable.all,
        agentBrowserProcessResolver: any AgentBrowserProcessResolving = AgentBrowserProcessResolver()
    ) {
        self.agentBrowserClient = agentBrowserClient
        self.listProcesses = listProcesses
        self.agentBrowserProcessResolver = agentBrowserProcessResolver
    }

    public func snapshot() async -> DetectionSnapshot {
        let agentResult = await agentBrowserClient.listSessions()
        // Read processes after the session list so every listed session's browser has had time to appear.
        let records = listProcesses()
        let processes = ProcessScanner.entries(from: records)
        let (knownSessions, degradedReason): ([DetectedEntry], String?)
        switch agentResult {
        case .available(let entries):
            // Never call `agent-browser --session <name> get url` while polling: since 0.28.0 it can
            // recreate a closed session as about:blank, which makes Close look ineffective.
            let metadata = agentBrowserProcessResolver.metadata(for: entries.map(\.sessionName), records: records)
            knownSessions = Self.enrichKnownSessions(entries, metadata: metadata)
            degradedReason = nil
        case .unavailable(let reason):
            knownSessions = []
            degradedReason = reason
        case .error(let message):
            knownSessions = []
            degradedReason = message
        }

        let merged = Self.merge(knownSessions: knownSessions, processEntries: processes)
        return DetectionSnapshot(entries: merged, degradedReason: degradedReason, lastUpdated: Date())
    }

    public static func merge(knownSessions: [DetectedEntry], processEntries: [DetectedEntry]) -> [DetectedEntry] {
        let knownBrowserPIDs = Set(knownSessions.compactMap { $0.processIdentity?.pid })
        let deduplicatedProcesses = processEntries.filter { entry in
            guard let pid = entry.processIdentity?.pid else { return true }
            return knownBrowserPIDs.contains(pid) == false
        }
        var seen = Set<String>()
        var merged: [DetectedEntry] = []
        for entry in knownSessions + deduplicatedProcesses {
            guard seen.insert(entry.id).inserted else { continue }
            merged.append(entry)
        }
        return merged.sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
            if lhs.confidence != rhs.confidence { return (lhs.confidence == .high) && (rhs.confidence != .high) }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func enrichKnownSessions(
        _ entries: [DetectedEntry],
        metadata: [String: AgentBrowserProcessMetadata]
    ) -> [DetectedEntry] {
        entries.map { entry in
            guard let sessionMetadata = metadata[entry.sessionName] else { return entry }
            var details: [String] = []
            if let engine = sessionMetadata.engine { details.append("engine \(engine)") }
            details.append("agent PID \(sessionMetadata.agentPID)")
            if let streamPort = sessionMetadata.streamPort { details.append("stream \(streamPort)") }
            return DetectedEntry.agentBrowserSession(
                name: entry.sessionName,
                processIdentity: sessionMetadata.browserIdentity,
                commandLineSnippet: sessionMetadata.browserCommandLineSnippet,
                parentProcessSummary: sessionMetadata.agentProcessSummary,
                signalReason: details.joined(separator: " · ")
            )
        }
    }
}

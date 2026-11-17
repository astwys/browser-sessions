import Foundation
import os

public struct DetectionEngine: Sendable {
    private let agentBrowserClient: any AgentBrowserClientProtocol
    private let listProcesses: @Sendable () -> [ProcessRecord]
    private let agentBrowserProcessResolver: any AgentBrowserProcessResolving
    /// The last session list and the agent-browser processes that were running when it was read.
    private let sessionCache = OSAllocatedUnfairLock<(daemons: [String], entries: [DetectedEntry])?>(initialState: nil)

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
        let records = listProcesses()
        let agentResult = await listSessions(daemons: Self.agentBrowserProcesses(in: records))
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
        return DetectionSnapshot(entries: merged, degradedReason: degradedReason)
    }

    /// Every agent-browser session is served by a running agent-browser daemon, so the CLI is asked only
    /// when that set of processes changes. With none running there are no sessions and nothing is spawned.
    private func listSessions(daemons: [String]) async -> AgentBrowserListResult {
        if daemons.isEmpty { return .available([]) }
        if let cached = sessionCache.withLock({ $0 }), cached.daemons == daemons {
            return .available(cached.entries)
        }
        let result = await agentBrowserClient.listSessions()
        if case .available(let entries) = result {
            sessionCache.withLock { $0 = (daemons, entries) }
        }
        return result
    }

    /// Identity of every running agent-browser process. Matches the native binary's names
    /// (`agent-browser`, `agent-browser-darwin-arm64`); a Node-hosted daemon would need its own rule.
    static func agentBrowserProcesses(in records: [ProcessRecord]) -> [String] {
        records
            .filter { ($0.executablePath as NSString).lastPathComponent.hasPrefix("agent-browser") }
            .map { "\($0.pid)@\($0.startTime.timeIntervalSince1970)" }
            .sorted()
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
            details.append("PID \(sessionMetadata.agentPID)")
            if let streamPort = sessionMetadata.streamPort { details.append("stream port \(streamPort)") }
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

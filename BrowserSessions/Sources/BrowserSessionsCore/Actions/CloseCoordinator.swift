import Foundation

public enum CloseOutcome: Equatable, Sendable {
    case success
    case notClosable
    case staleTarget
    case unavailable(String)
    case failed(String)
}

public struct CloseCoordinator: Sendable {
    private let agentBrowserClient: any AgentBrowserClientProtocol
    private let identityReader: any ProcessIdentityReading
    private let processKiller: any ProcessKilling

    public init(
        agentBrowserClient: any AgentBrowserClientProtocol = AgentBrowserClient(),
        identityReader: any ProcessIdentityReading = ProcessIdentityReader(),
        processKiller: any ProcessKilling = ProcessKiller()
    ) {
        self.agentBrowserClient = agentBrowserClient
        self.identityReader = identityReader
        self.processKiller = processKiller
    }

    public func close(_ entry: DetectedEntry) async -> CloseOutcome {
        switch entry.source {
        case .agentBrowser:
            return await closeKnownSession(entry)
        case .process:
            return await closeProcess(entry)
        }
    }

    private func closeKnownSession(_ entry: DetectedEntry) async -> CloseOutcome {
        switch await agentBrowserClient.closeSession(name: entry.sessionName) {
        case .success:
            // agent-browser can report close success before its session list/processes have settled.
            // Give the CLI a short grace period so the immediate UI refresh does not re-show
            // the just-closed session as if nothing happened.
            try? await Task.sleep(for: .milliseconds(750))
            return .success
        case .unavailable(let reason):
            return .unavailable(reason)
        case .error(let message):
            return .failed(message)
        }
    }

    private func closeProcess(_ entry: DetectedEntry) async -> CloseOutcome {
        guard entry.confidence == .high, let identity = entry.processIdentity else {
            return .notClosable
        }
        guard let current = identityReader.currentIdentity(pid: identity.pid), identity.matches(current: current) else {
            return .staleTarget
        }
        switch processKiller.terminate(pid: identity.pid) {
        case .success:
            return .success
        case .failed(let message):
            return .failed(message)
        }
    }
}

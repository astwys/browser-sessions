import Foundation

public enum AgentBrowserListResult: Equatable, Sendable {
    case available([DetectedEntry])
    case unavailable(reason: String)
    case error(message: String)
}

public enum AgentBrowserCloseResult: Equatable, Sendable {
    case success
    case unavailable(reason: String)
    case error(message: String)
}

public protocol AgentBrowserClientProtocol: Sendable {
    func listSessions() async -> AgentBrowserListResult
    func closeSession(name: String) async -> AgentBrowserCloseResult
}

public struct AgentBrowserClient: AgentBrowserClientProtocol, Sendable {
    private let commandRunner: any CommandRunning
    private let executable: String
    private let timeout: Duration

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        executable: String = "agent-browser",
        timeout: Duration = .seconds(2)
    ) {
        self.commandRunner = commandRunner
        self.executable = executable
        self.timeout = timeout
    }

    public func listSessions() async -> AgentBrowserListResult {
        let result = await commandRunner.run(
            executable: executable,
            arguments: ["session", "list", "--json"],
            timeout: timeout
        )
        if let unavailable = unavailableReason(from: result) {
            return .unavailable(reason: unavailable)
        }
        return parseListResponse(result.stdout)
    }

    public func closeSession(name: String) async -> AgentBrowserCloseResult {
        let result = await commandRunner.run(
            executable: executable,
            arguments: ["--session", name, "close", "--json"],
            timeout: timeout
        )
        if let unavailable = unavailableReason(from: result) {
            return .unavailable(reason: unavailable)
        }
        return parseCloseResponse(result.stdout)
    }

    private func unavailableReason(from result: CommandResult) -> String? {
        if result.timedOut {
            return "agent-browser timed out"
        }
        if result.exitCode == 127 {
            return "agent-browser not found on PATH"
        }
        if result.exitCode != 0 {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.localizedCaseInsensitiveContains("no such file")
                || detail.localizedCaseInsensitiveContains("not found") {
                return "agent-browser not found on PATH"
            }
            return detail.isEmpty ? "agent-browser exited with code \(result.exitCode)" : URLSanitizer.sanitizedUserVisibleMessage(detail)
        }
        return nil
    }

    private func parseListResponse(_ stdout: String) -> AgentBrowserListResult {
        guard let response = decode(SessionListResponse.self, from: stdout) else {
            return .error(message: "invalid session list JSON")
        }
        guard response.success else {
            return .error(message: response.error.map { URLSanitizer.sanitizedUserVisibleMessage($0) } ?? "session list failed")
        }
        let names = response.data?.sessions ?? []
        let entries = names.map { DetectedEntry.agentBrowserSession(name: $0) }
        return .available(entries)
    }

    private func parseCloseResponse(_ stdout: String) -> AgentBrowserCloseResult {
        guard let response = decode(CloseResponse.self, from: stdout) else {
            return .error(message: "invalid close JSON")
        }
        guard response.success, response.data?.closed == true else {
            return .error(message: response.error.map { URLSanitizer.sanitizedUserVisibleMessage($0) } ?? "close failed")
        }
        return .success
    }

    private func decode<T: Decodable>(_ type: T.Type, from stdout: String) -> T? {
        let data = Data(stdout.utf8)
        return try? JSONDecoder().decode(type, from: data)
    }
}

private struct SessionListResponse: Decodable {
    let success: Bool
    let data: SessionListData?
    let error: String?
}

private struct SessionListData: Decodable {
    let sessions: [String]
}

private struct CloseResponse: Decodable {
    let success: Bool
    let data: CloseData?
    let error: String?
}

private struct CloseData: Decodable {
    let closed: Bool
}

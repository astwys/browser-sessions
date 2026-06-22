import Foundation
import BrowserSessionsCore

struct MockCommandRunner: CommandRunning {
    let handler: @Sendable (String, [String]) -> CommandResult

    func run(executable: String, arguments: [String], timeout: Duration) async -> CommandResult {
        handler(executable, arguments)
    }
}

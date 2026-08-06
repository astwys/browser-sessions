import Foundation
import BrowserSessionsCore

@MainActor
func runURLSanitizerTests(_ harness: inout TestHarness) {
    testCommandLineRedactsSplitSecretFlags(&harness)
    testCommandLineRedactsBearerAndCookieValues(&harness)
    testUserVisibleMessageIsSanitizedAndBounded(&harness)
}

@MainActor
private func testCommandLineRedactsSplitSecretFlags(_ harness: inout TestHarness) {
    let snippet = URLSanitizer.sanitizedCommandLineSnippet("chrome --token abc123 --client-secret super-secret --user-data-dir=/tmp/profile", maxLength: 200)
    harness.expect(snippet.contains("abc123") == false, "split token value redacted")
    harness.expect(snippet.contains("super-secret") == false, "split client secret redacted")
    harness.expect(snippet.contains("--token <redacted>"), "token placeholder shown")
}

@MainActor
private func testCommandLineRedactsBearerAndCookieValues(_ harness: inout TestHarness) {
    let snippet = URLSanitizer.sanitizedCommandLineSnippet("curl -H 'Authorization: Bearer abc.def' -H 'Cookie: sessionid=secret'", maxLength: 200)
    harness.expect(snippet.localizedCaseInsensitiveContains("abc.def") == false, "bearer value redacted")
    harness.expect(snippet.localizedCaseInsensitiveContains("sessionid=secret") == false, "cookie value redacted")
}

@MainActor
private func testUserVisibleMessageIsSanitizedAndBounded(_ harness: inout TestHarness) {
    let message = URLSanitizer.sanitizedUserVisibleMessage("failed with --password swordfish at https://example.com/path?token=abc", maxLength: 80)
    harness.expect(message.contains("swordfish") == false, "stderr password redacted")
    harness.expect(message.contains("token=abc") == false, "stderr URL query redacted")
    harness.expect(message.count <= 80, "stderr message bounded")
}

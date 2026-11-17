import Foundation
import BrowserSessionsCore

@MainActor
func runURLSanitizerTests(_ harness: inout TestHarness) {
    testCommandLineRedactsSplitSecretFlags(&harness)
    testCommandLineRedactsBearerAndCookieValues(&harness)
    testUserVisibleMessageIsSanitizedAndBounded(&harness)
    testCommandLineRedactsURLCredentialsAndBasicAuth(&harness)
    testRedactsLessCommonSecretForms(&harness)
    testRedactionKeepsWhatIdentifiesABrowser(&harness)
    testLongCommandLinesStayFast(&harness)
}

@MainActor
private func testCommandLineRedactsURLCredentialsAndBasicAuth(_ harness: inout TestHarness) {
    let snippet = URLSanitizer.sanitizedCommandLineSnippet("chrome --proxy-server=http://alice:s3cret@proxy.local:8080 -H 'Authorization: Basic YWxpY2U6czNjcmV0'", maxLength: 200)
    harness.expect(snippet.contains("s3cret") == false, "URL userinfo password redacted")
    harness.expect(snippet.contains("YWxpY2U6czNjcmV0") == false, "basic auth value redacted")
    harness.expect(snippet.contains("proxy.local:8080"), "proxy host stays visible")
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

@MainActor
private func testRedactsLessCommonSecretForms(_ harness: inout TestHarness) {
    func sanitized(_ value: String) -> String { URLSanitizer.sanitizedCommandLineSnippet(value, maxLength: 400) }
    harness.expectEqual(sanitized("chrome --proxy-server=HTTPS://alice:pa/ss@w0rd@proxy.local:8080"), "chrome --proxy-server=HTTPS://<redacted>@proxy.local:8080", "userinfo redacted for any scheme case and up to the last @")
    // Quotes never reach a command line: it is argv joined by spaces.
    harness.expectEqual(sanitized("curl -H X-Api-Key: k1 -H Authorization: Token t1 -H Authorization: raw1 https://api.example/x"), "curl -H X-Api-Key: <redacted> -H Authorization: Token <redacted> -H Authorization: <redacted> https://api.example/x", "API key header and authorization with or without a scheme redacted")
    harness.expectEqual(sanitized("chrome https://example.com/p?next=/a&email=a@b.com"), "chrome <url-with-query-redacted>", "an @ in a query is not read as userinfo")
    harness.expectEqual(sanitized("tool --auth a1 --key=k2 --secret-access-key=s3"), "tool --auth <redacted> --key=<redacted> --secret-access-key=<redacted>", "flags ending in a secret word redacted")
    harness.expectEqual(sanitized("node ws.js wss://relay.example/socket?sig=abc"), "node ws.js <url-with-query-redacted>", "query redacted for non-http URLs")
    harness.expectEqual(sanitized("chrome --password-store=basic --use-mock-keychain --remote-debugging-port=0"), "chrome --password-store=basic --use-mock-keychain --remote-debugging-port=0", "flags that only contain a secret word stay readable")
}

@MainActor
private func testRedactionKeepsWhatIdentifiesABrowser(_ harness: inout TestHarness) {
    func sanitized(_ value: String) -> String { URLSanitizer.sanitizedCommandLineSnippet(value, maxLength: 400) }
    harness.expectEqual(sanitized("tool --password -s3cr3t https://ghp_abc@github.com/o/r"), "tool --password <redacted> https://<redacted>@github.com/o/r", "dash-led value and token-only userinfo redacted")
    harness.expectEqual(sanitized("java -Dspring.datasource.password=s1 --db.password=s2 --config.api_key=s3 redis://:s4@cache:6379 -H cookie:s5 -H X-Api-Key:s6"), "java -Dspring.datasource.password=<redacted> --db.password=<redacted> --config.api_key=<redacted> redis://<redacted>@cache:6379 -H cookie:<redacted> -H X-Api-Key:<redacted>", "dotted names, password-only userinfo and headers without a space redacted")
    let readable = "node https://www.npmjs.com/package/@playwright/test file:///p/.pnpm/@playwright+test@1.49.0/cli.js --user-data-dir=/tmp/my-auth profile monkey:443 --app=http://auth:3000/login"
    harness.expectEqual(sanitized(readable), readable, "@ in a path, a secret word inside a value, and host:port stay readable")
}

@MainActor
private func testLongCommandLinesStayFast(_ harness: inout TestHarness) {
    let hyphenated = String(repeating: "a-", count: 20_000)
    let base64url = String((0..<200_000).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".randomElement()! })
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        _ = URLSanitizer.sanitizedCommandLineSnippet("chrome --state=\(base64url)")
        _ = URLSanitizer.sanitizedCommandLineSnippet("chrome \(hyphenated) --token abc")
        _ = URLSanitizer.sanitizedCommandLineSnippet("chrome " + String(repeating: "a://", count: 250_000))
    }
    harness.expect(elapsed < .milliseconds(200), "long command lines are sanitized quickly (took \(elapsed))")
    // The 4096-character cut lands inside the password, before its @.
    let secretAtCut = String(repeating: "x ", count: 2_035) + "https://alice:hunter2hunter2hunter2@proxy.local"
    harness.expect(URLSanitizer.sanitizedUserVisibleMessage(secretAtCut, maxLength: 10_000).contains("hunter") == false, "a secret cut by the length bound never shows")
}

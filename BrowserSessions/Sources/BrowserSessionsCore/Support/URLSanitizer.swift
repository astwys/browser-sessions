import Foundation

public enum URLSanitizer {
    public static func sanitizedCommandLineSnippet(_ commandLine: String, maxLength: Int = 120) -> String {
        let redacted = sanitize(commandLine)
        if redacted.count <= maxLength { return redacted }
        return String(redacted.prefix(maxLength - 1)) + "…"
    }

    public static func sanitizedUserVisibleMessage(_ message: String, maxLength: Int = 160) -> String {
        let redacted = sanitize(message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.isEmpty == false else { return "command failed" }
        if redacted.count <= maxLength { return redacted }
        return String(redacted.prefix(maxLength - 1)) + "…"
    }

    /// Only the start of a value is ever shown, so only the start is sanitized: argv can be 1 MB, and this
    /// runs every poll. The cut drops the last, partial word, so a secret cut in half never shows.
    private static let sanitizedPrefixLength = 4096

    private static func sanitize(_ value: String) -> String {
        var redacted = value
        if redacted.count > sanitizedPrefixLength {
            let prefix = redacted.prefix(sanitizedPrefixLength)
            redacted = String(prefix[..<(prefix.lastIndex(where: \.isWhitespace) ?? prefix.startIndex)])
        }
        // Names and URLs match only where they start, never inside a word, so `--user-data-dir=/tmp/my-auth` is not
        // an `auth` flag. That also keeps most long tokens fast; the cut above bounds the rest.
        // A name may follow a dot: `-Dspring.datasource.password=…`.
        let nameStart = #"(?<![\w-])"#
        // A name counts as secret when it ends in one of these words: `--secret-access-key`, `X-Api-Key`,
        // `--auth`. Ending, not containing, so `--password-store=basic` and `--use-mock-keychain` stay readable.
        let secretName = #"[\w-]*(?:token|secret|password|passwd|pwd|key|auth|cookie|credentials?|signature)"#
        let scheme = #"(?<![\w.+-])[a-z][a-z0-9+.-]*://"#
        let replacements = [
            // A user, then optionally `:` and a password up to the last @ before any query, so a password holding
            // `/` or `@`, or one with no user (`redis://:pw@host`), is covered. A path like
            // `npmjs.com/package/@playwright/test` holds no userinfo.
            (#"(?i)("# + scheme + #")[^\s/?#:@]*(?::[^\s?#]*)?@"#, "$1<redacted>@"),
            (#"(?i)"# + scheme + #"[^\s?#]+\?\S+"#, "<url-with-query-redacted>"),
            (#"(?i)("# + nameStart + secretName + #")=\S+"#, "$1=<redacted>"),
            (#"(?i)("# + nameStart + "--?" + secretName + #")\s+\S+"#, "$1 <redacted>"),
            // Command lines are argv joined by spaces, so the value is the word after a known scheme, or the next word.
            (#"(?i)(authorization:\s*(?:(?:bearer|basic|token|digest|negotiate)\s+)?)\S+"#, "$1<redacted>"),
            // A header, with or without a space after the colon. A number alone is a port (`monkey:443`), and
            // nothing after a `/` is a header (`http://auth:3000/login`).
            (#"(?i)(?<!/)("# + nameStart + secretName + #":\s*)(?!\d+(?:\s|$))\S+"#, "$1<redacted>")
        ]
        for (pattern, replacement) in replacements {
            redacted = redacted.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return redacted
    }
}

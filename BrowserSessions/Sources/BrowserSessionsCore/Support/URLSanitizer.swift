import Foundation

public enum URLSanitizer {
    public static func displayString(for rawValue: String?) -> String? {
        guard let rawValue, rawValue.isEmpty == false else { return nil }
        if let url = URL(string: rawValue), let host = url.host(percentEncoded: false) {
            return host
        }
        return rawValue.components(separatedBy: "?").first?.components(separatedBy: "#").first
    }

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

    private static func sanitize(_ value: String) -> String {
        var redacted = value
        let replacements = [
            (#"https?://[^\s?#]+\?[^\s]+"#, "<url-with-query-redacted>"),
            (#"(?i)(token|secret|password|passwd|pwd|api[-_]?key|client[-_]?secret|access[-_]?token|auth[-_]?token|session[-_]?token|cookie)=\S+"#, "$1=<redacted>"),
            (#"(?i)(--?(?:token|secret|password|passwd|pwd|api[-_]?key|client[-_]?secret|access[-_]?token|auth[-_]?token|cookie))\s+\S+"#, "$1 <redacted>"),
            (#"(?i)(authorization:\s*bearer\s+)\S+"#, "$1<redacted>"),
            (#"(?i)(cookie:\s*)\S+"#, "$1<redacted>")
        ]
        for (pattern, replacement) in replacements {
            redacted = redacted.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return redacted
    }
}

import SwiftUI

public struct PermissionsOnboardingView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browser Sessions")
                .font(.title2.weight(.semibold))
            Text("Lists the automation browsers running on this Mac and lets you close them.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                OnboardingRow(
                    title: "What it reads",
                    detail: "The names and arguments of your own processes, to find browsers started by Playwright, Puppeteer or agent-browser. It never reads their environment variables."
                )
                OnboardingRow(
                    title: "agent-browser",
                    detail: "When an agent-browser daemon starts or stops, the app runs agent-browser session list. Closing a session runs agent-browser close. Both give up after 2 seconds."
                )
                OnboardingRow(
                    title: "No page titles or URLs",
                    detail: "The app doesn't ask for Accessibility access, so it can't show which page a Playwright or Puppeteer browser has open."
                )
                OnboardingRow(
                    title: "What Close does",
                    detail: "Close appears only for agent-browser sessions and browsers with Playwright or Puppeteer flags. Before sending SIGTERM, the app checks that the PID still belongs to the same browser. The Node process that launched it keeps running."
                )
            }

            Text("Nothing is saved to disk. Tokens, passwords and URL query strings are masked in the arguments the app shows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }
}

private struct OnboardingRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import SwiftUI

public struct PermissionsOnboardingView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browser Sessions")
                .font(.title2.weight(.semibold))
            Text("This app supervises local automation browsers from the menu bar.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                OnboardingRow(
                    title: "Local process inspection",
                    detail: "Browser Sessions reads same-user process names and command lines to find Chrome/Chromium automation signals."
                )
                OnboardingRow(
                    title: "agent-browser CLI",
                    detail: "While an agent-browser daemon is running, the app runs agent-browser session list --json when the daemons change, and close when you ask, each with a short timeout."
                )
                OnboardingRow(
                    title: "No Accessibility access in v1",
                    detail: "Playwright/Puppeteer URL and title metadata may be unknown. Accessibility and CDP metadata readers are deferred."
                )
                OnboardingRow(
                    title: "Safe close behavior",
                    detail: "Close is shown only for known sessions and high-confidence process rows. PID kills are identity-revalidated first and target the browser PID only."
                )
            }

            Text("The app does not persist URLs or command-line secrets.")
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

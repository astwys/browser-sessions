import AppKit
import SwiftUI

public struct PopoverShellView: View {
    public let snapshot: DetectionSnapshot
    public let lastUpdated: Date
    public let isRefreshing: Bool
    private let closeCoordinator: CloseCoordinator
    private let onCloseCompleted: @Sendable () async -> Void
    private let onRefresh: @Sendable () async -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    @State private var pendingCloseEntry: DetectedEntry?
    @State private var closeStatusMessage: String?
    @State private var entriesContentHeight: CGFloat = 220

    public init(
        snapshot: DetectionSnapshot,
        lastUpdated: Date = Date(),
        isRefreshing: Bool = false,
        closeCoordinator: CloseCoordinator = CloseCoordinator(),
        onCloseCompleted: @escaping @Sendable () async -> Void = {},
        onRefresh: @escaping @Sendable () async -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.lastUpdated = lastUpdated
        self.isRefreshing = isRefreshing
        self.closeCoordinator = closeCoordinator
        self.onCloseCompleted = onCloseCompleted
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let degradedReason = snapshot.degradedReason {
                DegradationBanner(reason: degradedReason)
            }
            if let closeStatusMessage {
                StatusBanner(message: closeStatusMessage)
            }
            if let pendingCloseEntry {
                CloseConfirmationPanel(
                    entry: pendingCloseEntry,
                    title: confirmationTitle(for: pendingCloseEntry),
                    message: confirmationMessage(for: pendingCloseEntry),
                    confirmTitle: confirmationButtonTitle(for: pendingCloseEntry),
                    onConfirm: { Task { await performClose(pendingCloseEntry) } },
                    onCancel: { self.pendingCloseEntry = nil }
                )
            }
            if snapshot.totalCount == 0 {
                ZeroStateView()
            } else {
                entriesList
            }
            footer
        }
        .padding(14)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)
        .task(id: closeStatusMessage) {
            guard let message = closeStatusMessage else { return }
            try? await Task.sleep(for: .seconds(4))
            if closeStatusMessage == message {
                closeStatusMessage = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browser Sessions")
                    .font(.headline)
                Text(snapshot.totalCount == 0 ? "No automation browsers running" : "See every automation browser running locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if isRefreshing {
                    Text("Refreshing…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Text(lastUpdated, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Last updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack {
                Spacer()

                Button("Quit") {
                    onQuit()
                }
                .keyboardShortcut("q")
                .controlSize(.small)
                .accessibilityLabel("Quit Browser Sessions")
            }
        }
    }

    private var entriesList: some View {
        ScrollView {
            entriesContent
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: EntriesContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(height: popoverListHeight)
        .onPreferenceChange(EntriesContentHeightKey.self) { height in
            entriesContentHeight = height
        }
    }

    private var entriesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.knownSessions.isEmpty == false {
                EntrySection(title: "Known agent-browser sessions", entries: snapshot.knownSessions, onClose: queueClose)
            }
            if snapshot.highConfidenceProcesses.isEmpty == false {
                EntrySection(title: "Likely Playwright/Puppeteer browsers", entries: snapshot.highConfidenceProcesses, onClose: queueClose)
            }
            if snapshot.lowConfidenceProcesses.isEmpty == false {
                EntrySection(title: "Possible automation browsers", entries: snapshot.lowConfidenceProcesses, onClose: queueClose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var popoverListHeight: CGFloat {
        min(max(entriesContentHeight, 120), popoverListMaxHeight)
    }

    private var popoverListMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 1050
        return visibleHeight * 0.60
    }

    private func confirmationTitle(for entry: DetectedEntry) -> String {
        entry.source == .agentBrowser ? "Close agent-browser session?" : "Terminate browser process?"
    }

    private func queueClose(_ entry: DetectedEntry) {
        closeStatusMessage = nil
        pendingCloseEntry = entry
    }

    @MainActor
    private func performClose(_ entry: DetectedEntry) async {
        pendingCloseEntry = nil
        let outcome = await closeCoordinator.close(entry)
        closeStatusMessage = statusMessage(for: outcome, entry: entry)
        await onCloseCompleted()
    }

    private func statusMessage(for outcome: CloseOutcome, entry: DetectedEntry) -> String {
        switch outcome {
        case .success:
            return "Closed \(entry.displayName)."
        case .notClosable:
            return "This row is inspect-only and cannot be closed."
        case .staleTarget:
            return "The target changed or disappeared before close; no action was taken."
        case .unavailable(let reason):
            return "Close unavailable: \(reason)"
        case .failed(let message):
            return "Close failed: \(message)"
        }
    }

    private func confirmationButtonTitle(for entry: DetectedEntry) -> String {
        entry.source == .agentBrowser ? "Close Session" : "Terminate PID \(entry.processIdentity?.pid ?? 0)"
    }

    private func confirmationMessage(for entry: DetectedEntry) -> String {
        switch entry.source {
        case .agentBrowser:
            return "This will ask agent-browser to close the \(entry.sessionName) session."
        case .process:
            if let pid = entry.processIdentity?.pid {
                return "This sends SIGTERM to browser PID \(pid) only. The app will revalidate PID identity before terminating."
            }
            return "This sends SIGTERM to the browser process only after identity revalidation."
        }
    }
}

private struct EntriesContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 220

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CloseConfirmationPanel: View {
    let entry: DetectedEntry
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive) {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.20))
        )
        .accessibilityElement(children: .contain)
    }
}

private struct EntrySection: View {
    let title: String
    let entries: [DetectedEntry]
    let onClose: (DetectedEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                EntryRowView(entry: entry, onClose: onClose)
            }
        }
    }
}

public struct EntryRowView: View {
    public let entry: DetectedEntry
    private let onClose: (DetectedEntry) -> Void
    @State private var isExpanded = false

    public init(entry: DetectedEntry, onClose: @escaping (DetectedEntry) -> Void = { _ in }) {
        self.entry = entry
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                compactRow
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary.opacity(isExpanded ? 0.8 : 0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 10) {
            sourceAnchor
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    confidenceBadge
                }
                compactMetadata
            }

            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var sourceAnchor: some View {
        Text(anchorText)
            .font(.callout.monospacedDigit().weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var anchorText: String {
        switch entry.source {
        case .agentBrowser:
            return "agent"
        case .process:
            if let pid = entry.processIdentity?.pid { return "#\(pid)" }
            return entry.confidence == .high ? "high" : "low"
        }
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        switch entry.source {
        case .agentBrowser:
            EmptyView()
        case .process:
            Text(entry.confidence == .high ? "high" : "inspect only")
                .badgeStyle(tint: entry.confidence == .high ? .orange : .gray)
        }
    }

    private var compactMetadata: some View {
        HStack(spacing: 8) {
            if let parentProcessSummary = entry.parentProcessSummary {
                Label(parentProcessSummary, systemImage: "terminal")
                    .lineLimit(1)
            } else if entry.source == .agentBrowser {
                Label("managed session", systemImage: "globe")
                    .lineLimit(1)
            }

            if let identity = entry.processIdentity {
                Label(relativeAge(since: identity.startTime), systemImage: "clock")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.leading, 74)

            VStack(alignment: .leading, spacing: 6) {
                detailGrid
                if let commandLineSnippet = entry.commandLineSnippet {
                    Text(commandLineSnippet)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
            .padding(.leading, 74)
            .padding(.trailing, 10)

            HStack(spacing: 8) {
                Text(safetyCopy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if entry.isClosable {
                    Button("Close…", role: .destructive) {
                        onClose(entry)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Close \(entry.displayName)")
                }
            }
            .padding(.leading, 74)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var detailGrid: some View {
        if entry.source == .agentBrowser {
            DetailRow(label: "Session", value: entry.sessionName)
            DetailRow(label: "Manager", value: "agent-browser")
            if let signalReason = entry.signalReason, signalReason.isEmpty == false {
                DetailRow(label: "Runtime", value: signalReason)
            }
            if let parentProcessSummary = entry.parentProcessSummary {
                DetailRow(label: "Agent", value: parentProcessSummary)
            }
            if let identity = entry.processIdentity {
                DetailRow(label: "Browser PID", value: "\(identity.pid)")
                DetailRow(label: "Started", value: identity.startTime == .distantPast ? "unknown" : identity.startTime.formatted(date: .abbreviated, time: .standard))
                DetailRow(label: "Age", value: relativeAge(since: identity.startTime))
                DetailRow(label: "Executable", value: identity.executableBasename)
            }
            DetailRow(label: "Close", value: "Uses agent-browser session close")
        } else if let identity = entry.processIdentity {
            DetailRow(label: "PID", value: "\(identity.pid)")
            DetailRow(label: "Started", value: identity.startTime == .distantPast ? "unknown" : identity.startTime.formatted(date: .abbreviated, time: .standard))
            DetailRow(label: "Age", value: relativeAge(since: identity.startTime))
            DetailRow(label: "Confidence", value: entry.confidence == .high ? "high — close allowed" : "low — inspect only")
            if let parentProcessSummary = entry.parentProcessSummary {
                DetailRow(label: "Parent", value: parentProcessSummary)
            }
            if let signalReason = entry.signalReason, signalReason.isEmpty == false {
                DetailRow(label: "Signal", value: signalReason)
            }
            DetailRow(label: "Executable", value: identity.executableBasename)
            DetailRow(label: "Close", value: entry.isClosable ? "Sends SIGTERM to browser PID after identity revalidation" : "Disabled for low-confidence process rows")
        }
    }

    private var safetyCopy: String {
        if entry.source == .agentBrowser {
            return "Asks agent-browser to close this session."
        }
        if entry.isClosable {
            return "Close targets browser PID only and revalidates first."
        }
        return "Inspect-only: low-confidence rows cannot be closed."
    }

    private func relativeAge(since date: Date) -> String {
        guard date != .distantPast else { return "unknown" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    private var color: Color {
        switch entry.source {
        case .agentBrowser: return .accentColor
        case .process: return entry.confidence == .high ? .orange : .gray
        }
    }

    private var accessibilityLabel: String {
        var parts = [entry.displayName]
        switch entry.source {
        case .agentBrowser:
            parts.append("known agent-browser session")
        case .process:
            parts.append(entry.confidence == .high ? "high confidence process" : "inspect-only possible automation process")
            if let pid = entry.processIdentity?.pid { parts.append("PID \(pid)") }
        }
        if entry.isClosable { parts.append("closable") } else { parts.append("no close action") }
        return parts.joined(separator: ", ")
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct DegradationBanner: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Reduced detection capability: \(reason)")
    }
}

private struct StatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(message)
    }
}

public struct ZeroStateView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No automation browsers detected")
                .font(.headline)
            Text("Polling continues in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private extension Text {
    func badgeStyle(tint: Color = .secondary) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

import AppKit
import SwiftUI

public struct PopoverShellView: View {
    public let snapshot: DetectionSnapshot
    public let lastUpdated: Date
    public let isRefreshing: Bool
    private let closeCoordinator: CloseCoordinator
    private let onCloseCompleted: @Sendable () async -> Void
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
        onQuit: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.lastUpdated = lastUpdated
        self.isRefreshing = isRefreshing
        self.closeCoordinator = closeCoordinator
        self.onCloseCompleted = onCloseCompleted
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
            Text("Browser Sessions")
                .font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if isRefreshing {
                    Text("Refreshing…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Text("Updated \(lastUpdated, style: .time)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Last updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
            }
        }
        .padding(.horizontal, 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack {
                Spacer()

                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
                .accessibilityLabel("Quit Browser Sessions")
            }
        }
    }

    private var entriesList: some View {
        // Measured with onGeometryChange: a preference set inside a macOS ScrollView never reaches
        // the outside, which left the list stuck at its initial height.
        ScrollView {
            entriesContent
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { entriesContentHeight = $0 }
        }
        .frame(height: popoverListHeight)
    }

    private var entriesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.knownSessions.isEmpty == false {
                EntrySection(title: "agent-browser sessions", entries: snapshot.knownSessions, onClose: queueClose)
            }
            if snapshot.highConfidenceProcesses.isEmpty == false {
                EntrySection(title: "Playwright and Puppeteer browsers", entries: snapshot.highConfidenceProcesses, onClose: queueClose)
            }
            if snapshot.lowConfidenceProcesses.isEmpty == false {
                EntrySection(title: "Unconfirmed browsers", entries: snapshot.lowConfidenceProcesses, onClose: queueClose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var popoverListHeight: CGFloat {
        min(entriesContentHeight, popoverListMaxHeight)
    }

    private var popoverListMaxHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 1050
        return visibleHeight * 0.60
    }

    private func confirmationTitle(for entry: DetectedEntry) -> String {
        entry.source == .agentBrowser ? "Close the \(entry.sessionName) session?" : "Close \(entry.displayName)?"
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
            return "This browser can't be closed from here."
        case .staleTarget:
            return "The browser exited or its PID now belongs to another process. Nothing was closed."
        case .unavailable(let reason):
            return "Couldn't close: \(reason)"
        case .failed(let message):
            return "Couldn't close: \(message)"
        }
    }

    private func confirmationButtonTitle(for entry: DetectedEntry) -> String {
        entry.source == .agentBrowser ? "Close Session" : "Close Browser"
    }

    private func confirmationMessage(for entry: DetectedEntry) -> String {
        switch entry.source {
        case .agentBrowser:
            return "agent-browser closes the browser and ends the session."
        case .process:
            if let pid = entry.processIdentity?.pid {
                return "Sends SIGTERM to PID \(pid) after checking that the PID still belongs to this browser. The process that launched it keeps running."
            }
            return "Sends SIGTERM after checking that the PID still belongs to this browser. The process that launched it keeps running."
        }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
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
    @State private var isHovered = false

    public init(entry: DetectedEntry, onClose: @escaping (DetectedEntry) -> Void = { _ in }) {
        self.entry = entry
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactRow
            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(isExpanded ? 0.6 : isHovered ? 0.4 : 0))
        )
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
    }

    private var compactRow: some View {
        HStack(spacing: 6) {
            Button(action: toggleExpanded) {
                HStack(spacing: 10) {
                    BrowserIcon(executablePath: entry.processIdentity?.executablePath)
                        .opacity(entry.isClosable ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.displayName)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if entry.isClosable == false {
                                Text("view only")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")
            .accessibilityActions {
                if entry.isClosable {
                    Button("Close") { onClose(entry) }
                }
            }

            if entry.isClosable {
                // Shown on hover or while expanded, like the close buttons in Notification Center.
                // A hidden button leaves the accessibility tree, so VoiceOver gets Close as a row action.
                Button {
                    onClose(entry)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close \(entry.displayName)")
                .accessibilityLabel("Close \(entry.displayName)")
                .opacity(showsClose ? 1 : 0)
                .allowsHitTesting(showsClose)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleExpanded)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var showsClose: Bool {
        isHovered || isExpanded
    }

    private func toggleExpanded() {
        withAnimation(.snappy(duration: 0.16)) {
            isExpanded.toggle()
        }
    }

    /// "playwright · 13m": what started the browser and how long ago. The full command is in the details.
    private var subtitle: String {
        let launcher = entry.launcherName ?? (entry.source == .agentBrowser ? "agent-browser" : nil)
        let age = entry.processIdentity.map { relativeAge(since: $0.startTime) }
        return [launcher, age].compactMap { $0 }.joined(separator: " · ")
    }

    /// Indented to line up with the row's text, past the 28 pt icon.
    private var expandedDetails: some View {
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
            Text(safetyCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.leading, 46)
        .padding(.trailing, 10)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var detailGrid: some View {
        if entry.source == .agentBrowser {
            DetailRow(label: "Session", value: entry.sessionName)
            if let signalReason = entry.signalReason, signalReason.isEmpty == false {
                DetailRow(label: "Daemon", value: signalReason)
            }
            if let parentProcessSummary = entry.parentProcessSummary {
                DetailRow(label: "Command", value: parentProcessSummary)
            }
            if let identity = entry.processIdentity {
                DetailRow(label: "Browser", value: "\(identity.executableBasename), PID \(identity.pid)")
                DetailRow(label: "Started", value: identity.startTime == .distantPast ? "unknown" : identity.startTime.formatted(date: .abbreviated, time: .standard))
            }
        } else if let identity = entry.processIdentity {
            DetailRow(label: "Browser", value: "\(identity.executableBasename), PID \(identity.pid)")
            DetailRow(label: "Started", value: identity.startTime == .distantPast ? "unknown" : identity.startTime.formatted(date: .abbreviated, time: .standard))
            if let parentProcessSummary = entry.parentProcessSummary {
                DetailRow(label: "Launched by", value: parentProcessSummary)
            }
            if let signalReason = entry.signalReason, signalReason.isEmpty == false {
                DetailRow(label: "Found by", value: signalReason)
            }
        }
    }

    private var safetyCopy: String {
        if entry.source == .agentBrowser {
            return "Close asks agent-browser to end this session."
        }
        if entry.isClosable {
            return "Close stops this browser and leaves the process that launched it running."
        }
        return "No Playwright or Puppeteer flags found, so this browser can't be closed from here."
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

    private var accessibilityLabel: String {
        var parts = [entry.displayName]
        switch entry.source {
        case .agentBrowser:
            parts.append("agent-browser session")
        case .process:
            parts.append(entry.confidence == .high ? "Playwright or Puppeteer browser" : "unconfirmed browser")
            if let pid = entry.processIdentity?.pid { parts.append("PID \(pid)") }
        }
        parts.append(entry.isClosable ? "can be closed" : "view only")
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
        .accessibilityLabel("agent-browser sessions unavailable: \(reason)")
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
            Text("No automation browsers running")
                .font(.headline)
            Text("Checks again every 5 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The app icon of the bundle a browser runs from, or a globe when the executable is unknown.
private struct BrowserIcon: View {
    let executablePath: String?

    var body: some View {
        Group {
            if let executablePath {
                Image(nsImage: AppIconCache.icon(forExecutable: executablePath))
                    .resizable()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum AppIconCache {
    // ponytail: unbounded, but keyed by app bundle, so it holds one entry per installed browser.
    private static var icons: [String: NSImage] = [:]

    static func icon(forExecutable path: String) -> NSImage {
        let bundle = path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" } ?? path
        if let icon = icons[bundle] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        icons[bundle] = icon
        return icon
    }
}

import SwiftUI

public struct PopoverShellView: View {
    public let snapshot: DetectionSnapshot

    public init(snapshot: DetectionSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        if snapshot.totalCount == 0 {
            ZeroStateView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Automation browsers")
                    .font(.headline)
                Text("\(snapshot.totalCount) detected")
                    .foregroundStyle(.secondary)
                Text("Detection engine lands in U4.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(minWidth: 260)
        }
    }
}

public struct ZeroStateView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            Text("No automation browsers detected")
                .font(.headline)
            Text("Polling continues in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 240)
    }
}

import SwiftUI

struct TimelineView: View {
    let steps: [AgentStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(steps) { step in
                DisclosureGroup {
                    Text(step.details)
                        .font(.body)
                        .padding(.top, 4)
                } label: {
                    HStack {
                        statusIcon(for: step.status)
                        Text(step.title)
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Text(step.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func statusIcon(for status: AgentStep.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.orange)
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.blue)
        case .success:
            Image(systemName: "checkmark.seal")
                .foregroundColor(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.yellow)
        case .failure:
            Image(systemName: "xmark.octagon")
                .foregroundColor(.red)
        }
    }
}

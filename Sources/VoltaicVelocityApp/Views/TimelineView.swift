import SwiftUI

struct TimelineView: View {
    let steps: [AgentStep]
    let editorViewModel: EditorViewModel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                TimelineStepView(
                    step: step,
                    isLast: index == steps.count - 1,
                    editorViewModel: editorViewModel
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct TimelineStepView: View {
    let step: AgentStep
    let isLast: Bool
    let editorViewModel: EditorViewModel?
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline line and node
            VStack(spacing: 0) {
                statusNode
                
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1.5)
                        .padding(.vertical, 4)
                } else {
                    Spacer()
                }
            }
            .frame(width: 14)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: iconForStep(step.title))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(step.status == .failure ? .red : .secondary)
                            
                        if let fileURL = step.fileURL {
                            Text(step.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(step.status == .failure ? .red : .blue)
                                .underline()
                                .onTapGesture {
                                    editorViewModel?.openFile(at: fileURL)
                                }
                                .help(fileURL.path)
                        } else {
                            Text(step.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(step.status == .failure ? .red : .primary)
                        }
                        
                        if let role = step.agentRole {
                            Text(role.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(roleColor(for: role).opacity(0.2))
                                .foregroundColor(roleColor(for: role))
                                .cornerRadius(4)
                        }
                        
                        Text(step.timestamp, style: .time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.trailing, 8)
                    }
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    if let children = step.children, !children.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(children.enumerated()), id: \.element.id) { index, childStep in
                                TimelineStepView(
                                    step: childStep,
                                    isLast: index == children.count - 1,
                                    editorViewModel: editorViewModel
                                )
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if !step.details.isEmpty {
                        Text(step.details)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(red: 0.85, green: 0.87, blue: 0.90))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                            )
                            .padding(.bottom, 8)
                            .padding(.trailing, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 12)
        }
    }
    
    private func iconForStep(_ title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("command") || lower.contains("ran") || lower.contains("terminal") {
            return "terminal"
        } else if lower.contains("edit") || lower.contains("file") || lower.contains("code") {
            return "doc.text"
        } else if lower.contains("search") || lower.contains("find") {
            return "magnifyingglass"
        } else if lower.contains("plan") || lower.contains("think") {
            return "brain"
        } else {
            return "circle"
        }
    }

    private func roleColor(for role: AgentRole) -> Color {
        switch role {
        case .supervisor: return .purple
        case .planner: return .orange
        case .coder: return .blue
        case .researcher: return .cyan
        case .reviewer: return .green
        }
    }

    @ViewBuilder
    private var statusNode: some View {
        switch step.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
                .padding(.top, 2)
        case .success:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
        case .failure:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
        case .warning:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
        case .pending:
            Circle()
                .strokeBorder(Color.gray, lineWidth: 1.5)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
        }
    }
}

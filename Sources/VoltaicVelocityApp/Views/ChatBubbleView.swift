import SwiftUI
import MarkdownUI

struct ChatBubbleView: View {
    enum FeedbackState {
        case liked, disliked
    }
    
    let message: ChatMessage
    var onEdit: (() -> Void)? = nil
    @State private var isHovering = false
    @State private var feedbackState: FeedbackState? = nil

    var body: some View {
        switch message.role {
        case .system:
            systemBubble
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        }
    }

    // MARK: — System Message (subtle centered pill)
    private var systemBubble: some View {
        HStack {
            Spacer()
            Text(message.text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: — User Message (right-aligned)
    private var userBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer(minLength: 60)
            
            if isHovering {
                Button(action: { onEdit?() }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .transition(.opacity)
            }
            
            Text(message.text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Material.ultraThin)
                .foregroundColor(.primary)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)

            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(
                    Text("U")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation { isHovering = hovering }
        }
    }

    // MARK: — Assistant Message (Antigravity-style)
    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.7), Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Work time header
                if message.totalWorkTime > 0 {
                    WorkTimeHeader(duration: message.totalWorkTime)
                }

                // Inline activity rows
                if !message.activities.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(message.activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                }

                // Main response text
                if !message.text.isEmpty {
                    renderMessageContent(message.text)
                }

                // Files changed summary
                if !message.filesChanged.isEmpty {
                    FilesChangedSummary(changes: message.filesChanged)
                }

                // Action buttons (hover to reveal)
                if !message.text.isEmpty {
                    HStack(spacing: 14) {
                        chatAction(icon: "doc.on.doc", label: "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                        chatAction(icon: feedbackState == .liked ? "hand.thumbsup.fill" : "hand.thumbsup", label: "Good") {
                            feedbackState = .liked
                            FeedbackService.shared.saveFeedback(query: "", response: message.text, isPositive: true)
                        }
                        chatAction(icon: feedbackState == .disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", label: "Bad") {
                            feedbackState = .disliked
                            FeedbackService.shared.saveFeedback(query: "", response: message.text, isPositive: false)
                        }

                        Spacer()

                        Text(message.date, style: .time)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.top, 4)
                    .opacity(isHovering || feedbackState != nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Material.ultraThin)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 2)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onHover { isHovering = $0 }
    }

    // MARK: — Message Content Renderer
    @ViewBuilder
    private func renderMessageContent(_ text: String) -> some View {
        Markdown(text)
            .markdownTheme(.voltTheme)
            .textSelection(.enabled)
    }

    private func chatAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .help(label)
        }
        .buttonStyle(.plain)
    }
}

// MARK: — Work Time Header
private struct WorkTimeHeader: View {
    let duration: TimeInterval
    @State private var isExpanded = false

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
            HStack(spacing: 4) {
                Text("Worked for \(formattedDuration)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    private var formattedDuration: String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
    }
}

// MARK: — Inline Activity Row
private struct ActivityRow: View {
    let activity: AgentActivity
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                if hasExpandableContent {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                }
            }) {
                HStack(spacing: 6) {
                    // Activity icon
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(iconColor)
                        .frame(width: 14)

                    // Label
                    activityLabel

                    Spacer()

                    // Chevron if expandable
                    if hasExpandableContent {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.4))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable details
            if isExpanded && !activity.details.isEmpty {
                Text(activity.details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.78, green: 0.80, blue: 0.83))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var activityLabel: some View {
        switch activity.kind {
        case .thinking(let duration):
            HStack(spacing: 4) {
                Text("Thought for \(Int(duration))s")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case .searching(let query, let results):
            HStack(spacing: 4) {
                Text("Searched")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(query)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(results) result\(results == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        case .analyzing(let file, let lines):
            HStack(spacing: 4) {
                Text("Analyzed")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("📄 \(file)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                if !lines.isEmpty {
                    Text(lines)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        case .editing(let file, let added, let removed):
            HStack(spacing: 4) {
                Text("Edited")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("📄 \(file)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                Text("+\(added)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
                Text("-\(removed)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
            }
        case .created(let file):
            HStack(spacing: 4) {
                Text("Created")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(file)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }
        case .deleted(let file):
            HStack(spacing: 4) {
                Text("Deleted")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(file)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }
        case .ranCommand(let command):
            HStack(spacing: 4) {
                Text("Ran")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(command.prefix(50) + (command.count > 50 ? "…" : ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        case .completed:
            Text("Completed")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case .error(let message):
            HStack(spacing: 4) {
                Text("Error:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                Text(message.prefix(60) + (message.count > 60 ? "…" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(1)
            }
        case .warning(let message):
            HStack(spacing: 4) {
                Text("Warning:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                Text(message.prefix(60) + (message.count > 60 ? "…" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(.orange.opacity(0.8))
                    .lineLimit(1)
            }
        case .info(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        case .askingUser(let question):
            HStack(spacing: 4) {
                Text("Asked")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(question.prefix(60) + (question.count > 60 ? "…" : ""))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
        case .searchingWeb(let query):
            HStack(spacing: 4) {
                Text("Searched Web")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(query)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        case .runningTests(let file):
            HStack(spacing: 4) {
                Text("Running Tests")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(file)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        case .profiling(let command):
            HStack(spacing: 4) {
                Text("Profiling")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(command.prefix(50) + (command.count > 50 ? "…" : ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }

    private var iconName: String {
        switch activity.kind {
        case .thinking: return "brain"
        case .searching: return "magnifyingglass"
        case .analyzing: return "doc.text.magnifyingglass"
        case .editing: return "pencil"
        case .created: return "plus.circle.fill"
        case .deleted: return "trash"
        case .ranCommand: return "terminal"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.triangle"
        case .info: return "info.circle"
        case .askingUser: return "person.fill.questionmark"
        case .searchingWeb: return "globe"
        case .runningTests: return "testtube.2"
        case .profiling: return "speedometer"
        }
    }

    private var iconColor: Color {
        switch activity.kind {
        case .thinking: return .purple
        case .searching: return .cyan
        case .analyzing: return .blue
        case .editing: return .orange
        case .created: return .green
        case .deleted: return .red
        case .ranCommand: return .secondary
        case .completed: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .askingUser: return .orange
        case .searchingWeb: return .teal
        case .runningTests: return .purple
        case .profiling: return .orange
        }
    }

    private var hasExpandableContent: Bool {
        !activity.details.isEmpty
    }
}

// MARK: — Files Changed Summary
private struct FilesChangedSummary: View {
    let changes: [FileChange]

    var body: some View {
        HStack(spacing: 8) {
            let totalAdded = changes.reduce(0) { $0 + $1.added }
            let totalRemoved = changes.reduce(0) { $0 + $1.removed }

            Text("\(changes.count) file\(changes.count == 1 ? "" : "s") changed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 2) {
                Text("+\(totalAdded)")
                    .foregroundColor(.green)
                Text("-\(totalRemoved)")
                    .foregroundColor(.red)
            }
            .font(.system(size: 11, weight: .medium))

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text("Review")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

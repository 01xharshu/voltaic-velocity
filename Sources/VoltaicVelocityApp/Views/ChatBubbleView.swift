import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    var onEdit: (() -> Void)? = nil
    @State private var isHovering = false

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
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.primary)
                .cornerRadius(18)

            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(
                    Text("U")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation { isHovering = hovering }
        }
    }

    // MARK: — Assistant Message (left-aligned, clean)
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

            VStack(alignment: .leading, spacing: 8) {
                // Render message with basic code block support
                renderMessageContent(message.text)

                // Action buttons (hover to reveal)
                if !message.text.isEmpty {
                    HStack(spacing: 14) {
                        chatAction(icon: "doc.on.doc", label: "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                        chatAction(icon: "hand.thumbsup", label: "Good") {
                            FeedbackService.shared.saveFeedback(query: "", response: message.text, isPositive: true)
                        }
                        chatAction(icon: "hand.thumbsdown", label: "Bad") {
                            FeedbackService.shared.saveFeedback(query: "", response: message.text, isPositive: false)
                        }
                    }
                    .padding(.top, 2)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onHover { isHovering = $0 }
    }

    // MARK: — Message Content Renderer (basic code block support)
    @ViewBuilder
    private func renderMessageContent(_ text: String) -> some View {
        let parts = splitByCodeBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parts.indices, id: \.self) { i in
                let part = parts[i]
                if part.isCode {
                    // Code block
                    VStack(alignment: .leading, spacing: 0) {
                        if !part.language.isEmpty {
                            Text(part.language)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                        Text(part.content)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(red: 0.85, green: 0.87, blue: 0.90))
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                    .cornerRadius(10)
                } else if !part.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Regular text
                    Text(part.content)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
            }
        }
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

    // MARK: — Code Block Parser
    private struct TextPart {
        let content: String
        let isCode: Bool
        let language: String
    }

    private func splitByCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [TextPart(content: text, isCode: false, language: "")]
        }

        let nsText = text as NSString
        var lastEnd = 0

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
                parts.append(TextPart(content: before, isCode: false, language: ""))
            }

            let lang = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            parts.append(TextPart(content: code, isCode: true, language: lang))

            lastEnd = matchRange.location + matchRange.length
        }

        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd)
            parts.append(TextPart(content: remaining, isCode: false, language: ""))
        }

        if parts.isEmpty {
            parts.append(TextPart(content: text, isCode: false, language: ""))
        }

        return parts
    }
}

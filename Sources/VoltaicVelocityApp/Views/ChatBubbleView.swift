import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: message.role == .user ? "person.fill" : "gearshape.fill")
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(message.text)
                    .padding(12)
                    .background(bubbleColor)
                    .cornerRadius(14)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var bubbleColor: Color {
        switch message.role {
        case .assistant: return Color(NSColor.controlBackgroundColor)
        case .user: return Color.accentColor.opacity(0.15)
        case .system: return Color.gray.opacity(0.12)
        }
    }
}

import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var agentViewModel: AgentViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var terminalViewModel: TerminalViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent Console")
                    .font(.headline)
                Spacer()
                Picker("Mode", selection: $agentViewModel.isAgentModePlanning) {
                    Text("Plan + Execute").tag(true)
                    Text("Analyze").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            Divider()

            VStack(spacing: 12) {
                HStack {
                    Picker("Model", selection: $agentViewModel.selectedModel) {
                        Text("Qwen2.5-Coder").tag("qwen2.5-coder")
                        Text("Local Coder").tag("qwen2.5-coder")
                    }
                    .pickerStyle(.menu)
                    .padding(.vertical, 4)
                    Spacer()
                    Button("New Chat") {
                        agentViewModel.startNewChat()
                    }
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(agentViewModel.chatMessages) { message in
                            ChatBubbleView(message: message)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                Divider()

                ScrollView { TimelineView(steps: agentViewModel.agentSteps) }
                    .frame(minHeight: 150, maxHeight: 220)

                HStack {
                    TextField("Ask the AI to build UI, edit project files, or run a command…", text: $agentViewModel.promptText)
                        .textFieldStyle(.roundedBorder)
                    Button(action: agentViewModel.sendPrompt) {
                        Label(agentViewModel.isProcessing ? "Working…" : "Send", systemImage: "paperplane.fill")
                    }
                    .disabled(agentViewModel.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentViewModel.isProcessing)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $agentViewModel.pendingFileAction) { action in
            PendingActionReviewView(action: action)
        }
    }
}

private struct PendingActionReviewView: View {
    let action: PendingFileAction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.summary)
                .font(.title2)
                .bold()
            Text("Path: \(action.fileURL.path)")
                .foregroundColor(.secondary)
            Divider()
            ScrollView {
                Text(action.newText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Discard") {
                    dismiss()
                }
                Button("Apply") {
                    action.apply()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }
}

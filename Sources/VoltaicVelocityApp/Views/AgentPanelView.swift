import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var agentViewModel: AgentViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var terminalViewModel: TerminalViewModel

    @State private var showingMentions = false
    @State private var mentionQuery = ""
    @State private var filteredFiles: [WorkspaceFile] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.purple)
                    Text("Voltaic AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                // Connection indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(agentViewModel.ollamaReachable ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(agentViewModel.ollamaReachable ? "Connected" : "Offline")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Button(action: agentViewModel.startNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("New Chat")
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.5)

            // Chat Area
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        if agentViewModel.chatMessages.isEmpty || (agentViewModel.chatMessages.count == 1 && agentViewModel.chatMessages.first?.role == .system) {
                            // Empty state
                            emptyState
                        } else {
                            ForEach(agentViewModel.chatMessages) { message in
                                ChatBubbleView(message: message) {
                                    agentViewModel.editPrompt(messageId: message.id)
                                }
                            }
                        }

                        // Typing indicator
                        if agentViewModel.isProcessing {
                            typingIndicator
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: agentViewModel.chatMessages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: agentViewModel.chatMessages.last?.text) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: agentViewModel.chatMessages.last?.activities.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
            }

            // Error banner
            if !agentViewModel.ollamaReachable && agentViewModel.availableModels.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text("Ollama is not running. Start it with ")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    + Text("ollama serve")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if let action = agentViewModel.pendingFileAction {
                PendingActionReviewView(action: action, agentViewModel: agentViewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input Area
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        if !agentViewModel.availableModels.isEmpty {
                            Picker("", selection: $agentViewModel.selectedModel) {
                                ForEach(agentViewModel.availableModels, id: \.self) { model in
                                    let isOpt = model.lowercased().contains("q4_") || model.lowercased().contains("q5_")
                                    Text(isOpt ? "\(model) ⚡️ MLX Opt" : model)
                                        .tag(model)
                                }
                            }
                            .labelsHidden()
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        
                        Spacer()
                        
                        Toggle("Multi-Agent Team", isOn: $agentViewModel.isMultiAgentEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                    // Text input + Send
                    HStack(alignment: .bottom) {
                        ZStack(alignment: .bottomLeading) {
                            TextField("Ask the AI to build, edit, or run commands (use @ for files)…", text: $agentViewModel.promptText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                                .lineLimit(1...8)
                                .onChange(of: agentViewModel.promptText) { _, text in
                                    checkForMentions(in: text)
                                }
                                .onSubmit {
                                    if !showingMentions && !agentViewModel.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        agentViewModel.sendPrompt()
                                    }
                                }

                            if showingMentions {
                                mentionsPopover
                                    .alignmentGuide(.bottom) { d in d[.bottom] + 40 }
                                    .padding(.horizontal, 14)
                            }
                        }

                        Button(action: {
                            if agentViewModel.isProcessing {
                                agentViewModel.stopProcessing()
                            } else {
                                agentViewModel.sendPrompt()
                            }
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(canSend ? Color.accentColor : Color.gray.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: agentViewModel.isProcessing ? "stop.fill" : "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(canSend ? .white : .gray)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var canSend: Bool {
        !agentViewModel.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentViewModel.isProcessing
    }

    // MARK: - Mentions Logic
    private func checkForMentions(in text: String) {
        guard let lastWord = text.split(separator: " ", omittingEmptySubsequences: false).last else {
            showingMentions = false
            return
        }
        
        if lastWord.hasPrefix("@") {
            let query = String(lastWord.dropFirst())
            mentionQuery = query
            
            // Flatten workspace files
            var allFiles = [WorkspaceFile]()
            func collectFiles(from items: [WorkspaceFile]) {
                for item in items {
                    if !item.isDirectory {
                        allFiles.append(item)
                    }
                    if let children = item.children {
                        collectFiles(from: children)
                    }
                }
            }
            collectFiles(from: projectViewModel.workspaceItems)
            
            if query.isEmpty {
                filteredFiles = Array(allFiles.prefix(5))
            } else {
                filteredFiles = Array(allFiles.filter { $0.name.lowercased().contains(query.lowercased()) }.prefix(5))
            }
            
            showingMentions = !filteredFiles.isEmpty
        } else {
            showingMentions = false
        }
    }
    
    private var mentionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredFiles) { file in
                Button(action: {
                    insertMention(file.name)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                        Text(file.name)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor))
                
                if file.id != filteredFiles.last?.id {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
        .frame(width: 250)
    }
    
    private func insertMention(_ filename: String) {
        let words = agentViewModel.promptText.split(separator: " ", omittingEmptySubsequences: false)
        var newWords = Array(words)
        if let last = newWords.last, last.hasPrefix("@") {
            newWords[newWords.count - 1] = "@\(filename)"
        }
        agentViewModel.promptText = newWords.joined(separator: " ") + " "
        showingMentions = false
    }

    // MARK: — Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("How can I help with your project?")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)

            missionsGrid

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: — Missions Grid
    private var missionsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        
        let missions: [(icon: String, title: String, prompt: String)] = [
            ("hammer", "Refactor Architecture", "Refactor this module for better architecture"),
            ("ladybug", "Error Handling", "Add full error handling + logging"),
            ("swift", "SwiftUI Migration", "Convert this to SwiftUI from UIKit"),
            ("bolt.fill", "Optimize Performance", "Optimize for performance")
        ]
        
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(missions, id: \.title) { mission in
                Button(action: {
                    agentViewModel.promptText = mission.prompt
                    agentViewModel.sendPrompt()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: mission.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                        Text(mission.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: — Typing Indicator
    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
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

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .offset(y: dotOffset(for: i))
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: agentViewModel.isProcessing
                        )
                }
            }
            .padding(.top, 10)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func dotOffset(for index: Int) -> CGFloat {
        return agentViewModel.isProcessing ? -4 : 0
    }
}

// MARK: — Pending Action Review Card (Inline Cursor Style)
private struct PendingActionReviewView: View {
    let action: PendingFileAction
    @ObservedObject var agentViewModel: AgentViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Top portion: File info
            HStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                
                // Mock line changes (since we don't have exact diff chunks calculated)
                HStack(spacing: 4) {
                    Text("+4")
                        .foregroundColor(Color.green.opacity(0.9))
                    Text("-1")
                        .foregroundColor(Color.red.opacity(0.9))
                }
                .font(.system(size: 11, design: .monospaced))
                
                Text(action.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Divider()
                .background(Color.white.opacity(0.05))
            
            // Bottom portion: Action bar
            HStack {
                HStack(spacing: 4) {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(true)
                    
                    Image(systemName: "doc")
                        .padding(.leading, 4)
                    Text("1 File")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Reject all") {
                    agentViewModel.pendingFileAction = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
                
                Button("Accept all") {
                    action.apply()
                    agentViewModel.pendingFileAction = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.2))
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

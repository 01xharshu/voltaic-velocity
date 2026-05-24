import Foundation
import OllamaKit

@MainActor
public enum AutonomyLevel: String, CaseIterable {
    case manual = "Manual Approval"
    case autonomous = "Fully Autonomous"
}

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var chatMessages: [ChatMessage] = [ChatMessage(role: .system, text: "Volt Velocity AI agent ready. Use natural language to modify the project, write code, or run terminal commands.")]
    @Published var promptText = ""
    @Published var selectedModel = "qwen2.5-coder:7b"
    @Published var isAgentModePlanning = true
    @Published var isShowingCommandPalette = false
    @Published var isProcessing = false
    @Published var activeToolAction: String? = nil
    @Published var activePendingEditCode: String? = nil
    @Published var pendingFileAction: PendingFileAction?
    @Published var presentedDiff: PendingFileAction?
    @Published var ollamaReachable = true
    @Published var availableModels: [String] = ["qwen2.5-coder:7b"]
    @Published var isMultiAgentEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "isMultiAgentEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "isMultiAgentEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(isMultiAgentEnabled, forKey: "isMultiAgentEnabled")
        }
    }
    
    @Published var autonomyLevel: AutonomyLevel = {
        if let stored = UserDefaults.standard.string(forKey: "autonomyLevel"), let level = AutonomyLevel(rawValue: stored) {
            return level
        }
        return .autonomous
    }() {
        didSet {
            UserDefaults.standard.set(autonomyLevel.rawValue, forKey: "autonomyLevel")
        }
    }

    @Published var useMLXEngine: Bool = UserDefaults.standard.bool(forKey: "useMLXEngine") {
        didSet {
            UserDefaults.standard.set(useMLXEngine, forKey: "useMLXEngine")
            Task { await fetchAvailableModels() }
        }
    }

    private var currentTask: Task<Void, Never>?

    private let ollamaService = OllamaService()
    private let mlxService = MLXService()
    
    private var service: any AIServiceProtocol {
        useMLXEngine ? mlxService : ollamaService
    }
    
    private let gitService = GitService()
    private var projectViewModel: ProjectViewModel?
    private var editorViewModel: EditorViewModel?
    private var terminalManager: TerminalManagerViewModel?
    private let coordinator = MultiAgentCoordinator()

    @Published var activeChatId: UUID = {
        if let stored = UserDefaults.standard.string(forKey: "activeChatId"), let id = UUID(uuidString: stored) {
            return id
        }
        return UUID()
    }() {
        didSet {
            UserDefaults.standard.set(activeChatId.uuidString, forKey: "activeChatId")
        }
    }
    
    init() {
        self.coordinator.agentViewModel = self
        loadHistory(id: activeChatId)
        Task {
            await fetchAvailableModels()
        }
    }
    
    func saveHistory() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoltaicVelocityChats")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(activeChatId.uuidString).json")
        do {
            let data = try JSONEncoder().encode(chatMessages)
            try data.write(to: url)
        } catch {
            print("Failed to save history: \(error)")
        }
    }

    func loadHistory(id: UUID) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoltaicVelocityChats/\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let msgs = try JSONDecoder().decode([ChatMessage].self, from: data)
            if !msgs.isEmpty {
                self.chatMessages = msgs
            }
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    func getAllChatSessions() -> [(id: UUID, date: Date, title: String)] {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoltaicVelocityChats")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        
        var sessions: [(UUID, Date, String)] = []
        for url in urls where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let date = attrs?[.creationDate] as? Date ?? Date()
            
            // Try to extract title from first user message
            var title = "New Chat"
            if let data = try? Data(contentsOf: url),
               let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data),
               let firstUser = msgs.first(where: { $0.role == .user }) {
                title = String(firstUser.text.prefix(30))
                if firstUser.text.count > 30 { title += "..." }
            }
            
            sessions.append((id, date, title))
        }
        return sessions.sorted(by: { $0.1 > $1.1 })
    }
    
    private func fetchAvailableModels() async {
        do {
            let fetchedModels = try await service.fetchModels()
            await MainActor.run {
                if !fetchedModels.isEmpty {
                    // Sort models putting quantized (Q4/Q5) ones first as they are Apple Silicon / MLX optimized
                    let sorted = fetchedModels.sorted { a, b in
                        let aIsOpt = a.lowercased().contains("q4_") || a.lowercased().contains("q5_")
                        let bIsOpt = b.lowercased().contains("q4_") || b.lowercased().contains("q5_")
                        if aIsOpt == bIsOpt { return a < b }
                        return aIsOpt && !bIsOpt
                    }
                    self.availableModels = sorted
                    if !sorted.contains(self.selectedModel) {
                        self.selectedModel = sorted.first!
                    }
                }
                self.ollamaReachable = true
            }
        } catch {
            await MainActor.run {
                self.ollamaReachable = false
            }
        }
    }

    func link(projectViewModel: ProjectViewModel, editorViewModel: EditorViewModel, terminalManager: TerminalManagerViewModel) {
        self.projectViewModel = projectViewModel
        self.editorViewModel = editorViewModel
        self.terminalManager = terminalManager
    }

    func startNewChat() {
        activeChatId = UUID()
        chatMessages = [ChatMessage(role: .system, text: "You are the Volt Velocity project agent. Use tool calls to modify files, run terminal commands, and analyze the workspace.")]
        promptText = ""
        saveHistory()
    }

    func sendPrompt() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        chatMessages.append(ChatMessage(role: .user, text: userText))
        saveHistory()
        promptText = ""
        isProcessing = true

        currentTask?.cancel()
        currentTask = Task {
            await streamResponse(for: userText)
        }
    }

    func editPrompt(messageId: UUID) {
        guard !isProcessing else { return }
        if let index = chatMessages.firstIndex(where: { $0.id == messageId }), chatMessages[index].role == .user {
            promptText = chatMessages[index].text
            // Revert chat history up to this message
            chatMessages = Array(chatMessages.prefix(upTo: index))
        }
    }

    func stopProcessing() {
        isProcessing = false
        currentTask?.cancel()
        currentTask = nil
        appendActivity(.error(message: "User interrupted the agent."), details: "")
        saveHistory()
    }

    private func streamResponse(for userText: String) async {
        let startTime = Date()
        isProcessing = true
        
        let assistant = ChatMessage(role: .assistant, text: "")
        chatMessages.append(assistant)
        
        guard let url = URL(string: "ws://127.0.0.1:8000/ws") else {
            appendActivity(.error(message: "Invalid WebSocket URL"), details: "")
            isProcessing = false
            return
        }
        
        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: url)
        webSocketTask.resume()
        
        let projectPath = projectViewModel?.projectURL?.path ?? ""
        let projectDescription = projectViewModel?.projectStructureDescription ?? "No project open."
        let openFiles = projectViewModel?.workspaceItems.map { $0.name }.joined(separator: ", ") ?? "None"
        let projectSummary = projectViewModel?.projectSummary ?? ""
        
        let requestDict: [String: Any] = [
            "prompt": getAugmentedPrompt(for: userText),
            "project_path": projectPath,
            "project_description": projectDescription,
            "open_files": openFiles,
            "project_summary": projectSummary
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: requestDict),
           let string = String(data: data, encoding: .utf8) {
            try? await webSocketTask.send(.string(string))
        }
        
        while isProcessing {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        if let type = json["type"] as? String {
                            await MainActor.run {
                                if type == "token", let token = json["text"] as? String {
                                    if let lastIndex = self.chatMessages.lastIndex(where: { $0.role == .assistant }) {
                                        self.chatMessages[lastIndex].text += token
                                    }
                                } else if type == "status", let msg = json["message"] as? String {
                                    self.appendActivity(.info(message: msg), details: "")
                                } else if type == "done" {
                                    self.isProcessing = false
                                } else if type == "error", let errorMsg = json["message"] as? String {
                                    self.appendActivity(.error(message: "Agent Error"), details: errorMsg)
                                    self.isProcessing = false
                                } else if type == "tool_start", let toolName = json["name"] as? String {
                                    self.activeToolAction = toolName
                                    self.activePendingEditCode = ""
                                } else if type == "tool_stream", let chunk = json["chunk"] as? String {
                                    self.activePendingEditCode? += chunk
                                } else if type == "tool_finish" {
                                    if self.activeToolAction != nil,
                                       let argsJson = self.activePendingEditCode,
                                       let projectURL = self.projectViewModel?.projectURL {
                                        if let argsData = argsJson.data(using: .utf8),
                                           let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                                            if let relativePath = argsDict["path"] as? String {
                                                let targetURL = projectURL.appendingPathComponent(relativePath)
                                                self.projectViewModel?.refreshWorkspace()
                                                self.editorViewModel?.reloadText(for: targetURL)
                                            }
                                        }
                                    }
                                    self.activeToolAction = nil
                                    self.activePendingEditCode = nil
                                }
                            }
                        }
                    }
                case .data(_):
                    break
                @unknown default:
                    break
                }
            } catch {
                await MainActor.run {
                    self.appendActivity(.error(message: "WebSocket disconnected"), details: error.localizedDescription)
                    if let lastIndex = self.chatMessages.lastIndex(where: { $0.role == .assistant }) {
                        self.chatMessages[lastIndex].text += "\n⚠️ Connection to Python backend lost. Is `agent_server.py` running on port 8000?"
                    }
                    self.isProcessing = false
                }
                break
            }
        }
        
        if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
            chatMessages[lastIndex].totalWorkTime = Date().timeIntervalSince(startTime)
        }
        
        saveHistory()
    }

    private func getAugmentedPrompt(for prompt: String) -> String {
        var augmentedPrompt = prompt
        if let projectVM = projectViewModel {
            let words = prompt.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            var injectedFiles = [String]()
            for word in words {
                var cleanWord = word
                while cleanWord.hasSuffix("?") || cleanWord.hasSuffix(".") || cleanWord.hasSuffix(",") || cleanWord.hasSuffix("!") || cleanWord.hasSuffix(":") {
                    cleanWord.removeLast()
                }
                if cleanWord.hasPrefix("@") {
                    let filename = String(cleanWord.dropFirst())
                    if let url = findFileURL(name: filename, in: projectVM.workspaceItems),
                       let content = try? FileSystemService.shared.readText(from: url) {
                        let limit = 150000
                        let truncated: String
                        if content.count > limit {
                            truncated = String(content.prefix(limit)) + "\n... [File truncated due to size. Use your tools to read specific lines if needed]"
                        } else {
                            truncated = content
                        }
                        injectedFiles.append("Context from \(filename):\n```\n\(truncated)\n```\n")
                    }
                }
            }
            if !injectedFiles.isEmpty {
                augmentedPrompt = injectedFiles.joined(separator: "\n") + "\nUser Request: " + prompt
            }
        }
        return augmentedPrompt
    }

    private func findFileURL(name: String, in items: [WorkspaceFile]) -> URL? {
        for item in items {
            if item.name == name { return item.url }
            if let children = item.children, let found = findFileURL(name: name, in: children) {
                return found
            }
        }
        return nil
    }

    private func buildChatMessages(for prompt: String) -> [OKChatRequestData.Message] {
        var augmentedPrompt = prompt
        if let projectVM = projectViewModel {
            let words = prompt.split(separator: " ")
            var injectedFiles = [String]()
            for word in words {
                if word.hasPrefix("@") {
                    let filename = String(word.dropFirst())
                    if let url = findFileURL(name: filename, in: projectVM.workspaceItems),
                       let content = try? FileSystemService.shared.readText(from: url) {
                        let limit = 150000
                        let truncated: String
                        if content.count > limit {
                            truncated = String(content.prefix(limit)) + "\n... [File truncated due to size. Use your tools to read specific lines if needed]"
                        } else {
                            truncated = content
                        }
                        injectedFiles.append("Context from \(filename):\n```\n\(truncated)\n```\n")
                    }
                }
            }
            if !injectedFiles.isEmpty {
                augmentedPrompt = injectedFiles.joined(separator: "\n") + "\nUser Request: " + prompt
            }
        }

        var messages: [OKChatRequestData.Message] = []
        // Limit context to the last 20 messages to prevent context window overflow
        let recentMessages = chatMessages.suffix(20)
        
        for item in recentMessages {
            let role: OKChatRequestData.Message.Role = item.role == .user ? .user : item.role == .assistant ? .assistant : .system
            messages.append(OKChatRequestData.Message(role: role, content: item.text))
        }

        let systemPrompt = buildSystemPrompt()
        messages.insert(OKChatRequestData.Message(role: .system, content: systemPrompt), at: 0)
        messages.append(OKChatRequestData.Message(role: .user, content: augmentedPrompt))
        return messages
    }

    func buildSystemPrompt() -> String {
        let projectDescription = projectViewModel?.projectStructureDescription ?? "No project open."
        let fileNames = projectViewModel?.workspaceItems.map { $0.name }.joined(separator: ", ") ?? "None"
        let projectSummary = projectViewModel?.projectSummary ?? ""

        return """
        You are Volt, a friendly and helpful AI coding assistant inside Volt Velocity, a native macOS IDE.

        CRITICAL RULES:
        1. For normal conversation (greetings, questions, explanations), respond with plain text. Do NOT use any tools.
        2. ONLY use tool calls when the user explicitly asks you to create, edit, delete files, or run commands.
        3. You MUST NEVER output raw code blocks (like ```html or ```js) to create or edit files. You MUST use the `create_file` or `edit_file` tools. If you output raw code blocks, the files will not be saved!
        4. When you DO need to use a tool, respond with a brief explanation of what you will do FIRST, then on a new line output the tool call JSON wrapped in <tool_call> tags like: <tool_call>{"name": "create_file", "arguments": {"path": "...", "content": "..."}}</tool_call>
        5. Never output raw JSON without explanation. Always talk to the user like a human.
        6. Complete Code Only (Zero Placeholders): Never leave any incomplete sections, todo comments, or placeholder text. Always deliver 100% complete, fully functional, production-ready code.
        7. Single-File Inline Creation (Default): When creating web projects (HTML, CSS, JS), always put everything in a single inline HTML file unless explicitly asked otherwise. No external styles.css or script.js by default. All CSS and JS must be embedded.
        8. Advanced & Full-Featured Delivery: Build complete, full-fledged, advanced applications with modern UI/UX, smooth animations, responsive design, dark mode, micro-interactions, etc., even if the final code is 1000 to 10,000+ lines long. You are allowed to take time to generate high-quality, comprehensive code. Completeness is priority.
        9. Internet Search Capability: You can use the tool search_internet(query) whenever you need current information, latest design trends, best practices, or references. Always mention when you are searching the internet and summarize relevant findings before using them.
        10. When you successfully complete a task, proactively suggest 2-3 relevant new features or improvements the user could add next to keep iterating!
        11. If you need to edit an existing file or a linked CSS/JS file, you should read it first if you don't know the contents, then use the `edit_file` tool to update it. Do NOT make the user paste code. Do it yourself.
        12. Maintain a memory file named `VOLT_MEMORY.md` in the root of the project to record key architectural decisions and context. Update this file whenever you make significant architectural changes.
        13. True Autonomous Agent Mode: Operate like Cursor + Claude Code + Antigravity combined. When the user gives a goal or prompt, take full ownership — plan, explore, reason, edit, test, and complete the task with high intelligence and minimal user input. Be proactive, decisive, and anticipatory.
        14. Advanced Reasoning Loop: For every task, internally follow: 1) Understand the goal deeply. 2) Explore relevant files & update Project Summary. 3) Create a clear step-by-step plan (show it briefly to user). 4) Execute using tools. 5) Verify (build/test). 6) Refine and improve.
        15. High Intelligence Standards: Think several steps ahead. Suggest superior approaches when beneficial. Deliver only advanced, production-grade solutions. Maintain strong project-wide understanding at all times.
        16. Minimal Hand-Holding: Only ask the user for confirmation on major decisions or large changes. Otherwise, drive the task to completion autonomously.
        17. Full Autonomous Execution: Take complete ownership of tasks. Create a plan, execute it step-by-step, and only ask for confirmation when making large changes or finalizing major features.
        18. Smart Recovery & Iteration: If something fails (edit, build, tool call), automatically try an alternative method instead of stopping. After major changes, always offer to build and fix any errors.
        19. Cleaner & More Professional Output: Keep using the transparent Antigravity/Codex style: Thoughts & Analysis -> Plan -> Actions Taken -> Result -> Verification.
        20. Deep Advanced Skills System (2026-Level Expertise):
            - Swift & macOS: Use Swift 6+ features, SwiftUI for macOS 15+, @Observable, proper Actor isolation, async/await, TaskGroup, Continuation.
            - Architecture: Strict MVVM + Repository pattern, Clean Architecture, comprehensive error handling.
            - UI/UX: Advanced animations (matched geometry, spring), glassmorphism, responsive single-file HTML for web.
            - General Excellence: Prioritize readability, performance, secure code, and never use deprecated APIs.
        21. Skills Enforcement Mechanism: Before making any code generation or edit, you MUST output a `<skill_evaluation>` block evaluating: "Is this using the most modern, advanced, and production-grade approach available in 2026?" Upgrade mediocre code to expert level.

        EXAMPLE OF A BAD RESPONSE (DO NOT DO THIS):
        I will create the file for you.
        ```html
        <h1>Hello</h1>
        ```

        EXAMPLE OF A GOOD RESPONSE (DO THIS):
        I will create the file for you.
        <tool_call>
        {
          "name": "create_file",
          "arguments": {
            "path": "index.html",
            "content": "<h1>Hello</h1>"
          }
        }
        </tool_call>


        Available tools:
        - read_file(file_path) — Read the contents of a file
        - create_file(path, content) — Create a new file
        - edit_file(path, operation, startLine, endLine, newContent, matchText) — Edit a file. Operations: replace_lines, insert, string_replace, full_replace.
        - replace_in_file(file_path, old_string, new_string) — Replace a specific string in a file
        - delete_file(path) — Delete a file
        - run_terminal(command) — Run a shell command
        - list_files(path) — List directory contents
        - git_status() — Show git status
        - git_diff(path) — Show git diff
        - apply_diff(file_path, diff_content) — Safely apply a unified diff to a file instead of full replace
        - generate_tests(file_path) — Generate and automatically run unit tests for a specified file
        - analyze_performance(command) — Run performance profiling or time analysis on a command
        - ask_user(question) — Ask the user a clarifying question. Pauses the agent until answered
        - search_internet(query) — Search the internet for latest info, design trends, or references

        Current project:
        \(projectDescription)

        Project Summary:
        \(projectSummary)

        Open files: \(fileNames)
        """
    }

    func appendAssistantText(_ text: String) {
        guard let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) else { return }
        chatMessages[lastIndex].text += text
    }

    func appendActivity(_ kind: AgentActivity.Kind, details: String = "") {
        guard let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) else { return }
        chatMessages[lastIndex].activities.append(AgentActivity(kind: kind, details: details))
    }
    
    private func recordFileChange(name: String, added: Int, removed: Int) {
        guard let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) else { return }
        if let existingIndex = chatMessages[lastIndex].filesChanged.firstIndex(where: { $0.name == name }) {
            chatMessages[lastIndex].filesChanged[existingIndex].added += added
            chatMessages[lastIndex].filesChanged[existingIndex].removed += removed
        } else {
            chatMessages[lastIndex].filesChanged.append(FileChange(name: name, added: added, removed: removed))
        }
        saveHistory()
    }

    func makeToolDefinitions() -> [OKJSONValue] {
        let toolObjects: [[String: OKJSONValue]] = [
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("create_file"),
                    "description": .string("Create a project file and populate it with content."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path inside the project folder."),
                            ]),
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("The file content to write."),
                            ]),
                        ]),
                        "required": .array([.string("path"), .string("content")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("read_file"),
                    "description": .string("Read the contents of a file."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path to the file inside the project folder."),
                            ]),
                        ]),
                        "required": .array([.string("file_path")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("replace_in_file"),
                    "description": .string("Replace a specific string in a file with a new string. Use this for partial file edits."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path inside the project folder."),
                            ]),
                            "old_string": .object([
                                "type": .string("string"),
                                "description": .string("The exact existing string to replace."),
                            ]),
                            "new_string": .object([
                                "type": .string("string"),
                                "description": .string("The new string to replace it with."),
                            ]),
                        ]),
                        "required": .array([.string("file_path"), .string("old_string"), .string("new_string")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("edit_file"),
                    "description": .string("Edit an existing file to update content. Supports line-based partial replacements, string replacement, or full file replacement."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path inside the project folder."),
                            ]),
                            "operation": .object([
                                "type": .string("string"),
                                "description": .string("Type of edit: 'replace_lines', 'insert', 'string_replace', or 'full_replace'."),
                            ]),
                            "startLine": .object([
                                "type": .string("integer"),
                                "description": .string("Starting line number (1-indexed) for replace_lines or insert."),
                            ]),
                            "endLine": .object([
                                "type": .string("integer"),
                                "description": .string("Ending line number (1-indexed) for replace_lines. Inclusive."),
                            ]),
                            "newContent": .object([
                                "type": .string("string"),
                                "description": .string("The updated file contents to apply."),
                            ]),
                            "matchText": .object([
                                "type": .string("string"),
                                "description": .string("The exact text to match for 'string_replace' operation."),
                            ]),
                        ]),
                        "required": .array([.string("path"), .string("operation"), .string("newContent")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("delete_file"),
                    "description": .string("Delete a file from the project."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path inside the project folder."),
                            ]),
                        ]),
                        "required": .array([.string("path")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("run_terminal"),
                    "description": .string("Execute a shell command in the project workspace."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "command": .object([
                                "type": .string("string"),
                                "description": .string("The shell command to execute."),
                            ]),
                        ]),
                        "required": .array([.string("command")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("list_files"),
                    "description": .string("List the contents of a folder in the project."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path inside the project folder or root."),
                            ]),
                        ]),
                        "required": .array([.string("path")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("git_status"),
                    "description": .string("Get the current git status of the repository."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "required": .array([])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("git_diff"),
                    "description": .string("Get git diff for the repository or a specific file."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Optional relative path to a file or folder."),
                            ]),
                        ]),
                        "required": .array([])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("apply_diff"),
                    "description": .string("Safely apply a unified diff to a file instead of full replace."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path to the file."),
                            ]),
                            "diff_content": .object([
                                "type": .string("string"),
                                "description": .string("The unified diff content to apply."),
                            ]),
                        ]),
                        "required": .array([.string("file_path"), .string("diff_content")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("generate_tests"),
                    "description": .string("Generate and automatically run unit tests for a specified file."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "file_path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path to the file to test."),
                            ]),
                        ]),
                        "required": .array([.string("file_path")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("analyze_performance"),
                    "description": .string("Run performance profiling or time analysis on a command."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "command": .object([
                                "type": .string("string"),
                                "description": .string("The shell command to profile."),
                            ]),
                        ]),
                        "required": .array([.string("command")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("ask_user"),
                    "description": .string("Ask the user a clarifying question. Pauses the agent until answered."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "question": .object([
                                "type": .string("string"),
                                "description": .string("The question to ask the user."),
                            ]),
                        ]),
                        "required": .array([.string("question")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("search_internet"),
                    "description": .string("Search the internet for current information, latest design trends, best practices, or references."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("The search query."),
                            ]),
                        ]),
                        "required": .array([.string("query")])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("build_project"),
                    "description": .string("Build the project (detects swift, npm, or xcodebuild automatically)."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "required": .array([])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("run_project"),
                    "description": .string("Run the project (detects swift, npm, etc.)."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "required": .array([])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("get_build_errors"),
                    "description": .string("Get the standard error output from the last build command."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "required": .array([])
                    ])
                ])
            ],
            [
                "type": .string("function"),
                "function": .object([
                    "name": .string("create_branch"),
                    "description": .string("Create a new git branch."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object([
                                "type": .string("string"),
                                "description": .string("The name of the new branch.")
                            ])
                        ]),
                        "required": .array([.string("name")])
                    ])
                ])
            ]
        ]
        return toolObjects.map { .object($0) }
    }

    private func handleToolCall(name: String, arguments: OKJSONValue?) async -> String {
        guard let projectURL = projectViewModel?.projectURL else {
            appendActivity(.error(message: "No project opened"), details: "The agent attempted a tool call before a project folder was opened.")
            return "Error: No project opened."
        }

        let args = arguments?.objectValue() ?? [:]
        switch name {
        case "create_file":
            guard let path = args["path"]?.stringValue(), let content = args["content"]?.stringValue() else {
                appendActivity(.error(message: "create_file missing arguments"), details: "Missing path or content.")
                return "Error: Missing path or content."
            }
            let targetURL = projectURL.appendingPathComponent(path)
            let directory = targetURL.deletingLastPathComponent()
            do {
                try FileSystemService.shared.createFolderIfNeeded(at: directory)
                try FileSystemService.shared.writeText(content, to: targetURL)
                projectViewModel?.refreshWorkspace()
                let fileName = targetURL.lastPathComponent
                appendActivity(.created(file: fileName), details: "Created file at \(path).")
                let lineCount = content.components(separatedBy: .newlines).count
                recordFileChange(name: fileName, added: lineCount, removed: 0)
                return "File successfully created at \(path)."
            } catch {
                return "Error creating file: \(error.localizedDescription)"
            }

        case "read_file":
            guard let path = args["file_path"]?.stringValue() else { return "Error: Missing file_path." }
            let targetURL = projectURL.appendingPathComponent(path)
            do {
                let content = try FileSystemService.shared.readText(from: targetURL)
                appendActivity(.analyzing(file: targetURL.lastPathComponent, lines: "\(content.count) chars"), details: "Read \(path)")
                if content.count > 6000 {
                    return String(content.prefix(6000)) + "\n\n... [Content Truncated]"
                }
                return content
            } catch {
                return "Error reading file: \(error.localizedDescription)"
            }

        case "replace_in_file":
            guard let path = args["file_path"]?.stringValue(),
                  let oldString = args["old_string"]?.stringValue(),
                  let newString = args["new_string"]?.stringValue() else {
                return "Error: Missing arguments for replace_in_file."
            }
            let targetURL = projectURL.appendingPathComponent(path)
            do {
                var existingText = try FileSystemService.shared.readText(from: targetURL)
                await MainActor.run {
                    if let openFile = self.editorViewModel?.openFiles.first(where: { $0.url == targetURL }) {
                        existingText = openFile.text
                    }
                }
                let components = existingText.components(separatedBy: oldString)
                if components.count - 1 == 0 {
                    return "Error: old_string not found in file."
                } else if components.count - 1 > 1 {
                    return "Error: old_string occurs \(components.count - 1) times in the file. It must occur exactly ONCE to prevent global corruption. Please provide a larger, more unique code snippet."
                }
                let newText = existingText.replacingOccurrences(of: oldString, with: newString)
                let result = try await processFileAction(type: .edit, relativePath: path, content: newText, baseURL: projectURL)
                return result
            } catch {
                return "Error preparing replace_in_file: \(error.localizedDescription)"
            }
            
        case "edit_file":
            guard let path = args["path"]?.stringValue(), 
                  let operation = args["operation"]?.stringValue(), 
                  let newContent = args["newContent"]?.stringValue() else {
                appendActivity(.error(message: "edit_file missing arguments"), details: "Missing path, operation, or newContent.")
                return "Error: Missing path, operation, or newContent."
            }
            let targetURL = projectURL.appendingPathComponent(path)
            do {
                var existingText = try FileSystemService.shared.readText(from: targetURL)
                await MainActor.run {
                    if let openFile = self.editorViewModel?.openFiles.first(where: { $0.url == targetURL }) {
                        existingText = openFile.text
                    }
                }
                var finalText = existingText
                let lines = existingText.components(separatedBy: .newlines)

                switch operation {
                case "replace_lines":
                    if let startLine = args["startLine"]?.intValue(), let endLine = args["endLine"]?.intValue(), startLine > 0, endLine <= lines.count, startLine <= endLine {
                        var newLines = lines
                        newLines.removeSubrange((startLine - 1)...(endLine - 1))
                        let incomingLines = newContent.components(separatedBy: .newlines)
                        newLines.insert(contentsOf: incomingLines, at: startLine - 1)
                        finalText = newLines.joined(separator: "\n")
                    } else {
                        return "Error: Invalid startLine or endLine for replace_lines."
                    }
                case "insert":
                    if let startLine = args["startLine"]?.intValue(), startLine > 0, startLine <= lines.count + 1 {
                        var newLines = lines
                        let incomingLines = newContent.components(separatedBy: .newlines)
                        newLines.insert(contentsOf: incomingLines, at: startLine - 1)
                        finalText = newLines.joined(separator: "\n")
                    } else {
                        return "Error: Invalid startLine for insert."
                    }
                case "string_replace":
                    if let matchText = args["matchText"]?.stringValue() {
                        let components = existingText.components(separatedBy: matchText)
                        if components.count - 1 == 0 {
                            return "Error: matchText not found in file."
                        } else if components.count - 1 > 1 {
                            return "Error: matchText occurs \(components.count - 1) times in the file. Please provide a more unique string."
                        }
                        finalText = existingText.replacingOccurrences(of: matchText, with: newContent)
                    } else {
                        return "Error: Missing matchText for string_replace."
                    }
                case "full_replace":
                    finalText = newContent
                default:
                    return "Error: Unknown operation '\(operation)'."
                }
                
                let result = try await processFileAction(type: .edit, relativePath: path, content: finalText, baseURL: projectURL)
                return result
            } catch {
                appendActivity(.error(message: "Failed to edit file"), details: error.localizedDescription)
                return "Error editing file: \(error.localizedDescription)"
            }

        case "delete_file":
            guard let path = args["path"]?.stringValue() else {
                appendActivity(.error(message: "delete_file missing arguments"), details: "Missing path.")
                return "Error: Missing path."
            }
            await deleteFile(relativePath: path, baseURL: projectURL)
            return "Delete action requested."

        case "run_terminal":
            guard let command = args["command"]?.stringValue() else {
                appendActivity(.error(message: "run_terminal missing arguments"), details: "Missing command.")
                return "Error: Missing command."
            }
            appendActivity(.ranCommand(command: command), details: "Executing...")
            await terminalManager?.appendOutput("$ \(command)\n")
            if let output = await terminalManager?.execute(command: command) {
                return output
            }
            return "Command executed but no output returned."

        case "list_files":
            let path = args["path"]?.stringValue() ?? "."
            await listFiles(relativePath: path, baseURL: projectURL)
            // Just returning a confirmation string since UI receives real list
            return "Directory listing requested. Note: Keep in mind not to read excessively large files."
            
        case "git_status":
            await performGitStatus(baseURL: projectURL)
            return "Git status requested."
            
        case "git_diff":
            let path = args["path"]?.stringValue()
            await performGitDiff(relativePath: path, baseURL: projectURL)
            return "Git diff requested."
            
        case "apply_diff":
            guard let path = args["file_path"]?.stringValue(), let diffContent = args["diff_content"]?.stringValue() else {
                return "Error: Missing file_path or diff_content."
            }
            // Simple heuristic: just write diff to a temp file and use system patch utility
            let targetURL = projectURL.appendingPathComponent(path)
            let tempDiffURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".patch")
            do {
                try diffContent.write(to: tempDiffURL, atomically: true, encoding: .utf8)
                let command = "patch \(targetURL.path) < \(tempDiffURL.path)"
                appendActivity(.ranCommand(command: command), details: "Applying diff to \(path)")
                if let output = await terminalManager?.execute(command: command) {
                    try? FileManager.default.removeItem(at: tempDiffURL)
                    projectViewModel?.refreshWorkspace()
                    return "Diff applied:\n\(output)"
                }
                return "Diff command executed but no output returned."
            } catch {
                return "Error applying diff: \(error.localizedDescription)"
            }
            
        case "generate_tests":
            guard let path = args["file_path"]?.stringValue() else { return "Error: Missing file_path." }
            appendActivity(.runningTests(file: path), details: "Generating and running tests for \(path)")
            let command = "xcodebuild test -project VoltaicVelocity.xcodeproj -scheme VoltaicVelocityTests -destination 'platform=macOS'"
            await terminalManager?.appendOutput("$ \(command)\n")
            if let output = await terminalManager?.execute(command: command) {
                return output
            }
            return "Test command executed but no output returned."
            
        case "analyze_performance":
            guard let command = args["command"]?.stringValue() else { return "Error: Missing command." }
            appendActivity(.profiling(command: command), details: "Profiling command")
            let timeCommand = "time \(command)"
            await terminalManager?.appendOutput("$ \(timeCommand)\n")
            if let output = await terminalManager?.execute(command: timeCommand) {
                return output
            }
            return "Profile command executed but no output returned."
            
        case "ask_user":
            guard let question = args["question"]?.stringValue() else { return "Error: Missing question." }
            appendActivity(.askingUser(question: question), details: "Waiting for user input")
            return "User was asked: \(question). The agent should stop and wait for their reply in the chat."
            
        case "search_internet":
            guard let query = args["query"]?.stringValue() else { return "Error: Missing query." }
            appendActivity(.ranCommand(command: "Search Internet"), details: "Searching for: \(query)")
            
            // Simple curl via duckduckgo html endpoint to fetch titles/snippets
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let searchCommand = "curl -s -A 'Mozilla/5.0' 'https://html.duckduckgo.com/html/?q=\(encodedQuery)' | grep -iE 'a class=\"result__snippet' | sed -E 's/<[^>]*>//g' | head -n 5"
            
            if let output = await terminalManager?.execute(command: searchCommand) {
                return "Search Results:\n\(output.isEmpty ? "No useful snippet results found. Try running a curl to a specific URL." : output)"
            }
            return "Search command failed."
            
        case "build_project":
            appendActivity(.ranCommand(command: "Build Project"), details: "Building...")
            let command = "if [ -f Package.swift ]; then swift build; elif [ -f package.json ]; then npm run build; else echo 'Unknown build system'; fi"
            await terminalManager?.appendOutput("$ Build Project\n")
            if let output = await terminalManager?.execute(command: command) {
                return output
            }
            return "Build command executed but no output returned."
            
        case "run_project":
            appendActivity(.ranCommand(command: "Run Project"), details: "Running...")
            let command = "if [ -f Package.swift ]; then swift run; elif [ -f package.json ]; then npm start; else echo 'Unknown run system'; fi"
            await terminalManager?.appendOutput("$ Run Project\n")
            if let output = await terminalManager?.execute(command: command) {
                return output
            }
            return "Run command executed but no output returned."
            
        case "get_build_errors":
            appendActivity(.ranCommand(command: "Get Build Errors"), details: "Fetching errors...")
            let command = "if [ -f Package.swift ]; then swift build 2>&1 >/dev/null; elif [ -f package.json ]; then npm run build 2>&1 >/dev/null; else echo 'Unknown build system'; fi"
            if let output = await terminalManager?.execute(command: command) {
                return output
            }
            return "No error output returned."
            
        case "create_branch":
            guard let name = args["name"]?.stringValue() else { return "Error: Missing branch name." }
            appendActivity(.ranCommand(command: "git checkout -b \(name)"), details: "Creating branch...")
            if let output = await terminalManager?.execute(command: "git checkout -b \(name)") {
                return output
            }
            return "Branch created."
            
        default:
            appendActivity(.error(message: "Unknown tool call"), details: "Tool '\(name)' is not supported.")
            return "Error: Tool '\(name)' is not supported."
        }
    }

    private func processFileAction(type: PendingFileAction.ActionType, relativePath: String, content: String, baseURL: URL) async throws -> String {
        let targetURL = baseURL.appendingPathComponent(relativePath)
        let existingText = try? FileSystemService.shared.readText(from: targetURL)
        let actionName = type == .create ? "Create" : "Edit"
        let summary = "\(actionName) file at \(relativePath)"

        pendingFileAction = PendingFileAction(
            type: type,
            fileURL: targetURL,
            existingText: existingText,
            newText: content,
            summary: summary,
            apply: {
                Task { try? await self.applyPendingAction() }
            }
        )

        let oldLineCount = (existingText ?? "").components(separatedBy: .newlines).count
        let newLineCount = content.components(separatedBy: .newlines).count
        let diffSize = type == .create ? newLineCount : abs(newLineCount - oldLineCount) + 20
        let isLargeChange = diffSize > 50

        if autonomyLevel == .autonomous && !isLargeChange {
            appendActivity(.info(message: summary), details: "Automatically applying action in Autonomous mode.")
            try await applyPendingAction()
            return "File successfully updated and verified."
        } else {
            if isLargeChange {
                appendActivity(.warning(message: "Large change detected"), details: "Change affects >50 lines. Presenting Safety Diff Preview.")
                self.presentedDiff = self.pendingFileAction
            } else {
                appendActivity(.info(message: summary), details: "Review or confirm the generated code before applying.")
                self.presentedDiff = self.pendingFileAction
            }
            return "Action queued for user review. Do not assume the file is updated until the user approves it."
        }
    }

    func cancelPendingDiff() {
        presentedDiff = nil
        pendingFileAction = nil
        appendActivity(.info(message: "Edit Cancelled"), details: "User cancelled the pending diff.")
    }

    func requestDiffModification() {
        presentedDiff = nil
        pendingFileAction = nil
        let assistantMsg = ChatMessage(role: .assistant, text: "I have cancelled the pending diff. Please specify how you would like me to modify it.")
        chatMessages.append(assistantMsg)
    }

    func applyPresentedDiff() {
        presentedDiff = nil
        Task { try? await applyPendingAction() }
    }

    private func applyPendingAction() async throws {
        guard let pending = pendingFileAction else { return }
        do {
            if pending.type == .create {
                let directory = pending.fileURL.deletingLastPathComponent()
                try FileSystemService.shared.createFolderIfNeeded(at: directory)
            }
            try FileSystemService.shared.writeText(pending.newText, to: pending.fileURL)
            
            // VERIFICATION
            let verificationText = try FileSystemService.shared.readText(from: pending.fileURL)
            if verificationText != pending.newText {
                appendActivity(.error(message: "File verification failed"), details: "The written file content does not match the requested content!")
                throw NSError(domain: "AgentViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "File verification mismatch."])
            }
            
            projectViewModel?.refreshWorkspace()
            
            await MainActor.run {
                editorViewModel?.openFile(at: pending.fileURL)
                editorViewModel?.reloadText(for: pending.fileURL)
            }
            
            if pending.type == .create {
                appendActivity(.created(file: pending.fileURL.lastPathComponent))
            } else {
                appendActivity(.editing(file: pending.fileURL.lastPathComponent, added: 0, removed: 0))
            }
            
            Task { await coordinator.runQA(fileChanged: pending.fileURL.lastPathComponent) }
        } catch {
            appendActivity(.error(message: "File action failed"), details: error.localizedDescription)
            pendingFileAction = nil
            throw error
        }
        pendingFileAction = nil
    }

    private func deleteFile(relativePath: String, baseURL: URL) async {
        let targetURL = baseURL.appendingPathComponent(relativePath)
        do {
            try FileSystemService.shared.deleteItem(at: targetURL)
            projectViewModel?.refreshWorkspace()
            appendActivity(.deleted(file: relativePath))
        } catch {
            appendActivity(.error(message: "Delete failed"), details: error.localizedDescription)
        }
    }

    private func runTerminalCommand(_ command: String) async {
        appendActivity(.ranCommand(command: command), details: "Executing...")
        await terminalManager?.appendOutput("$ \(command)\n")
        _ = await terminalManager?.execute(command: command)
    }

    private func performGitStatus(baseURL: URL) async {
        appendActivity(.ranCommand(command: "git status"), details: "Fetching repository status.")
        do {
            let result = try await gitService.status(at: baseURL)
            appendActivity(.info(message: "Git status"), details: result.isEmpty ? "Clean working tree." : result)
        } catch {
            appendActivity(.error(message: "Git status failed"), details: error.localizedDescription)
        }
    }

    private func performGitDiff(relativePath: String?, baseURL: URL) async {
        appendActivity(.ranCommand(command: "git diff \(relativePath ?? "")"), details: "Computing git diff.")
        do {
            let fileURL = relativePath.flatMap { baseURL.appendingPathComponent($0) }
            let result = try await gitService.diff(at: baseURL, file: fileURL)
            appendActivity(.info(message: "Git diff"), details: result.isEmpty ? "No changes." : result)
        } catch {
            appendActivity(.error(message: "Git diff failed"), details: error.localizedDescription)
        }
    }

    private func listFiles(relativePath: String, baseURL: URL) async {
        let pathURL = baseURL.appendingPathComponent(relativePath)
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: pathURL.path)
            appendActivity(.info(message: "Directory listing"), details: contents.joined(separator: ", "))
        } catch {
            appendActivity(.error(message: "List failed"), details: error.localizedDescription)
        }
    }
}

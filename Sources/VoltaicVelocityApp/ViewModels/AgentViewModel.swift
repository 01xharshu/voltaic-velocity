import Foundation
import OllamaKit

@MainActor
public enum AutonomyLevel: String, CaseIterable {
    case manual = "Manual Approval"
    case autonomous = "Fully Autonomous"
}

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var chatMessages: [ChatMessage] = [ChatMessage(role: .system, text: "Voltaic Velocity AI agent ready. Use natural language to modify the project, write code, or run terminal commands.")]
    @Published var promptText = ""
    @Published var selectedModel = "qwen2.5-coder:7b"
    @Published var isAgentModePlanning = true
    @Published var isShowingCommandPalette = false
    @Published var isProcessing = false
    @Published var pendingFileAction: PendingFileAction?
    @Published var ollamaReachable = true
    @Published var availableModels: [String] = ["qwen2.5-coder:7b"]
    @Published var isMultiAgentEnabled = false
    @Published var autonomyLevel: AutonomyLevel = .manual

    private var currentTask: Task<Void, Never>?

    private let service = OllamaService()
    private let gitService = GitService()
    private var projectViewModel: ProjectViewModel?
    private var editorViewModel: EditorViewModel?
    private var terminalViewModel: TerminalViewModel?
    private let coordinator = MultiAgentCoordinator()

    init() {
        self.coordinator.agentViewModel = self
        Task {
            await fetchAvailableModels()
        }
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

    func link(projectViewModel: ProjectViewModel, editorViewModel: EditorViewModel, terminalViewModel: TerminalViewModel) {
        self.projectViewModel = projectViewModel
        self.editorViewModel = editorViewModel
        self.terminalViewModel = terminalViewModel
    }

    func startNewChat() {
        chatMessages = [ChatMessage(role: .system, text: "You are the Voltaic Velocity project agent. Use tool calls to modify files, run terminal commands, and analyze the workspace.")]
        promptText = ""
    }

    func sendPrompt() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        chatMessages.append(ChatMessage(role: .user, text: userText))
        promptText = ""
        isProcessing = true

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
    }

    private func streamResponse(for userText: String) async {
        let startTime = Date()
        guard let _ = projectViewModel, let _ = editorViewModel, let _ = terminalViewModel else {
            appendActivity(.error(message: "Missing context"), details: "Project and editor context must be linked before sending prompts.")
            isProcessing = false
            return
        }

        var messages = buildChatMessages(for: userText)


        let assistant = ChatMessage(role: .assistant, text: "")
        chatMessages.append(assistant)

        let maxIterations = 5
        var currentIteration = 0
        var taskCompleted = false

        while currentIteration < maxIterations && !taskCompleted && isProcessing {
            currentIteration += 1
            var accumulatedText = ""

            do {
                let stream = await service.streamChat(model: selectedModel, messages: messages, tools: nil)
                for try await response in stream {
                    if let chunk = response.message?.content {
                        accumulatedText += chunk
                    }

                    if response.done {
                        break
                    }
                }
                
                // Add to conversation history
                messages.append(OKChatRequestData.Message(role: .assistant, content: accumulatedText))

                // --- Determine what the model returned ---
                let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)

                var extractedJSON: String? = nil
                var matchRange: Range<String.Index>? = nil

                if let range = accumulatedText.range(of: "(?s)(?<=<tool_call>).*?(?=</tool_call>)", options: [.regularExpression]) {
                    extractedJSON = String(accumulatedText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    matchRange = accumulatedText.range(of: "(?s)<tool_call>.*?</tool_call>", options: [.regularExpression])
                } else if let range = accumulatedText.range(of: "(?s)(?<=```json).*?(?=```)", options: [.regularExpression]) {
                    let maybeJson = String(accumulatedText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if maybeJson.hasPrefix("{") && maybeJson.contains("\"name\"") {
                        extractedJSON = maybeJson
                        matchRange = accumulatedText.range(of: "(?s)```json.*?```", options: [.regularExpression])
                    }
                }

                if let jsonString = extractedJSON, let fullMatchRange = matchRange {
                    // Case 2: Model used <tool_call> tags or ```json block
                    var explanationText = accumulatedText
                    explanationText.removeSubrange(fullMatchRange)
                    explanationText = explanationText.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
                        chatMessages[lastIndex].text = explanationText
                    }

                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let name = json["name"] as? String {
                        var argMap: [String: OKJSONValue] = [:]
                        if let dict = json["arguments"] as? [String: Any] {
                            for (k, v) in dict {
                                if let str = v as? String { argMap[k] = .string(str) }
                            }
                        }
                        appendActivity(.ranCommand(command: "Using tool: \(name)"), details: "Executing...")
                        let resultStr = await handleToolCall(name: name, arguments: .object(argMap))
                        messages.append(OKChatRequestData.Message(role: .user, content: "Tool '\(name)' result:\n\(resultStr)"))
                        if name == "ask_user" { taskCompleted = true }
                    } else {
                        taskCompleted = true
                    }

                } else if trimmed.hasPrefix("{") && trimmed.hasSuffix("}"),
                          let data = trimmed.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let name = json["name"] as? String {
                    // Case 3: Raw JSON tool call (model ignored <tool_call> instruction)
                    // Do NOT show JSON in the chat bubble — replace with a human message
                    if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
                        let args = json["arguments"] as? [String: Any]
                        let path = args?["path"] as? String ?? ""
                        chatMessages[lastIndex].text = "I'll \(name.replacingOccurrences(of: "_", with: " ")) \(path.isEmpty ? "" : "`\(path)`") for you."
                    }
                    var argMap: [String: OKJSONValue] = [:]
                    if let dict = json["arguments"] as? [String: Any] {
                        for (k, v) in dict {
                            if let str = v as? String { argMap[k] = .string(str) }
                        }
                    }
                    appendActivity(.ranCommand(command: "Using tool: \(name)"), details: "Executing...")
                    let resultStr = await handleToolCall(name: name, arguments: .object(argMap))
                    messages.append(OKChatRequestData.Message(role: .user, content: "Tool '\(name)' result:\n\(resultStr)"))
                    if name == "ask_user" { taskCompleted = true }

                } else {
                    if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
                        if trimmed.isEmpty {
                            chatMessages[lastIndex].text = "I encountered an error or generated an empty response. Please try rephrasing."
                            appendActivity(.error(message: "Empty response"), details: "The model returned nothing and used no tools.")
                        } else {
                            chatMessages[lastIndex].text = trimmed
                            appendActivity(.info(message: "Completed"), details: "Agent completed the request.")
                        }
                    }
                    taskCompleted = true
                }
                
            } catch {
                appendActivity(.error(message: "Agent failed"), details: error.localizedDescription)
                if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
                    chatMessages[lastIndex].text += "\n⚠️ Error: \(error.localizedDescription)"
                }
                break
            }
        }

        if currentIteration >= maxIterations && !taskCompleted {
            appendActivity(.error(message: "Max iterations reached"), details: "The agent stopped after 5 tool loops.")
            if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
                chatMessages[lastIndex].text += "\n[Stopped after maximum iterations]"
            }
        }

        if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
            chatMessages[lastIndex].totalWorkTime = Date().timeIntervalSince(startTime)
        }

        isProcessing = false
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
                        let truncated = content.count > 6000 ? String(content.prefix(6000)) + "\n... [Truncated]" : content
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

        return """
        You are Volt, a friendly and helpful AI coding assistant inside Voltaic Velocity, a native macOS IDE.

        CRITICAL RULES:
        1. For normal conversation (greetings, questions, explanations), respond with plain text. Do NOT use any tools.
        2. ONLY use tool calls when the user explicitly asks you to create, edit, delete files, or run commands.
        3. You MUST NEVER output raw code blocks (like ```html or ```js) to create or edit files. You MUST use the `create_file` or `edit_file` tools. If you output raw code blocks, the files will not be saved!
        4. When you DO need to use a tool, respond with a brief explanation of what you will do FIRST, then on a new line output the tool call JSON wrapped in <tool_call> tags like: <tool_call>{"name": "create_file", "arguments": {"path": "...", "content": "..."}}</tool_call>
        5. Never output raw JSON without explanation. Always talk to the user like a human.
        6. If asked to create a website or HTML, make it beautiful with modern CSS, animations, and responsive design.
        7. When you successfully complete a task, proactively suggest 2-3 relevant new features or improvements the user could add next to keep iterating!

        Available tools:
        - read_file(file_path) — Read the contents of a file
        - create_file(path, content) — Create a new file
        - edit_file(path, content) — Replace entire file contents
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

        Current project:
        \(projectDescription)

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
                    "description": .string("Edit an existing file to update content."),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "path": .object([
                                "type": .string("string"),
                                "description": .string("Relative path inside the project folder."),
                            ]),
                            "content": .object([
                                "type": .string("string"),
                                "description": .string("The updated file contents."),
                            ]),
                        ]),
                        "required": .array([.string("path"), .string("content")])
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
                let existingText = try FileSystemService.shared.readText(from: targetURL)
                let components = existingText.components(separatedBy: oldString)
                if components.count - 1 == 0 {
                    return "Error: old_string not found in file."
                } else if components.count - 1 > 1 {
                    return "Error: old_string occurs \(components.count - 1) times in the file. It must occur exactly ONCE to prevent global corruption. Please provide a larger, more unique code snippet."
                }
                let newText = existingText.replacingOccurrences(of: oldString, with: newString)
                await processFileAction(type: .edit, relativePath: path, content: newText, baseURL: projectURL)
                return "Action queued for user review. Do not assume the file is updated until the user approves it."
            } catch {
                return "Error preparing replace_in_file: \(error.localizedDescription)"
            }
            
        case "edit_file":
            guard let path = args["path"]?.stringValue(), let content = args["content"]?.stringValue() else {
                appendActivity(.error(message: "edit_file missing arguments"), details: "Missing path or content.")
                return "Error: Missing path or content."
            }
            await processFileAction(type: .edit, relativePath: path, content: content, baseURL: projectURL)
            return "Edit action queued for user review."

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
            await terminalViewModel?.appendOutput("$ \(command)\n")
            if let output = await terminalViewModel?.execute(command: command) {
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
                if let output = await terminalViewModel?.execute(command: command) {
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
            await terminalViewModel?.appendOutput("$ \(command)\n")
            if let output = await terminalViewModel?.execute(command: command) {
                return output
            }
            return "Test command executed but no output returned."
            
        case "analyze_performance":
            guard let command = args["command"]?.stringValue() else { return "Error: Missing command." }
            appendActivity(.profiling(command: command), details: "Profiling command")
            let timeCommand = "time \(command)"
            await terminalViewModel?.appendOutput("$ \(timeCommand)\n")
            if let output = await terminalViewModel?.execute(command: timeCommand) {
                return output
            }
            return "Profile command executed but no output returned."
            
        case "ask_user":
            guard let question = args["question"]?.stringValue() else { return "Error: Missing question." }
            appendActivity(.askingUser(question: question), details: "Waiting for user input")
            return "User was asked: \(question). The agent should stop and wait for their reply in the chat."
            
        default:
            appendActivity(.error(message: "Unknown tool call"), details: "Tool '\(name)' is not supported.")
            return "Error: Tool '\(name)' is not supported."
        }
    }

    private func processFileAction(type: PendingFileAction.ActionType, relativePath: String, content: String, baseURL: URL) async {
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
                Task { await self.applyPendingAction() }
            }
        )

        if autonomyLevel == .autonomous {
            appendActivity(.info(message: summary), details: "Automatically applying action in Autonomous mode.")
            await applyPendingAction()
        } else {
            appendActivity(.info(message: summary), details: "Review or confirm the generated code before applying.")
        }
    }

    private func applyPendingAction() async {
        guard let pending = pendingFileAction else { return }
        do {
            switch pending.type {
            case .create:
                let directory = pending.fileURL.deletingLastPathComponent()
                try FileSystemService.shared.createFolderIfNeeded(at: directory)
                try FileSystemService.shared.writeText(pending.newText, to: pending.fileURL)
                projectViewModel?.refreshWorkspace()
                editorViewModel?.openFile(at: pending.fileURL)
                appendActivity(.created(file: pending.fileURL.lastPathComponent))
                
                Task { await coordinator.runQA(fileChanged: pending.fileURL.lastPathComponent) }
                
            case .edit:
                try FileSystemService.shared.writeText(pending.newText, to: pending.fileURL)
                projectViewModel?.refreshWorkspace()
                editorViewModel?.openFile(at: pending.fileURL)
                appendActivity(.editing(file: pending.fileURL.lastPathComponent, added: 0, removed: 0))
                
                Task { await coordinator.runQA(fileChanged: pending.fileURL.lastPathComponent) }
            }
        } catch {
            appendActivity(.error(message: "File action failed"), details: error.localizedDescription)
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
        await terminalViewModel?.appendOutput("$ \(command)\n")
        _ = await terminalViewModel?.execute(command: command)
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

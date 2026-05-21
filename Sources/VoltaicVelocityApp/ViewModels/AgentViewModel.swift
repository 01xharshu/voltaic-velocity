import Foundation
import OllamaKit

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var chatMessages: [ChatMessage] = [ChatMessage(role: .system, text: "Voltaic Velocity AI agent ready. Use natural language to modify the project, write code, or run terminal commands.")]
    @Published var agentSteps: [AgentStep] = []
    @Published var promptText = ""
    @Published var selectedModel = "qwen2.5-coder:7b"
    @Published var isAgentModePlanning = true
    @Published var isShowingCommandPalette = false
    @Published var isProcessing = false
    @Published var pendingFileAction: PendingFileAction?
    @Published var ollamaReachable = true
    @Published var availableModels: [String] = ["qwen2.5-coder:7b"]
    @Published var isMultiAgentEnabled = false

    private let service = OllamaService()
    private let gitService = GitService()
    private var projectViewModel: ProjectViewModel?
    private var editorViewModel: EditorViewModel?
    private var terminalViewModel: TerminalViewModel?

    func link(projectViewModel: ProjectViewModel, editorViewModel: EditorViewModel, terminalViewModel: TerminalViewModel) {
        self.projectViewModel = projectViewModel
        self.editorViewModel = editorViewModel
        self.terminalViewModel = terminalViewModel
    }

    func startNewChat() {
        chatMessages = [ChatMessage(role: .system, text: "You are the Voltaic Velocity project agent. Use tool calls to modify files, run terminal commands, and analyze the workspace.")]
        agentSteps = []
        promptText = ""
    }

    func sendPrompt() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userText = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        chatMessages.append(ChatMessage(role: .user, text: userText))
        promptText = ""
        isProcessing = true
        agentSteps.append(AgentStep(title: "Planning", details: "Preparing context for \(selectedModel) and analyzing files...", status: .running))

        Task {
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
        appendSystemStep(title: "Stopped", details: "User interrupted the agent.", status: .warning)
    }

    private func streamResponse(for userText: String) async {
        guard let projectViewModel, let editorViewModel, let terminalViewModel else {
            appendSystemStep(title: "Missing context", details: "Project and editor context must be linked before sending prompts.", status: .failure)
            isProcessing = false
            return
        }

        var messages = buildChatMessages(for: userText)
        let tools = makeToolDefinitions()

        let assistant = ChatMessage(role: .assistant, text: "")
        chatMessages.append(assistant)

        let maxIterations = 5
        var currentIteration = 0
        var taskCompleted = false

        while currentIteration < maxIterations && !taskCompleted && isProcessing {
            currentIteration += 1
            var accumulatedText = ""
            var toolCallsMade: [OKChatResponse.Message.ToolCall] = []
            
            var inPlanBlock = false
            var planStepID: UUID?

            do {
                let stream = await service.streamChat(model: selectedModel, messages: messages, tools: tools)
                for try await response in stream {
                    if let content = response.message?.content {
                        let incoming = content
                        if incoming.count > accumulatedText.count {
                            let suffix = String(incoming.dropFirst(accumulatedText.count))
                            accumulatedText = incoming
                            
                            // Plan block logic
                            if !inPlanBlock, accumulatedText.contains("<plan>") {
                                inPlanBlock = true
                                let step = AgentStep(title: "Implementation Plan", details: "Thinking...", status: .running)
                                planStepID = step.id
                                agentSteps.append(step)
                            }
                            
                            if inPlanBlock {
                                let planStart = accumulatedText.range(of: "<plan>")?.upperBound ?? accumulatedText.startIndex
                                let planEnd = accumulatedText.range(of: "</plan>")?.lowerBound ?? accumulatedText.endIndex
                                
                                if planStart <= planEnd {
                                    let planText = String(accumulatedText[planStart..<planEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if let stepID = planStepID,
                                       let stepIndex = agentSteps.firstIndex(where: { $0.id == stepID }) {
                                        agentSteps[stepIndex].details = planText.isEmpty ? "Thinking..." : planText
                                    }
                                }
                                
                                if accumulatedText.contains("</plan>") {
                                    inPlanBlock = false
                                    if let stepID = planStepID,
                                       let stepIndex = agentSteps.firstIndex(where: { $0.id == stepID }) {
                                        agentSteps[stepIndex].status = .success
                                    }
                                }
                            } else {
                                if accumulatedText.contains("</plan>") {
                                    let cleanText = accumulatedText.replacingOccurrences(of: "(?s)<plan>.*?</plan>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) {
                                        chatMessages[lastIndex].text = cleanText
                                    }
                                } else {
                                    appendAssistantText(suffix)
                                }
                            }
                        }
                    }

                    if let tCalls = response.message?.toolCalls, !tCalls.isEmpty {
                        toolCallsMade.append(contentsOf: tCalls)
                    }

                    if response.done {
                        break
                    }
                }
                
                messages.append(OKChatRequestData.Message(role: .assistant, content: accumulatedText))

                if toolCallsMade.isEmpty {
                    // Manual tool call fallback
                    if let range = accumulatedText.range(of: "(?s)(?<=<tool_call>).*?(?=</tool_call>)", options: [.regularExpression]) {
                        let jsonString = String(accumulatedText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let data = jsonString.data(using: String.Encoding.utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let name = json["name"] as? String {
                            
                            var argMap: [String: OKJSONValue] = [:]
                            if let dict = json["arguments"] as? [String: Any] {
                                for (k, v) in dict {
                                    if let str = v as? String { argMap[k] = .string(str) }
                                }
                            }
                            
                            let resultStr = await handleToolCall(name: name, arguments: .object(argMap))
                            messages.append(OKChatRequestData.Message(role: .user, content: "Tool '\(name)' execution result:\n\(resultStr)"))
                        } else {
                            taskCompleted = true // Parse failed, end loop
                        }
                    } else {
                        taskCompleted = true // No tool calls at all, finished
                        appendSystemStep(title: "Completed", details: "Agent completed the request.", status: .success)
                    }
                } else {
                    // Execute Ollama native tool calls
                    var resultsText = ""
                    for toolCall in toolCallsMade {
                        if let function = toolCall.function, let name = function.name {
                            let resultStr = await handleToolCall(name: name, arguments: function.arguments)
                            resultsText += "Tool '\(name)' execution result:\n\(resultStr)\n\n"
                        }
                    }
                    messages.append(OKChatRequestData.Message(role: .user, content: resultsText))
                }
                
            } catch {
                appendSystemStep(title: "Agent failed", details: error.localizedDescription, status: .failure)
                appendAssistantText("\n[Error] \(error.localizedDescription)")
                break // Break out of loop on error
            }
        }

        if currentIteration >= maxIterations && !taskCompleted {
            appendSystemStep(title: "Max iterations reached", details: "The agent stopped after 5 tool loops.", status: .warning)
            appendAssistantText("\n[Stopped after maximum iterations]")
        }

        isProcessing = false
    }

    private func buildChatMessages(for prompt: String) -> [OKChatRequestData.Message] {
        var messages: [OKChatRequestData.Message] = []
        for item in chatMessages {
            let role: OKChatRequestData.Message.Role = item.role == .user ? .user : item.role == .assistant ? .assistant : .system
            messages.append(OKChatRequestData.Message(role: role, content: item.text))
        }

        let systemPrompt = buildSystemPrompt()
        messages.insert(OKChatRequestData.Message(role: .system, content: systemPrompt), at: 0)
        messages.append(OKChatRequestData.Message(role: .user, content: prompt))
        return messages
    }

    private func buildSystemPrompt() -> String {
        let projectDescription = projectViewModel?.projectStructureDescription ?? "No project open."
        let fileNames = projectViewModel?.workspaceItems.map { $0.name }.joined(separator: ", ") ?? "None"

        return "You are Voltaic Velocity, a native macOS project agent. The user asks for IDE changes, file creation, editing, deletion, terminal execution, or git workflow support. Use tool calls to create or modify files, run commands, inspect git status, or show git diffs.\n\nProject structure:\n\(projectDescription)\n\nOpen files: \(fileNames)\n\nTool names:\n- create_file(path, content)\n- edit_file(path, content)\n- delete_file(path)\n- run_terminal(command)\n- list_files(path)\n- git_status()\n- git_diff(path)\n\nAlways provide a clear action plan and use the tool call format only when mutating the filesystem or terminal."
    }

    private func appendAssistantText(_ text: String) {
        guard let lastIndex = chatMessages.lastIndex(where: { $0.role == .assistant }) else { return }
        chatMessages[lastIndex].text += text
    }

    private func appendSystemStep(title: String, details: String, status: AgentStep.Status) {
        agentSteps.append(AgentStep(title: title, details: details, status: status))
    }

    private func makeToolDefinitions() -> [OKJSONValue] {
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
            ]
        ]
        return toolObjects.map { .object($0) }
    }

    private func handleToolCall(name: String, arguments: OKJSONValue?) async -> String {
        guard let projectURL = projectViewModel?.projectURL else {
            appendSystemStep(title: "No project opened", details: "The agent attempted a tool call before a project folder was opened.", status: .failure)
            return "Error: No project opened."
        }

        let args = arguments?.objectValue() ?? [:]
        switch name {
        case "create_file":
            guard let path = args["path"]?.stringValue(), let content = args["content"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "create_file missing required arguments.", status: .warning)
                return "Error: Missing path or content."
            }
            // Create immediately
            let targetURL = projectURL.appendingPathComponent(path)
            let directory = targetURL.deletingLastPathComponent()
            do {
                try FileSystemService.shared.createFolderIfNeeded(at: directory)
                try FileSystemService.shared.writeText(content, to: targetURL)
                projectViewModel?.refreshWorkspace()
                appendSystemStep(title: "Created \(targetURL.lastPathComponent)", details: "Created file.", status: .success)
                return "File successfully created at \(path)."
            } catch {
                return "Error creating file: \(error.localizedDescription)"
            }

        case "read_file":
            guard let path = args["file_path"]?.stringValue() else {
                return "Error: Missing file_path."
            }
            let targetURL = projectURL.appendingPathComponent(path)
            do {
                let content = try FileSystemService.shared.readText(from: targetURL)
                appendSystemStep(title: "Read \(path)", details: "Read \(content.count) characters.", status: .success)
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
                if !existingText.contains(oldString) {
                    return "Error: old_string not found in file."
                }
                let newText = existingText.replacingOccurrences(of: oldString, with: newString)
                await processFileAction(type: .edit, relativePath: path, content: newText, baseURL: projectURL)
                return "Action queued for user review. Do not assume the file is updated until the user approves it."
            } catch {
                return "Error preparing replace_in_file: \(error.localizedDescription)"
            }
            
        case "edit_file":
            // Fallback for edit_file if model still uses it
            guard let path = args["path"]?.stringValue(), let content = args["content"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "edit_file missing required arguments.", status: .warning)
                return "Error: Missing path or content."
            }
            await processFileAction(type: .edit, relativePath: path, content: content, baseURL: projectURL)
            return "Edit action queued for user review."

        case "delete_file":
            guard let path = args["path"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "delete_file missing required arguments.", status: .warning)
                return "Error: Missing path."
            }
            await deleteFile(relativePath: path, baseURL: projectURL)
            return "Delete action requested."

        case "run_terminal":
            guard let command = args["command"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "run_terminal missing required arguments.", status: .warning)
                return "Error: Missing command."
            }
            appendSystemStep(title: "Running command", details: command, status: .running)
            await terminalViewModel?.appendOutput("$ \(command)\n")
            if let output = await terminalViewModel?.execute(command: command) {
                appendSystemStep(title: "Command finished", details: "Executed \(command)", status: .success)
                return output
            }
            return "Command executed but no output returned."

        case "list_files":
            let path = args["path"]?.stringValue() ?? "."
            await listFiles(relativePath: path, baseURL: projectURL)
            return "Directory listing requested."
            
        case "git_status":
            await performGitStatus(baseURL: projectURL)
            return "Git status requested."
            
        case "git_diff":
            let path = args["path"]?.stringValue()
            await performGitDiff(relativePath: path, baseURL: projectURL)
            return "Git diff requested."
            
        default:
            appendSystemStep(title: "Unknown tool call", details: "Tool '\(name)' is not supported.", status: .warning)
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

        appendSystemStep(title: summary, details: "Review or confirm the generated code before applying.", status: .pending)
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
                appendSystemStep(title: "File created", details: pending.fileURL.lastPathComponent, status: .success)
            case .edit:
                try FileSystemService.shared.writeText(pending.newText, to: pending.fileURL)
                projectViewModel?.refreshWorkspace()
                editorViewModel?.openFile(at: pending.fileURL)
                appendSystemStep(title: "File edited", details: pending.fileURL.lastPathComponent, status: .success)
            }
        } catch {
            appendSystemStep(title: "File action failed", details: error.localizedDescription, status: .failure)
        }
        pendingFileAction = nil
    }

    private func deleteFile(relativePath: String, baseURL: URL) async {
        let targetURL = baseURL.appendingPathComponent(relativePath)
        do {
            try FileSystemService.shared.deleteItem(at: targetURL)
            projectViewModel?.refreshWorkspace()
            appendSystemStep(title: "File deleted", details: relativePath, status: .success)
        } catch {
            appendSystemStep(title: "Delete failed", details: error.localizedDescription, status: .failure)
        }
    }

    private func runTerminalCommand(_ command: String) async {
        appendSystemStep(title: "Running command", details: command, status: .running)
        await terminalViewModel?.appendOutput("$ \(command)\n")
        await terminalViewModel?.execute(command: command)
    }

    private func performGitStatus(baseURL: URL) async {
        appendSystemStep(title: "Git status", details: "Fetching repository status.", status: .running)
        do {
            let result = try await gitService.status(at: baseURL)
            appendSystemStep(title: "Git status", details: result.isEmpty ? "Clean working tree." : result, status: .success)
        } catch {
            appendSystemStep(title: "Git status failed", details: error.localizedDescription, status: .failure)
        }
    }

    private func performGitDiff(relativePath: String?, baseURL: URL) async {
        appendSystemStep(title: "Git diff", details: "Computing git diff.", status: .running)
        do {
            let fileURL = relativePath.flatMap { baseURL.appendingPathComponent($0) }
            let result = try await gitService.diff(at: baseURL, file: fileURL)
            appendSystemStep(title: "Git diff", details: result.isEmpty ? "No changes." : result, status: .success)
        } catch {
            appendSystemStep(title: "Git diff failed", details: error.localizedDescription, status: .failure)
        }
    }

    private func listFiles(relativePath: String, baseURL: URL) async {
        let pathURL = baseURL.appendingPathComponent(relativePath)
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: pathURL.path)
            appendSystemStep(title: "Directory listing", details: contents.joined(separator: ", "), status: .success)
        } catch {
            appendSystemStep(title: "List failed", details: error.localizedDescription, status: .failure)
        }
    }
}

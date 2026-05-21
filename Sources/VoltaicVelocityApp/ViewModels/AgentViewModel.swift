import Foundation
import OllamaKit

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var chatMessages: [ChatMessage] = [ChatMessage(role: .system, text: "Voltaic Velocity AI agent ready. Use natural language to modify the project, write code, or run terminal commands.")]
    @Published var agentSteps: [AgentStep] = []
    @Published var promptText = ""
    @Published var selectedModel = "qwen2.5-coder"
    @Published var isAgentModePlanning = true
    @Published var isShowingCommandPalette = false
    @Published var isProcessing = false
    @Published var pendingFileAction: PendingFileAction?

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

    private func streamResponse(for userText: String) async {
        guard let projectViewModel, let editorViewModel, let terminalViewModel else {
            appendSystemStep(title: "Missing context", details: "Project and editor context must be linked before sending prompts.", status: .failure)
            isProcessing = false
            return
        }

        let messages = buildChatMessages(for: userText)
        let tools = makeToolDefinitions()

        var assistant = ChatMessage(role: .assistant, text: "")
        chatMessages.append(assistant)
        var accumulatedText = ""
        var toolCallHandled = false

        do {
            for try await response in service.streamChat(model: selectedModel, messages: messages, tools: tools) {
                if let content = response.message?.content {
                    let incoming = content
                    if incoming.count > accumulatedText.count {
                        let suffix = String(incoming.dropFirst(accumulatedText.count))
                        accumulatedText = incoming
                        appendAssistantText(suffix)
                    }
                }

                if let toolCalls = response.message?.toolCalls, !toolCalls.isEmpty {
                    for toolCall in toolCalls {
                        if let function = toolCall.function, let name = function.name {
                            toolCallHandled = true
                            await handleToolCall(name: name, arguments: function.arguments)
                        }
                    }
                }

                if response.done {
                    break
                }
            }
            appendSystemStep(title: "Completed", details: "Agent completed the request.", status: .success)
        } catch {
            appendSystemStep(title: "Agent failed", details: error.localizedDescription, status: .failure)
            appendAssistantText("\n[Error] \(error.localizedDescription)")
        }

        if toolCallHandled {
            appendSystemStep(title: "Action executed", details: "Tool calls were processed and project state updated.", status: .success)
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
                        "properties": .object([]),
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

    private func handleToolCall(name: String, arguments: OKJSONValue?) async {
        guard let projectURL = projectViewModel?.projectURL else {
            appendSystemStep(title: "No project opened", details: "The agent attempted a tool call before a project folder was opened.", status: .failure)
            return
        }

        let args = arguments?.objectValue() ?? [:]
        switch name {
        case "create_file":
            guard let path = args["path"]?.stringValue(), let content = args["content"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "create_file missing required arguments.", status: .warning)
                return
            }
            await processFileAction(type: .create, relativePath: path, content: content, baseURL: projectURL)
        case "edit_file":
            guard let path = args["path"]?.stringValue(), let content = args["content"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "edit_file missing required arguments.", status: .warning)
                return
            }
            await processFileAction(type: .edit, relativePath: path, content: content, baseURL: projectURL)
        case "delete_file":
            guard let path = args["path"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "delete_file missing required arguments.", status: .warning)
                return
            }
            await deleteFile(relativePath: path, baseURL: projectURL)
        case "run_terminal":
            guard let command = args["command"]?.stringValue() else {
                appendSystemStep(title: "Invalid tool call", details: "run_terminal missing required arguments.", status: .warning)
                return
            }
            await runTerminalCommand(command)
        case "list_files":
            let path = args["path"]?.stringValue() ?? "."
            await listFiles(relativePath: path, baseURL: projectURL)
        case "git_status":
            await performGitStatus(baseURL: projectURL)
        case "git_diff":
            let path = args["path"]?.stringValue()
            await performGitDiff(relativePath: path, baseURL: projectURL)
        default:
            appendSystemStep(title: "Unknown tool call", details: "Tool '\(name)' is not supported.", status: .warning)
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

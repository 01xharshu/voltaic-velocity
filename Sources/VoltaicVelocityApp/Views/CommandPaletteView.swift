import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @ObservedObject var agentViewModel: AgentViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var terminalManager: TerminalManagerViewModel
    @ObservedObject var gitViewModel: GitViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Command Palette")
                .font(.title)
                .bold()
            TextField("Search commands…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            List(filteredCommands) { command in
                Button(action: {
                    command.action()
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(command.title)
                            Text(command.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .padding(.top, 20)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var filteredCommands: [PaletteCommand] {
        let commands = [
            PaletteCommand(title: "Open Project", subtitle: "Select a folder to load as a workspace.") {
                projectViewModel.openProjectFolder()
            },
            PaletteCommand(title: "New Chat", subtitle: "Start a fresh AI conversation.") {
                agentViewModel.startNewChat()
            },
            PaletteCommand(title: "Save Active File", subtitle: "Write the current file to disk.") {
                editorViewModel.saveActiveFile()
            },
            PaletteCommand(title: "Git Status", subtitle: "Show the current git status for the workspace.") {
                Task {
                    await gitViewModel.gitStatus(projectURL: projectViewModel.projectURL)
                }
            },
            PaletteCommand(title: "View Repository Diff", subtitle: "Show the current git diff for the repository.") {
                Task {
                    await gitViewModel.gitDiff(projectURL: projectViewModel.projectURL)
                }
            },
            PaletteCommand(title: "View Active File Diff", subtitle: "Show git diff for the currently active file.") {
                Task {
                    await gitViewModel.gitDiff(projectURL: projectViewModel.projectURL, fileURL: editorViewModel.activeFile?.url)
                }
            },
            PaletteCommand(title: "View Unsaved Diff", subtitle: "Compare active editor content with disk state.") {
                if let active = editorViewModel.activeFile {
                    gitViewModel.unsavedDiff(for: active)
                }
            },
            PaletteCommand(title: "Create Git Commit", subtitle: "Commit staged and modified files with a message.") {
                presentCommitAlert()
            },
            PaletteCommand(title: "Run Terminal Command", subtitle: "Enter a shell command directly in the terminal.") {
                terminalManager.activeTerminal?.inputText = ""
                terminalManager.activeTerminal?.runCurrentCommand()
                dismiss()
            }
        ]
        guard !query.isEmpty else { return commands }
        return commands.filter { command in
            command.title.localizedCaseInsensitiveContains(query) || command.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private func presentCommitAlert() {
        let alert = NSAlert()
        alert.messageText = "Git Commit"
        alert.informativeText = "Enter a commit message for the repository."
        alert.alertStyle = .informational
        let input = NSTextField(string: "")
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Commit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let message = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                await gitViewModel.gitCommit(message: message, projectURL: projectViewModel.projectURL)
            }
        }
    }
}

private struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let action: () -> Void
}

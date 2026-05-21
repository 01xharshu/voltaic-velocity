import Foundation

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var output = ""
    @Published var inputText = ""
    @Published var workingDirectory: URL?
    @Published var isRunningCommand = false

    private let service = TerminalService()

    func restoreWorkingDirectory(from projectURL: URL?) {
        if let projectURL {
            workingDirectory = projectURL
        }
    }

    func runCurrentCommand() {
        let command = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        inputText = ""
        Task {
            await appendOutput("$ \(command)\n")
            await execute(command: command)
        }
    }

    func execute(command: String) async {
        isRunningCommand = true
        defer { isRunningCommand = false }

        do {
            let results = try await service.run(command: command, in: workingDirectory)
            await appendOutput(results + "\n")
        } catch {
            await appendOutput("Error: \(error.localizedDescription)\n")
        }
    }

    func appendOutput(_ text: String) async {
        output += text
    }
}

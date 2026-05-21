import Foundation

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var output = ""
    @Published var inputText = ""
    @Published var workingDirectory: URL?
    @Published var isRunningCommand = false

    private let service = TerminalService()
    private var sessionStarted = false

    func restoreWorkingDirectory(from projectURL: URL?) {
        if let projectURL {
            workingDirectory = projectURL
        }
        startSessionIfNeeded()
    }

    func startSessionIfNeeded() {
        guard !sessionStarted else { return }
        sessionStarted = true
        service.start(in: workingDirectory) { [weak self] text in
            DispatchQueue.main.async {
                self?.output += text
            }
        }
    }

    /// Send raw characters directly to the shell's stdin (for NSView keyboard capture)
    func sendRawInput(_ chars: String) {
        service.send(raw: chars)
    }

    /// Legacy: run a command string (used by the separate input field fallback & agent tool calls)
    func runCurrentCommand() {
        let command = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        inputText = ""
        service.send(command: command)
    }

    /// One-shot execution for agent tool calls
    func execute(command: String) async -> String {
        isRunningCommand = true
        defer { isRunningCommand = false }

        do {
            let result = try await service.run(command: command, in: workingDirectory)
            // Intentionally not appending to `output` so it doesn't pollute the user's main terminal.
            return result
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func appendOutput(_ text: String) async {
        output += text
    }

    func clearOutput() {
        output = ""
    }

    deinit {
        service.stop()
    }
}

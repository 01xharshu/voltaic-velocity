import Foundation
import Combine

@MainActor
final class TerminalManagerViewModel: ObservableObject {
    @Published var terminals: [TerminalViewModel] = []
    @Published var activeTerminalId: UUID?
    
    // Background execution for the AI Agent so it doesn't pollute user terminals
    private let backgroundService = TerminalService()

    init() {
        // Create an initial terminal
        createTerminal()
    }

    func restoreWorkingDirectory(from projectURL: URL?) {
        for terminal in terminals {
            terminal.restoreWorkingDirectory(from: projectURL)
        }
    }

    @discardableResult
    func createTerminal() -> TerminalViewModel {
        let newTerminal = TerminalViewModel()
        let count = terminals.count + 1
        newTerminal.name = "zsh (\(count))"
        terminals.append(newTerminal)
        activeTerminalId = newTerminal.id
        newTerminal.startSessionIfNeeded()
        return newTerminal
    }

    func selectTerminal(id: UUID) {
        activeTerminalId = id
    }

    func removeTerminal(id: UUID) {
        if let index = terminals.firstIndex(where: { $0.id == id }) {
            terminals.remove(at: index)
            // If we removed the active terminal, select another one
            if activeTerminalId == id {
                if !terminals.isEmpty {
                    let newIndex = max(0, index - 1)
                    activeTerminalId = terminals[newIndex].id
                } else {
                    activeTerminalId = nil
                }
            }
        }
        
        // Ensure there's always at least one terminal if desired, or let it be empty
        if terminals.isEmpty {
            createTerminal()
        }
    }

    var activeTerminal: TerminalViewModel? {
        terminals.first { $0.id == activeTerminalId }
    }

    func appendOutput(_ text: String) async {
        if let active = activeTerminal {
            await active.appendOutput(text)
        }
    }

    /// One-shot execution for agent tool calls. Uses a separate invisible service.
    func execute(command: String, in workingDirectory: URL? = nil) async -> String {
        do {
            let result = try await backgroundService.run(command: command, in: workingDirectory)
            return result
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

import Foundation

final class TerminalService {
    func run(command: String, in directory: URL?) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        if let directory {
            process.currentDirectoryURL = directory
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let outputData = try await outputPipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()

        let result = String(data: outputData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw TerminalError.exit(code: Int(process.terminationStatus), output: result)
        }

        return result
    }
}

enum TerminalError: LocalizedError {
    case exit(code: Int, output: String)

    var errorDescription: String? {
        switch self {
        case .exit(let code, let output):
            return "Command exited with code \(code): \(output)"
        }
    }
}

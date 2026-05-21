import Foundation

final class GitService {
    private let terminal = TerminalService()

    func isGitRepository(at url: URL) async -> Bool {
        do {
            let result = try await terminal.run(command: "git -C \(shellEscape(url.path)) rev-parse --is-inside-work-tree", in: url)
            return result.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    func status(at url: URL) async throws -> String {
        try await terminal.run(command: "git -C \(shellEscape(url.path)) status --short --branch", in: url)
    }

    func diff(at url: URL, file: URL? = nil) async throws -> String {
        if let file {
            let relative = try relativePath(for: file, relativeTo: url)
            return try await terminal.run(command: "git -C \(shellEscape(url.path)) diff -- \(shellEscape(relative))", in: url)
        } else {
            return try await terminal.run(command: "git -C \(shellEscape(url.path)) diff -- .", in: url)
        }
    }

    func commit(at url: URL, message: String) async throws -> String {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.invalidCommitMessage
        }
        return try await terminal.run(command: "git -C \(shellEscape(url.path)) commit -am \(shellEscape(message))", in: url)
    }

    func log(at url: URL, count: Int = 20) async throws -> String {
        try await terminal.run(command: "git -C \(shellEscape(url.path)) log --oneline -n \(count)", in: url)
    }

    private func relativePath(for fileURL: URL, relativeTo rootURL: URL) throws -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { throw GitError.invalidPath }
        let relative = String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

enum GitError: LocalizedError {
    case invalidCommitMessage
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .invalidCommitMessage:
            return "Commit message cannot be empty."
        case .invalidPath:
            return "The specified file path is not within the repository."            
        }
    }
}

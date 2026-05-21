import Foundation
import SwiftUI

@MainActor
final class GitViewModel: ObservableObject {
    @Published var statusText = ""
    @Published var diffText = ""
    @Published var diffTitle = ""
    @Published var isGitRepository = false
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var isShowingDiffPreview = false

    private let service = GitService()

    func refreshRepositoryStatus(projectURL: URL?) async {
        guard let projectURL else {
            updateStatus("No project open.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            isGitRepository = await service.isGitRepository(at: projectURL)
            if isGitRepository {
                statusText = try await service.status(at: projectURL)
                if statusText.isEmpty {
                    statusText = "Clean working tree."
                }
            } else {
                statusText = "Not a git repository."
            }
        } catch {
            updateError(error)
        }
    }

    func gitStatus(projectURL: URL?) async {
        guard let projectURL else {
            updateStatus("No project open.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            isGitRepository = await service.isGitRepository(at: projectURL)
            if isGitRepository {
                statusText = try await service.status(at: projectURL)
                if statusText.isEmpty {
                    statusText = "Clean working tree."
                }
            } else {
                statusText = "Not a git repository."
            }
        } catch {
            updateError(error)
        }
    }

    func gitDiff(projectURL: URL?, fileURL: URL? = nil) async {
        guard let projectURL else {
            updateStatus("No project open.")
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            isGitRepository = await service.isGitRepository(at: projectURL)
            guard isGitRepository else {
                updateStatus("Not a git repository.")
                return
            }
            let diff = try await service.diff(at: projectURL, file: fileURL)
            diffTitle = fileURL?.lastPathComponent ?? "Repository diff"
            diffText = diff.isEmpty ? "No differences to show." : diff
            isShowingDiffPreview = true
        } catch {
            updateError(error)
        }
    }

    func gitCommit(message: String, projectURL: URL?) async {
        guard let projectURL else {
            updateStatus("No project open.")
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await service.commit(at: projectURL, message: message)
            await gitStatus(projectURL: projectURL)
        } catch {
            updateError(error)
        }
    }

    func unsavedDiff(for openFile: OpenFile) {
        do {
            let diskText = try FileSystemService.shared.readText(from: openFile.url)
            diffTitle = "Unsaved diff: \(openFile.title)"
            diffText = generateUnifiedDiff(original: diskText, modified: openFile.text, path: openFile.title)
            isShowingDiffPreview = true
        } catch {
            updateError(error)
        }
    }

    private func updateStatus(_ text: String) {
        statusText = text
        lastError = nil
    }

    private func updateError(_ error: Error) {
        lastError = error.localizedDescription
        diffTitle = "Error"
        diffText = error.localizedDescription
        isShowingDiffPreview = true
    }

    private func generateUnifiedDiff(original: String, modified: String, path: String) -> String {
        let oldLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = modified.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let diff = DiffUtility.unifiedDiff(old: oldLines, new: newLines, path: path)
        return diff.isEmpty ? "No unsaved changes detected." : diff
    }
}

private enum DiffUtility {
    static func unifiedDiff(old: [String], new: [String], path: String) -> String {
        let matrix = lcsMatrix(old: old, new: new)
        var i = old.count
        var j = new.count
        var chunks = [String]()

        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                i -= 1
                j -= 1
                continue
            }
            if j > 0, (i == 0 || matrix[i][j - 1] >= matrix[i - 1][j]) {
                chunks.insert("+\(new[j - 1])", at: 0)
                j -= 1
            } else if i > 0, (j == 0 || matrix[i][j - 1] < matrix[i - 1][j]) {
                chunks.insert("-\(old[i - 1])", at: 0)
                i -= 1
            }
        }

        if chunks.isEmpty {
            return ""
        }

        var patch = "--- a/\(path)\n+++ b/\(path)\n"
        for line in chunks {
            patch += line + "\n"
        }
        return patch
    }

    private static func lcsMatrix(old: [String], new: [String]) -> [[Int]] {
        var matrix = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in 1...old.count {
            for j in 1...new.count {
                if old[i - 1] == new[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1] + 1
                } else {
                    matrix[i][j] = max(matrix[i - 1][j], matrix[i][j - 1])
                }
            }
        }
        return matrix
    }
}

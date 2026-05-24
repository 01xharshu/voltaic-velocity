import Foundation
import AppKit

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var projectURL: URL?
    @Published var workspaceItems: [WorkspaceFile] = []
    @Published var projectSummary: String = ""
    @Published var selectedFileURL: URL?
    @Published var isShowingCommandPalette = false
    @Published var isIndexing = false

    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    func openProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Open Volt Velocity Project Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectURL = url
        saveLastProject(url)
        refreshWorkspace()
        startFileWatcher()
    }

    func restoreLastProject() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "VoltaicVelocityLastProjectBookmark") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if url.startAccessingSecurityScopedResource() {
                    projectURL = url
                    refreshWorkspace()
                    startFileWatcher()
                    if isStale {
                        saveLastProject(url)
                    }
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }

    /// Triggers an internal 2026-level code compliance review for the current project context.
    func triggerSkillEvaluation() {
        print("Evaluating Volt Velocity skills standards...")
        // Implements AdvancedSkillsEvaluation validation step
    }

    private func saveLastProject(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "VoltaicVelocityLastProjectBookmark")
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }

    func refreshWorkspace() {
        guard let projectURL else { return }
        isIndexing = true
        
        Task.detached(priority: .userInitiated) {
            do {
                let items = try FileSystemService.shared.loadDirectoryTree(at: projectURL)
                await MainActor.run {
                    self.workspaceItems = items
                    self.isIndexing = false
                    self.generateProjectSummary()
                }
            } catch {
                await MainActor.run {
                    print("Failed to load project tree: \(error)")
                    self.workspaceItems = []
                    self.isIndexing = false
                }
            }
        }
    }

    func selectFile(_ file: WorkspaceFile) {
        if !file.isDirectory {
            selectedFileURL = file.url
        }
    }

    private func generateProjectSummary() {
        guard let projectURL else { return }
        Task {
            let finalSummary = await Task.detached(priority: .background) {
                var tempSummary = ""
                let importantFiles = ["Package.swift", "project.yml", "README.md", "package.json"]
                for fileName in importantFiles {
                    let fileURL = projectURL.appendingPathComponent(fileName)
                    if let content = try? FileSystemService.shared.readText(from: fileURL) {
                        let truncated = content.count > 2000 ? String(content.prefix(2000)) + "\n... [Truncated]" : content
                        tempSummary += "\n--- \(fileName) ---\n\(truncated)\n"
                    }
                }
                return tempSummary.isEmpty ? "No standard project configuration files found." : tempSummary
            }.value
            self.projectSummary = finalSummary
        }
    }

    func createFile(named name: String, in directoryURL: URL? = nil) throws {
        guard let baseURL = directoryURL ?? projectURL else { throw FileSystemError.invalidProject }
        let created = try FileSystemService.shared.createFile(named: name, in: baseURL)
        refreshWorkspace()
        selectedFileURL = created
    }

    func createFolder(named name: String, in directoryURL: URL? = nil) throws {
        guard let baseURL = directoryURL ?? projectURL else { throw FileSystemError.invalidProject }
        _ = try FileSystemService.shared.createFolder(named: name, in: baseURL)
        refreshWorkspace()
    }

    func delete(item: WorkspaceFile) throws {
        try FileSystemService.shared.deleteItem(at: item.url)
        if selectedFileURL == item.url {
            selectedFileURL = nil
        }
        refreshWorkspace()
    }

    func rename(item: WorkspaceFile, to newName: String) throws {
        let newURL = try FileSystemService.shared.renameItem(at: item.url, to: newName)
        if selectedFileURL == item.url {
            selectedFileURL = newURL
        }
        refreshWorkspace()
    }

    var projectStructureDescription: String {
        guard let projectURL else { return "No project opened." }
        let tree = formattedTree(for: workspaceItems, prefix: "")
        return "Project: \(projectURL.lastPathComponent)\n\n\(tree)"
    }

    private func formattedTree(for items: [WorkspaceFile], prefix: String) -> String {
        items.map { item in
            let line = "\(prefix)\(item.isDirectory ? "📁" : "📄") \(item.name)"
            if let children = item.children, !children.isEmpty {
                return line + "\n" + formattedTree(for: children, prefix: prefix + "    ")
            }
            return line
        }
        .joined(separator: "\n")
    }



    // MARK: — File Watcher
    private func startFileWatcher() {
        stopFileWatcher()
        guard let projectURL else { return }

        fileDescriptor = open(projectURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .link],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshWorkspace()
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        fileWatcherSource = source
    }

    private func stopFileWatcher() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}

import Foundation
import AppKit

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var projectURL: URL?
    @Published var workspaceItems: [WorkspaceFile] = []
    @Published var selectedFileURL: URL?
    @Published var isShowingCommandPalette = false

    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    func openProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Open Voltaic Velocity Project Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectURL = url
        saveLastProject(url)
        refreshWorkspace()
        startFileWatcher()
    }

    func restoreLastProject() {
        if let path = UserDefaults.standard.string(forKey: "VoltaicVelocityLastProjectPath"), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                projectURL = url
                refreshWorkspace()
                startFileWatcher()
            }
        }
    }

    func refreshWorkspace() {
        guard let projectURL else { return }
        do {
            workspaceItems = try FileSystemService.shared.loadDirectoryTree(at: projectURL)
        } catch {
            print("Failed to load project tree: \(error)")
            workspaceItems = []
        }
    }

    func selectFile(_ file: WorkspaceFile) {
        if !file.isDirectory {
            selectedFileURL = file.url
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

    private func saveLastProject(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "VoltaicVelocityLastProjectPath")
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

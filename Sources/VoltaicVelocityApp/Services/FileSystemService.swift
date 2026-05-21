import Foundation

final class FileSystemService {
    static let shared = FileSystemService()
    private let fileManager = FileManager.default

    func loadDirectoryTree(at rootURL: URL) throws -> [WorkspaceFile] {
        let children = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let fileItems = try children.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                return WorkspaceFile(url: url, children: try loadDirectoryTree(at: url))
            } else {
                return WorkspaceFile(url: url, children: nil)
            }
        }
        return fileItems
    }

    func readText(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func writeText(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func createFile(named name: String, in directoryURL: URL, contents: String = "") throws -> URL {
        let fileURL = directoryURL.appendingPathComponent(name)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw FileSystemError.fileAlreadyExists(fileURL.path)
        }
        try createFolderIfNeeded(at: directoryURL)
        fileManager.createFile(atPath: fileURL.path, contents: contents.data(using: .utf8), attributes: nil)
        return fileURL
    }

    func createFolder(named name: String, in directoryURL: URL) throws -> URL {
        let folderURL = directoryURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    func deleteItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func renameItem(at url: URL, to newName: String) throws -> URL {
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    func createFolderIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

enum FileSystemError: LocalizedError {
    case fileAlreadyExists(String)
    case invalidProject

    var errorDescription: String? {
        switch self {
        case .fileAlreadyExists(let path):
            return "A file already exists at path: \(path)"
        case .invalidProject:
            return "The selected project folder is invalid."
        }
    }
}

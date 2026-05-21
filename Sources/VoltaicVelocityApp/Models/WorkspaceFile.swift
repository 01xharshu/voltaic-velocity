import Foundation

struct WorkspaceFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [WorkspaceFile]?

    init(url: URL, children: [WorkspaceFile]? = nil) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        self.children = children
    }

    var systemIconName: String {
        if isDirectory { return "folder"
        } else if url.pathExtension == "swift" { return "swift" }
        else if ["js", "ts", "jsx", "tsx"].contains(url.pathExtension) { return "chevron.left.slash.chevron.right" }
        else if ["py", "rb", "sh"].contains(url.pathExtension) { return "terminal" }
        else if ["json", "yaml", "yml", "plist"].contains(url.pathExtension) { return "curlybraces" }
        else { return "doc.text" }
    }

    var relativePath: String {
        return url.path
    }
}

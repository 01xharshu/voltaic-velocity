import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var isShowingNewFileAlert = false
    @State private var isShowingNewFolderAlert = false
    @State private var newItemName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with action buttons
            HStack(spacing: 6) {
                Text("EXPLORER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    newItemName = "NewFile.swift"
                    isShowingNewFileAlert = true
                }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("New File")

                Button(action: {
                    newItemName = "NewFolder"
                    isShowingNewFolderAlert = true
                }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("New Folder")

                Button(action: projectViewModel.refreshWorkspace) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button(action: projectViewModel.openProjectFolder) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Open Folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            if let _ = projectViewModel.projectURL {
                List {
                    OutlineGroup(projectViewModel.workspaceItems, children: \.children) { item in
                        SidebarFileRow(item: item, projectViewModel: projectViewModel, editorViewModel: editorViewModel)
                    }
                }
                .listStyle(.sidebar)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Folder Open")
                        .font(.system(size: 15, weight: .medium))
                    Text("Open a folder to start working on your project.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 200)
                    Button("Open Folder") {
                        projectViewModel.openProjectFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .alert("New File", isPresented: $isShowingNewFileAlert) {
            TextField("Filename", text: $newItemName)
            Button("Create") {
                let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                try? projectViewModel.createFile(named: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new file.")
        }
        .alert("New Folder", isPresented: $isShowingNewFolderAlert) {
            TextField("Folder name", text: $newItemName)
            Button("Create") {
                let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                try? projectViewModel.createFolder(named: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new folder.")
        }
    }
}

private struct SidebarFileRow: View {
    let item: WorkspaceFile
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel
    @State private var isShowingRename = false
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 6) {
            fileIcon
            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !item.isDirectory {
                projectViewModel.selectFile(item)
                editorViewModel.openFile(at: item.url)
            }
        }
        .contextMenu {
            if item.isDirectory {
                Button {
                    renameText = "NewFile.swift"
                    isShowingRename = false
                    let alert = NSAlert()
                    alert.messageText = "New File in \(item.name)"
                    alert.informativeText = "Enter a filename:"
                    let input = NSTextField(string: "NewFile.swift")
                    input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
                    alert.accessoryView = input
                    alert.addButton(withTitle: "Create")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            try? projectViewModel.createFile(named: name, in: item.url)
                        }
                    }
                } label: {
                    Label("New File", systemImage: "doc.badge.plus")
                }

                Button {
                    let alert = NSAlert()
                    alert.messageText = "New Folder in \(item.name)"
                    alert.informativeText = "Enter a folder name:"
                    let input = NSTextField(string: "NewFolder")
                    input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
                    alert.accessoryView = input
                    alert.addButton(withTitle: "Create")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            try? projectViewModel.createFolder(named: name, in: item.url)
                        }
                    }
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Divider()
            }

            Button {
                let alert = NSAlert()
                alert.messageText = "Rename \(item.name)"
                alert.informativeText = "Enter a new name:"
                let input = NSTextField(string: item.name)
                input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
                alert.accessoryView = input
                alert.addButton(withTitle: "Rename")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newName.isEmpty {
                        try? projectViewModel.rename(item: item, to: newName)
                    }
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if !item.isDirectory {
                Button {
                    if let text = try? FileSystemService.shared.readText(from: item.url) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                } label: {
                    Label("Copy Contents", systemImage: "doc.on.doc")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.right.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                let alert = NSAlert()
                alert.messageText = "Delete \(item.name)?"
                alert.informativeText = "This action cannot be undone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    try? projectViewModel.delete(item: item)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var fileIcon: some View {
        let ext = item.url.pathExtension.lowercased()
        if item.isDirectory {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
        } else {
            Group {
                switch ext {
                case "swift":
                    Image(systemName: "swift")
                        .foregroundColor(.orange)
                case "js", "jsx", "ts", "tsx":
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(.yellow)
                case "py":
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(.blue)
                case "html", "htm":
                    Image(systemName: "globe")
                        .foregroundColor(.orange)
                case "css", "scss", "sass":
                    Image(systemName: "paintbrush.fill")
                        .foregroundColor(.blue)
                case "json":
                    Image(systemName: "curlybraces")
                        .foregroundColor(.yellow)
                case "yaml", "yml":
                    Image(systemName: "doc.text")
                        .foregroundColor(.purple)
                case "md", "markdown":
                    Image(systemName: "doc.richtext")
                        .foregroundColor(.blue)
                case "png", "jpg", "jpeg", "gif", "svg", "webp":
                    Image(systemName: "photo")
                        .foregroundColor(.green)
                case "plist", "xml":
                    Image(systemName: "angle.bracket.chevron.left.chevron.right")
                        .foregroundColor(.gray)
                case "sh", "bash", "zsh":
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.green)
                case "rb":
                    Image(systemName: "diamond.fill")
                        .foregroundColor(.red)
                case "go":
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(.cyan)
                case "rs":
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.orange)
                case "txt", "log":
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                case "gitignore":
                    Image(systemName: "eye.slash")
                        .foregroundColor(.gray)
                default:
                    Image(systemName: "doc")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 13))
        }
    }
}

import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project Explorer")
                    .font(.headline)
                Spacer()
                Button(action: projectViewModel.openProjectFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open project folder")
            }
            .padding(.horizontal)
            .padding(.top, 10)

            Divider()

            if let _ = projectViewModel.projectURL {
                List {
                    OutlineGroup(projectViewModel.workspaceItems, children: \ .children) { item in
                        SidebarFileRow(item: item, projectViewModel: projectViewModel, editorViewModel: editorViewModel)
                    }
                }
                .listStyle(.sidebar)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No project folder open.")
                        .font(.title3)
                    Text("Use the folder button to open a project workspace and start editing files.")
                        .foregroundColor(.secondary)
                    Button("Open Folder") {
                        projectViewModel.openProjectFolder()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SidebarFileRow: View {
    let item: WorkspaceFile
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        HStack {
            Image(systemName: item.systemIconName)
                .foregroundColor(item.isDirectory ? .accentColor : .secondary)
            Text(item.name)
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory {
                // folder selection is only structural
            } else {
                projectViewModel.selectFile(item)
                editorViewModel.openFile(at: item.url)
            }
        }
        .contextMenu {
            Button("New File") {
                try? projectViewModel.createFile(named: "NewFile.swift", in: item.isDirectory ? item.url : item.url.deletingLastPathComponent())
            }
            Button("New Folder") {
                try? projectViewModel.createFolder(named: "NewFolder", in: item.isDirectory ? item.url : item.url.deletingLastPathComponent())
            }
            if !item.isDirectory {
                Button("Rename") {
                    rename(item: item)
                }
                Button("Delete", role: .destructive) {
                    try? projectViewModel.delete(item: item)
                }
            }
        }
    }

    private func rename(item: WorkspaceFile) {
        let alert = NSAlert()
        alert.messageText = "Rename \(item.name)"
        alert.informativeText = "Enter a new name for the item."
        alert.alertStyle = .informational
        let input = NSTextField(string: item.name)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else { return }
            try? projectViewModel.rename(item: item, to: newName)
        }
    }
}

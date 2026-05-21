import SwiftUI
import CodeEditorView

struct EditorView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if let file = editorViewModel.activeFile {
                HStack {
                    Text(file.url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Find/Replace") {
                        editorViewModel.showFindReplace.toggle()
                    }
                    .keyboardShortcut("f", modifiers: [.command])
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                CodeEditor(
                    text: Binding(
                        get: { file.text },
                        set: { editorViewModel.updateText($0, for: file) }
                    ),
                    position: Binding(
                        get: { file.selection },
                        set: { position in
                            guard let index = editorViewModel.openFiles.firstIndex(of: file) else { return }
                            editorViewModel.openFiles[index].selection = position
                        }
                    ),
                    messages: Binding(
                        get: { file.messages },
                        set: { messages in
                            guard let index = editorViewModel.openFiles.firstIndex(of: file) else { return }
                            editorViewModel.openFiles[index].messages = messages
                        }
                    ),
                    language: file.language
                )
                .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
                .padding(6)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    Text("Open a file from the sidebar to begin editing.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .sheet(isPresented: $editorViewModel.showFindReplace) {
            FindReplaceView(editorViewModel: editorViewModel)
                .frame(width: 520, height: 260)
        }
    }
}

private struct FindReplaceView: View {
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find and Replace")
                .font(.headline)
            TextField("Find", text: $editorViewModel.findQuery)
            TextField("Replace with", text: $editorViewModel.replaceQuery)
            HStack {
                Spacer()
                Button("Replace All") {
                    editorViewModel.applyFindReplace()
                }
                .keyboardShortcut(.defaultAction)
                Button("Close") {
                    editorViewModel.showFindReplace = false
                }
            }
        }
        .padding(20)
    }
}

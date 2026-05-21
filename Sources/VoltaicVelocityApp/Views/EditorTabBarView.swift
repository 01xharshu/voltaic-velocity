import SwiftUI

struct EditorTabBarView: View {
    @ObservedObject var editorViewModel: EditorViewModel
    @ObservedObject var projectViewModel: ProjectViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(editorViewModel.openFiles) { file in
                HStack(spacing: 4) {
                    Button(action: {
                        editorViewModel.activeFileID = file.id
                    }) {
                        Text(file.title)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundColor(editorViewModel.activeFileID == file.id ? .primary : .secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(editorViewModel.activeFileID == file.id ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { editorViewModel.closeTab(file) }) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                }
                if editorViewModel.openFiles.isEmpty {
                    Text("No file open")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }
}

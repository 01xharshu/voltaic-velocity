import Foundation
import SwiftUI
import CodeEditorView

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var openFiles: [OpenFile] = []
    @Published var activeFileID: UUID?
    @Published var findQuery = ""
    @Published var replaceQuery = ""
    @Published var showFindReplace = false

    var activeFile: OpenFile? {
        guard let activeFileID else { return nil }
        return openFiles.first { $0.id == activeFileID }
    }

    func openFile(at url: URL) {
        if let existingIndex = openFiles.firstIndex(where: { $0.url == url }) {
            activeFileID = openFiles[existingIndex].id
            return
        }

        do {
            let text = try FileSystemService.shared.readText(from: url)
            let file = OpenFile(url: url, text: text)
            openFiles.append(file)
            activeFileID = file.id
        } catch {
            print("Unable to open file: \(error)")
        }
    }

    func closeTab(_ file: OpenFile) {
        if let index = openFiles.firstIndex(of: file) {
            openFiles.remove(at: index)
            if activeFileID == file.id {
                activeFileID = openFiles.last?.id
            }
        }
    }

    func updateText(_ text: String, for file: OpenFile) {
        guard let index = openFiles.firstIndex(of: file) else { return }
        openFiles[index].text = text
    }

    func save(file: OpenFile?) {
        guard let file else { return }
        do {
            try FileSystemService.shared.writeText(file.text, to: file.url)
        } catch {
            print("Failed to save file: \(error)")
        }
    }

    func saveActiveFile() {
        save(file: activeFile)
    }

    func applyFindReplace() {
        guard let file = activeFile, !findQuery.isEmpty else { return }
        let updated = file.text.replacingOccurrences(of: findQuery, with: replaceQuery)
        updateText(updated, for: file)
    }
}

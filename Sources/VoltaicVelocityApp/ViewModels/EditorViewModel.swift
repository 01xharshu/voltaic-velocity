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

    private var fileWatchers: [UUID: DispatchSourceFileSystemObject] = [:]

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
            startWatching(file: file)
        } catch {
            print("Unable to open file: \(error)")
        }
    }

    func closeTab(_ file: OpenFile) {
        if let index = openFiles.firstIndex(of: file) {
            stopWatching(file: file)
            openFiles.remove(at: index)
            if activeFileID == file.id {
                activeFileID = openFiles.last?.id
            }
        }
    }
    
    private func startWatching(file: OpenFile) {
        let fd = open(file.url.path, O_EVTONLY)
        guard fd != -1 else { return }
        
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        watcher.setEventHandler { [weak self] in
            self?.reloadText(for: file.url)
        }
        watcher.setCancelHandler {
            close(fd)
        }
        watcher.resume()
        fileWatchers[file.id] = watcher
    }
    
    private func stopWatching(file: OpenFile) {
        fileWatchers[file.id]?.cancel()
        fileWatchers.removeValue(forKey: file.id)
    }

    func reloadText(for url: URL) {
        if let existingIndex = openFiles.firstIndex(where: { $0.url == url }) {
            do {
                let newText = try FileSystemService.shared.readText(from: url)
                if openFiles[existingIndex].text != newText {
                    openFiles[existingIndex].text = newText
                }
            } catch {
                print("Failed to reload text for open file: \(error)")
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

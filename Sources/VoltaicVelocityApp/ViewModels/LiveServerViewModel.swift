import Foundation
import SwiftUI
import AppKit

@MainActor
final class LiveServerViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var port: Int = 5500
    
    private let service = LiveServerService()

    func toggleServer(in directory: URL?, activeFileURL: URL? = nil) {
        if isRunning {
            stopServer()
        } else {
            startServer(in: directory, activeFileURL: activeFileURL)
        }
    }

    func startServer(in directory: URL?, activeFileURL: URL? = nil) {
        guard let directory = directory else { return }
        do {
            try service.start(in: directory, port: port)
            isRunning = true
            
            // Calculate the URL to open
            var urlComponents = URLComponents()
            urlComponents.scheme = "http"
            urlComponents.host = "localhost"
            urlComponents.port = port
            urlComponents.path = "/"
            
            if let activeURL = activeFileURL,
               activeURL.pathExtension.lowercased() == "html",
               activeURL.path.hasPrefix(directory.path) {
                
                let relativePath = String(activeURL.path.dropFirst(directory.path.count))
                urlComponents.path = "/" + relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            
            if let url = urlComponents.url {
                NSWorkspace.shared.open(url)
            }
        } catch {
            print("Failed to start Live Server: \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stopServer() {
        service.stop()
        isRunning = false
    }
}

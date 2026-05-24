import Foundation
import AppKit

final class BackendService {
    static let shared = BackendService()
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }
    
    func start() {
        guard process == nil else { return }
        
        // Find the backend directory robustly using the source file path
        let sourceFileURL = URL(fileURLWithPath: #file)
        // Navigate from: Sources/VoltaicVelocityApp/Services/BackendService.swift -> root
        let projectRoot = sourceFileURL
            .deletingLastPathComponent() // removes BackendService.swift
            .deletingLastPathComponent() // removes Services
            .deletingLastPathComponent() // removes VoltaicVelocityApp
            .deletingLastPathComponent() // removes Sources
        
        let backendPath = projectRoot.appendingPathComponent("backend")
        
        guard FileManager.default.fileExists(atPath: backendPath.path) else {
            print("Backend directory not found at: \(backendPath.path)")
            // Fallback for packaged app (Resources/backend)
            if let bundlePath = Bundle.main.path(forResource: "backend", ofType: nil) {
                startProcess(at: URL(fileURLWithPath: bundlePath))
            }
            return
        }
        
        startProcess(at: backendPath)
    }
    
    private func startProcess(at path: URL) {
        let task = Process()
        task.currentDirectoryURL = path
        
        // Aggressively kill any process running on port 8000 before starting
        let script = """
        lsof -ti:8000 | xargs kill -9 2>/dev/null || true
        if [ ! -d "venv" ]; then
            python3 -m venv venv
        fi
        source venv/bin/activate
        pip install -r requirements.txt
        uvicorn agent_server:app --port 8000
        """
        
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        self.process = task
        
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                print("[Backend] \(string)", terminator: "")
            }
        }
        
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                print("[Backend Error] \(string)", terminator: "")
            }
        }
        
        do {
            try task.run()
            print("Python backend started successfully at \(path.path)")
        } catch {
            print("Failed to start python backend: \(error)")
        }
    }
    
    func stop() {
        process?.terminate()
        process = nil
    }
}

import Foundation

final class LiveServerService {
    private var process: Process?
    private var outputPipe: Pipe?
    private let outputQueue = DispatchQueue(label: "liveserver.output")

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(in directory: URL, port: Int = 5500) throws {
        stop()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-m", "http.server", "\(port)"]
        proc.currentDirectoryURL = directory

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        try proc.run()
        process = proc
        outputPipe = pipe
    }

    func stop() {
        process?.terminate()
        process = nil
        outputPipe = nil
    }
}

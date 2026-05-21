import Foundation
import Darwin

final class LiveServerService {
    private var process: Process?
    private var outputPipe: Pipe?
    private let outputQueue = DispatchQueue(label: "liveserver.output")

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(in directory: URL, startingPort: Int = 5500) throws -> Int {
        stop()

        var currentPort = startingPort
        while currentPort < 65535 {
            if isPortFree(port: currentPort) {
                break
            }
            currentPort += 1
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-m", "http.server", "\(currentPort)"]
        proc.currentDirectoryURL = directory

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        try proc.run()
        process = proc
        outputPipe = pipe
        
        return currentPort
    }

    func stop() {
        process?.terminate()
        process = nil
        outputPipe = nil
    }

    private func isPortFree(port: Int) -> Bool {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor != -1 else { return false }
        defer { Darwin.close(socketFileDescriptor) }

        var serverAddress = sockaddr_in()
        serverAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        serverAddress.sin_family = sa_family_t(AF_INET)
        serverAddress.sin_port = in_port_t(port).bigEndian
        serverAddress.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &serverAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        return bindResult == 0
    }
}

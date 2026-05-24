import Foundation

final class TerminalService {
    private var process: Process?
    private var masterHandle: FileHandle?
    private var onOutput: ((String) -> Void)?
    private let outputQueue = DispatchQueue(label: "terminal.output")

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(in directory: URL?, onOutput: @escaping (String) -> Void) {
        self.onOutput = onOutput

        let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        grantpt(masterFD)
        unlockpt(masterFD)
        let slaveName = String(cString: ptsname(masterFD))
        let slaveFD = open(slaveName, O_RDWR | O_NOCTTY)

        let masterFileHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slaveFileHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["--login", "-i"]

        if let directory {
            proc.currentDirectoryURL = directory
        }

        // Set up environment for interactive use
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["CLICOLOR"] = "1"
        env["LANG"] = "en_US.UTF-8"
        env["DISABLE_BRACKETED_PASTE"] = "true"
        proc.environment = env

        proc.standardInput = slaveFileHandle
        proc.standardOutput = slaveFileHandle
        proc.standardError = slaveFileHandle

        // Read from the master side asynchronously
        masterFileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let cleanText = text.strippingANSI()
            self?.outputQueue.async {
                self?.onOutput?(cleanText)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            self?.outputQueue.async {
                self?.onOutput?("\r\n[Process exited]\r\n")
            }
        }

        do {
            try proc.run()
            close(slaveFD) // Close the slave in the parent process
            process = proc
            masterHandle = masterFileHandle
        } catch {
            onOutput("[Failed to start shell: \(error.localizedDescription)]\n")
        }
    }

    func send(command: String) {
        guard let masterHandle, process?.isRunning == true else { return }
        if let data = (command + "\n").data(using: .utf8) {
            masterHandle.write(data)
        }
    }

    /// Send raw characters (no trailing newline) — used for real-time keystroke forwarding
    func send(raw chars: String) {
        guard let masterHandle, process?.isRunning == true else { return }
        if let data = chars.data(using: .utf8) {
            masterHandle.write(data)
        }
    }

    func stop() {
        masterHandle?.readabilityHandler = nil
        process?.terminate()
        process = nil
        masterHandle = nil
        onOutput = nil
    }

    /// One-shot command execution (used by the agent for tool calls)
    func run(command: String, in directory: URL?) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]

        if let directory {
            proc.currentDirectoryURL = directory
        }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()

        let outputData = try pipe.fileHandleForReading.readToEnd() ?? Data()
        proc.waitUntilExit()

        let result = String(data: outputData, encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            throw TerminalError.exit(code: Int(proc.terminationStatus), output: result)
        }
        return result
    }
}

enum TerminalError: LocalizedError {
    case exit(code: Int, output: String)

    var errorDescription: String? {
        switch self {
        case .exit(let code, let output):
            return "Command exited with code \(code): \(output)"
        }
    }
}

fileprivate extension String {
    func strippingANSI() -> String {
        // Broadened regex to catch [?2004h and others
        return self.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)
    }
}

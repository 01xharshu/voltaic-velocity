import Foundation

let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
grantpt(masterFD)
unlockpt(masterFD)
let slaveName = String(cString: ptsname(masterFD))
let slaveFD = open(slaveName, O_RDWR | O_NOCTTY)

let masterHandle = FileHandle(fileDescriptor: masterFD)
let slaveHandle = FileHandle(fileDescriptor: slaveFD)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
proc.arguments = ["-l"]
proc.standardInput = slaveHandle
proc.standardOutput = slaveHandle
proc.standardError = slaveHandle

try! proc.run()
close(slaveFD) // close slave in parent after fork

masterHandle.write(Data("echo Hello PTY\n".utf8))

let data = masterHandle.readData(ofLength: 1024)
print(String(data: data, encoding: .utf8) ?? "")
proc.terminate()

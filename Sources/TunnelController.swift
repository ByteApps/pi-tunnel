import Foundation

enum TunnelController {
    /// Opens one ssh session forwarding exactly `ports`. ExitOnForwardFailure keeps the
    /// all-or-nothing behaviour, which is why callers pass only the ports that are down.
    static func open(ports: [Int], host: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            var args = ["-f", "-N",
                        "-o", "ExitOnForwardFailure=yes",
                        "-o", "BatchMode=yes",
                        "-o", "ConnectTimeout=10"]
            for port in ports { args += ["-L", "\(port):127.0.0.1:\(port)"] }
            args.append(host)
            p.arguments = args
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch {
                completion("Could not start ssh: \(error.localizedDescription)"); return
            }
            let data = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                completion(nil)
            } else {
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(text.isEmpty ? "ssh exited with status \(p.terminationStatus)" : text)
            }
        }
    }

    /// SIGTERM the ssh processes that own listeners on registered ports.
    static func close(pids: [Int32]) {
        for pid in pids { kill(pid, SIGTERM) }
    }
}

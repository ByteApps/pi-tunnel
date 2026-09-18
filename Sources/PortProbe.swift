import Foundation

enum PortState {
    case open    // a TCP connect succeeds and the listener is ssh (or lsof could not tell)
    case busy    // something answers on the port but it is not ssh
    case closed  // nothing listening
}

struct ProbeResult {
    let states: [Int: PortState]
    /// PIDs of ssh processes that own a listener on one of the registered ports.
    let sshPIDs: [Int32]
    let date: Date

    func openCount() -> Int { states.values.filter { $0 == .open }.count }
}

struct Listener {
    let pid: Int32
    let command: String
    let port: Int
}

enum PortProbe {
    /// Blocking; call from a background queue.
    static func probe(ports: [Int]) -> ProbeResult {
        var states: [Int: PortState] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for port in ports {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let ok = tcpOpen(port: port, timeout: 1.5)
                lock.lock(); states[port] = ok ? .open : .closed; lock.unlock()
                group.leave()
            }
        }
        let listeners = self.listeners()
        group.wait()

        var sshPIDs = Set<Int32>()
        if let listeners = listeners {
            for port in ports where states[port] == .open {
                let owners = listeners.filter { $0.port == port }
                if owners.isEmpty { continue } // listener vanished between checks; trust the connect
                if let ssh = owners.first(where: { $0.command == "ssh" }) {
                    sshPIDs.insert(ssh.pid)
                } else {
                    states[port] = .busy
                }
            }
        }
        return ProbeResult(states: states, sshPIDs: Array(sshPIDs).sorted(), date: Date())
    }

    /// Non-blocking connect to 127.0.0.1:port with a timeout. Sends no data.
    static func tcpOpen(port: Int, timeout: TimeInterval) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, Int32(timeout * 1000)) > 0 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0 else { return false }
        return err == 0
    }

    /// All listening TCP sockets owned by this user, via `lsof -nP -iTCP -sTCP:LISTEN -Fpcn`.
    /// Returns nil when lsof could not run.
    static func listeners() -> [Listener]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var result: [Listener] = []
        var pid: Int32 = 0
        var cmd = ""
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let rest = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(rest) ?? 0
            case "c": cmd = rest
            case "n":
                if let colon = rest.lastIndex(of: ":"),
                   let port = Int(rest[rest.index(after: colon)...]) {
                    result.append(Listener(pid: pid, command: cmd, port: port))
                }
            default: break
            }
        }
        return result
    }
}

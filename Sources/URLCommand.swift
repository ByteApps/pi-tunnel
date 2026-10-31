import Foundation

/// `pitunnel://` links, so other apps and web pages can ask Pi Tunnel to open
/// ports instead of running ssh themselves. Pi Tunnel stays the only thing that
/// opens and closes tunnels.
///
///     pitunnel://open                      open every registered port that is down
///     pitunnel://open?port=3001            open just these (repeat `port=` for more)
///     pitunnel://open?port=3001&then=URL   …then open URL once the ports are up
///
/// Guard rails, because any web page can try a custom URL:
/// - only ports already registered in ports.json are ever opened;
/// - `then` must be http(s) on 127.0.0.1 or localhost, i.e. a page behind the tunnel.
struct URLCommand: Equatable {
    let ports: [Int]        // registered ports to make sure are open; empty = none asked
    let all: Bool           // no `port=` given: open every registered port that is down
    let then: URL?
    let rejected: [String]  // what was ignored and why, shown to the user

    static func parse(_ url: URL, registered: [Int]) -> URLCommand? {
        guard url.scheme?.lowercased() == "pitunnel",
              (url.host ?? "").lowercased() == "open" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var ports: [Int] = []
        var rejected: [String] = []
        let asked = items.filter { $0.name == "port" }
        for item in asked {
            guard let raw = item.value, let p = Int(raw) else {
                rejected.append("port \"\(item.value ?? "")\" is not a number"); continue
            }
            if registered.contains(p) {
                if !ports.contains(p) { ports.append(p) }
            } else {
                rejected.append("port \(p) is not in your ports list")
            }
        }
        var then: URL?
        if let raw = items.first(where: { $0.name == "then" })?.value {
            if let u = URL(string: raw), isLoopbackWeb(u) {
                then = u
            } else {
                rejected.append("not opening \(raw): only http(s) pages on 127.0.0.1 or localhost")
            }
        }
        return URLCommand(ports: ports, all: asked.isEmpty, then: then, rejected: rejected)
    }

    static func isLoopbackWeb(_ u: URL) -> Bool {
        guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
}

import Foundation

struct PortEntry: Codable, Equatable {
    let port: Int
    let name: String
    let url: String?
}

struct PortGroup: Codable, Equatable {
    let name: String
    let ports: [PortEntry]
}

struct Config: Codable, Equatable {
    var host: String
    var intervalSeconds: Double
    var groups: [PortGroup]

    var allPorts: [PortEntry] { groups.flatMap { $0.ports } }

    /// Written to ~/.config/pi-tunnel/ports.json on first launch. Edit it to match
    /// your Pi; the app re-reads it on every check.
    static let `default` = Config(
        host: "pi@raspberrypi.local",
        intervalSeconds: 5,
        groups: [
            PortGroup(name: "raspberrypi", ports: [
                PortEntry(port: 8080, name: "Web UI", url: "http://127.0.0.1:8080"),
                PortEntry(port: 3000, name: "Grafana", url: "http://127.0.0.1:3000"),
                PortEntry(port: 5432, name: "Postgres", url: nil),
            ]),
        ]
    )
}

/// Loads ~/.config/pi-tunnel/ports.json, writing the default file on first run.
/// `reloadIfChanged` is cheap (one stat) and is called on every poll.
final class ConfigStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/pi-tunnel/ports.json")

    private(set) var config: Config = .default
    private(set) var lastError: String?
    private var lastModified: Date?

    /// Writes `config` to disk as pretty JSON and adopts it immediately.
    func save(_ newConfig: Config) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(newConfig)
        try data.write(to: Self.url, options: .atomic)
        config = newConfig
        lastError = nil
        lastModified = (try? fm.attributesOfItem(atPath: Self.url.path))?[.modificationDate] as? Date
    }

    func ensureExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Self.url.path) else { return }
        try? fm.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(Config.default) {
            try? data.write(to: Self.url)
        }
    }

    /// Returns true when the config on disk changed since the last call.
    @discardableResult
    func reloadIfChanged() -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.url.path)
        let modified = attrs?[.modificationDate] as? Date
        if modified == lastModified { return false }
        lastModified = modified
        guard let data = try? Data(contentsOf: Self.url) else {
            lastError = "ports.json could not be read; using built-in ports"
            return false
        }
        do {
            let fresh = try JSONDecoder().decode(Config.self, from: data)
            lastError = nil
            if fresh == config { return false }
            config = fresh
            return true
        } catch {
            lastError = "ports.json is invalid: \(error.localizedDescription)"
            return false
        }
    }
}

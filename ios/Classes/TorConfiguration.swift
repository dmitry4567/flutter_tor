import Foundation

/// Tor bridge transport configuration.
struct TorBridgeConfig: Equatable {
    var useBridges: Bool = false
    var bridgeLines: [String] = []
    var useObfs4: Bool = false
    var useSnowflake: Bool = false
}

/// Helper that prepares TorConfiguration and data paths. Named TorSetup
/// to avoid clashing with the pod's TorConfiguration type (NS_SWIFT_NAME).
class TorSetup {

    let dataDirectory: URL
    let controlSocketURL: URL
    let socksPort: Int
    let controlPort: Int

    init() throws {
        let torDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tor", isDirectory: true)

        try FileManager.default.createDirectory(at: torDir, withIntermediateDirectories: true)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: torDir.path
        )

        self.dataDirectory = torDir
        self.controlSocketURL = torDir.appendingPathComponent("c.sock")
        self.socksPort = TorSetup.findAvailablePort(startingAt: 39050)
        self.controlPort = TorSetup.findAvailablePort(startingAt: 39150)
    }

    /// Builds a TorConfiguration honoring the bridge settings.
    /// ptPorts: ["obfs4": port, "snowflake": port] — ports allocated by IPtProxy.
    func buildTorConfiguration(bridges: TorBridgeConfig, ptPorts: [String: Int], logsEnabled: Bool = true) -> TorConfiguration {
        let config = TorConfiguration()
        config.dataDirectory = dataDirectory
        config.socksPort = UInt(socksPort)
        config.cookieAuthentication = false
        config.ignoreMissingTorrc = true
        config.clientOnly = true
        config.avoidDiskWrites = true

        var args: [String] = [
            "--ControlPort", "\(controlPort)",
        ]

        if !logsEnabled {
            args += ["--Log", "err file /dev/null"]
        }

        if bridges.useBridges && !bridges.bridgeLines.isEmpty {
            args += ["--UseBridges", "1"]

            if bridges.useObfs4, let port = ptPorts["obfs4"], port > 0 {
                args += ["--ClientTransportPlugin", "obfs4 socks5 127.0.0.1:\(port)"]
            }

            if bridges.useSnowflake, let port = ptPorts["snowflake"], port > 0 {
                args += ["--ClientTransportPlugin", "snowflake socks5 127.0.0.1:\(port)"]
            }

            for bridge in bridges.bridgeLines {
                let trimmed = bridge.trimmingCharacters(in: .whitespaces)
                if bridges.useObfs4 && !trimmed.hasPrefix("obfs4 ") && !trimmed.hasPrefix("snowflake ") {
                    args += ["--Bridge", "obfs4 \(trimmed)"]
                } else if bridges.useSnowflake && !trimmed.hasPrefix("snowflake ") && !trimmed.hasPrefix("obfs4 ") {
                    args += ["--Bridge", "snowflake \(trimmed)"]
                } else {
                    args += ["--Bridge", trimmed]
                }
            }
        } else {
            args += ["--UseBridges", "0"]
        }

        config.arguments = NSMutableArray(array: args)
        return config
    }

    static func findAvailablePort(startingAt start: Int) -> Int {
        for port in start...(start + 100) {
            if isPortAvailable(port) { return port }
        }
        return start
    }

    private static func isPortAvailable(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

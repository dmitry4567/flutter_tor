import Foundation
import IPtProxy

typealias TorStatusCallback = (_ status: String, _ progress: Int, _ error: String?) -> Void
typealias TorLogCallback = (_ level: String, _ tag: String, _ message: String) -> Void

class TorManager {

    static let shared = TorManager()

    private var torThread: TorThread?
    private var torController: TorController?
    private var torSetup: TorSetup?
    private(set) var currentBridges: TorBridgeConfig = TorBridgeConfig()

    /// Serializes the current bridge configuration for delivery to Dart.
    /// Used by both getStatus and the EventChannel status events so the
    /// Dart side can recover its state after a hot restart.
    func currentBridgesMap() -> [String: Any] {
        return [
            "useBridges": currentBridges.useBridges,
            "useObfs4": currentBridges.useObfs4,
            "useSnowflake": currentBridges.useSnowflake,
            "bridgeLines": currentBridges.bridgeLines,
        ]
    }

    private var ptController: IPtProxyController?

    private(set) var isRunning = false
    private var isSuspended = false
    private var reconfigureGeneration: Int = 0
    /// True after a reconfiguration: the bootstrap observer will not emit
    /// "connected" until pollConnectionTimeout confirms circuit-established.
    private var awaitingCircuitCheck = false
    private(set) var socksPort: Int = 0
    private(set) var bootstrapProgress: Int = 0

    var onStatusEvent: TorStatusCallback?
    var onLogEvent: TorLogCallback?
    var logsEnabled: Bool = true

    private init() {}

    func log(_ level: String, _ message: String, tag: String = "TorManager") {
        guard logsEnabled else { return }
        NSLog("[\(tag)] \(message)")
        let cb = onLogEvent
        DispatchQueue.main.async {
            cb?(level, tag, message)
        }
    }

    /// Initializes Tor. If a TorThread already exists (Tor cannot be
    /// restarted within a single process due to TORThread asserts), the
    /// new bridge configuration is applied via SETCONF and DisableNetwork
    /// is toggled instead of spawning a second thread.
    func initialize(bridges: TorBridgeConfig = TorBridgeConfig(), completion: @escaping (Error?) -> Void) {
        if torThread != nil {
            let bridgesChanged = (bridges != currentBridges)
            if bridgesChanged {
                log("info", "Bridge config changed, reconfiguring via SETCONF")
                reconfigureBridges(newBridges: bridges, completion: completion)
            } else if isSuspended {
                log("info", "Resuming Tor (DisableNetwork=0)")
                bootstrapProgress = 0
                awaitingCircuitCheck = true
                emitStatus("connecting", progress: 0, error: nil)
                isSuspended = false
                isRunning = true
                torController?.setConfs([["key": "DisableNetwork", "value": "0"]]) { [weak self] success, _ in
                    guard let self = self else { return }
                    if !success {
                        self.isSuspended = true
                        self.isRunning = false
                        self.emitStatus("error", progress: 0, error: "Failed to re-enable network")
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    self.reconfigureGeneration += 1
                    self.pollConnectionTimeout(controller: self.torController!, generation: self.reconfigureGeneration)
                    DispatchQueue.main.async { completion(nil) }
                }
            } else {
                log("info", "Already running with same bridges, skipping")
                DispatchQueue.main.async { completion(nil) }
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startTor(bridges: bridges, completion: completion)
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    /// Dynamically swaps the bridge configuration without restarting the
    /// TorThread. Sequence: SETCONF + DisableNetwork toggle + DROPGUARDS
    /// (only when switching off bridges) + NEWNYM.
    private func reconfigureBridges(newBridges: TorBridgeConfig,
                                    completion: @escaping (Error?) -> Void) {
        guard let controller = torController, let setup = torSetup else {
            let err = NSError(domain: "TorManager", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: "Controller/setup not available"])
            DispatchQueue.main.async { completion(err) }
            return
        }

        reconfigureGeneration += 1
        let myGeneration = reconfigureGeneration

        awaitingCircuitCheck = true
        bootstrapProgress = 0
        emitStatus("connecting", progress: 0, error: nil)
        log("info", "reconfigureBridges: gen=\(myGeneration), newBridges=\(newBridges)")

        controller.setConfs([["key": "DisableNetwork", "value": "1"]]) { [weak self] _, _ in
            guard let self = self else { return }
            guard myGeneration == self.reconfigureGeneration else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                guard myGeneration == self.reconfigureGeneration else { return }

                self.stopPluggableTransports()
                let ptPorts: [String: Int]
                do {
                    ptPorts = try self.startPluggableTransports(
                        bridges: newBridges,
                        dataDir: setup.dataDirectory
                    )
                } catch {
                    self.log("error", "PT restart failed: \(error)")
                    DispatchQueue.main.async { completion(error) }
                    return
                }
                self.log("info", "PT ports after restart: \(ptPorts)", tag: "PT")

                var bridgeLines: [String] = []
                var transportLines: [String] = []
                let useBridgesValue: String

                if newBridges.useBridges && !newBridges.bridgeLines.isEmpty {
                    useBridgesValue = "1"
                    if newBridges.useObfs4, let p = ptPorts["obfs4"], p > 0 {
                        transportLines.append("obfs4 socks5 127.0.0.1:\(p)")
                    }
                    if newBridges.useSnowflake, let p = ptPorts["snowflake"], p > 0 {
                        transportLines.append("snowflake socks5 127.0.0.1:\(p)")
                    }
                    for line in newBridges.bridgeLines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if newBridges.useObfs4
                            && !trimmed.hasPrefix("obfs4 ")
                            && !trimmed.hasPrefix("snowflake ") {
                            bridgeLines.append("obfs4 \(trimmed)")
                        } else if newBridges.useSnowflake
                                  && !trimmed.hasPrefix("snowflake ")
                                  && !trimmed.hasPrefix("obfs4 ") {
                            bridgeLines.append("snowflake \(trimmed)")
                        } else {
                            bridgeLines.append(trimmed)
                        }
                    }
                } else {
                    useBridgesValue = "0"
                }

                DispatchQueue.main.async {
                    guard myGeneration == self.reconfigureGeneration else { return }

                    controller.setConfs([["key": "UseBridges", "value": "0"]]) { [weak self] _, _ in
                        guard let self = self else { return }

                        self.resetKeys(["Bridge", "ClientTransportPlugin"], controller: controller) {
                            var parts: [String] = ["UseBridges=\(useBridgesValue)"]
                            for t in transportLines {
                                parts.append("ClientTransportPlugin=\(Self.quote(t))")
                            }
                            for b in bridgeLines {
                                parts.append("Bridge=\(Self.quote(b))")
                            }
                            self.log("info", "SETCONF → \(parts.joined(separator: " "))", tag: "Tor")

                            controller.sendCommand("SETCONF",
                                                   arguments: parts,
                                                   data: nil) { [weak self] codes, lines, stop in
                                guard let self = self else {
                                    stop.pointee = true
                                    return true
                                }
                                let code = codes.first?.intValue ?? 0
                                if code < 200 || code >= 300 { return false }
                                stop.pointee = true

                                let ok = code == 250
                                if !ok {
                                    self.log("error", "SETCONF bridges failed: \(code)")
                                } else {
                                    self.log("success", "SETCONF bridges accepted")
                                }
                                self.currentBridges = newBridges

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    if !newBridges.useBridges {
                                        controller.sendCommand("DROPGUARDS",
                                                               arguments: nil,
                                                               data: nil) { _, _, stop in
                                            stop.pointee = true
                                            return true
                                        }
                                    }
                                    controller.sendCommand("SIGNAL", arguments: ["NEWNYM"],
                                                           data: nil) { _, _, stop in
                                        stop.pointee = true
                                        return true
                                    }

                                    self.isSuspended = false
                                    self.isRunning = true
                                    controller.setConfs([["key": "DisableNetwork", "value": "0"]]) { [weak self] _, _ in
                                        guard let self = self else { return }
                                        self.log("success", "Bridges reconfigured, network re-enabled")
                                        self.pollConnectionTimeout(controller: controller, generation: myGeneration)
                                        DispatchQueue.main.async { completion(nil) }
                                    }
                                }
                                return true
                            }
                        }
                    }
                }
            }
        }
    }

    /// Wraps a value in double quotes for SETCONF, escaping inner `\` and
    /// `"` so Tor accepts strings containing whitespace.
    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Sequentially RESETCONFs the given keys.
    private func resetKeys(_ keys: [String],
                           controller: TorController,
                           completion: @escaping () -> Void) {
        var remaining = keys
        func next() {
            guard !remaining.isEmpty else {
                completion()
                return
            }
            let key = remaining.removeFirst()
            controller.resetConf(forKey: key) { [weak self] success, err in
                if !success {
                    self?.log("warn",
                              "RESETCONF \(key) failed: \(err?.localizedDescription ?? "unknown")")
                }
                next()
            }
        }
        next()
    }

    /// Soft stop: the Tor thread keeps running but network traffic is
    /// disabled via DisableNetwork=1. This is the only safe way to "stop"
    /// Tor inside a process — a full stop (cancel + release of the thread)
    /// crashes the libevent worker threads.
    func stop() {
        guard let controller = torController else {
            log("warn", "stop() called but controller is nil")
            isSuspended = true
            isRunning = false
            bootstrapProgress = 0
            emitStatus("disconnected", progress: 0, error: nil)
            return
        }
        isSuspended = true
        isRunning = false
        bootstrapProgress = 0
        awaitingCircuitCheck = false
        reconfigureGeneration += 1
        emitStatus("disconnected", progress: 0, error: nil)
        log("info", "Stopping Tor (DisableNetwork=1)")
        controller.setConfs([["key": "DisableNetwork", "value": "1"]]) { [weak self] success, _ in
            guard let self = self else { return }
            if success {
                self.log("success", "Tor suspended")
            } else {
                self.log("warn", "DisableNetwork=1 returned failure")
            }
            self.emitStatus("disconnected", progress: 0, error: nil)
        }
    }

    private func emitStatus(_ status: String, progress: Int, error: String?) {
        let cb = onStatusEvent
        DispatchQueue.main.async {
            cb?(status, progress, error)
        }
    }

    func suspend() {
        torController?.setConfs([["key": "DisableNetwork", "value": "1"]]) { [weak self] _, _ in
            self?.log("warn", "Network disabled (background)")
        }
    }

    func resume() {
        torController?.setConfs([["key": "DisableNetwork", "value": "0"]]) { [weak self] _, _ in
            self?.log("info", "Network re-enabled (foreground)")
        }
    }

    private func startTor(bridges: TorBridgeConfig, completion: @escaping (Error?) -> Void) throws {
        currentBridges = bridges

        let setup = try TorSetup()
        torSetup = setup
        socksPort = setup.socksPort

        let ptPorts = try startPluggableTransports(bridges: bridges, dataDir: setup.dataDirectory)

        let torConf = setup.buildTorConfiguration(bridges: bridges, ptPorts: ptPorts, logsEnabled: logsEnabled)

        log("header", "Starting TorThread, socksPort=\(socksPort), controlPort=\(setup.controlPort)")
        let thread = TorThread(configuration: torConf)

        // Suppress Tor's early stderr/stdout output when logs are disabled
        var savedStderr: Int32 = -1
        var savedStdout: Int32 = -1
        if !logsEnabled {
            savedStderr = dup(STDERR_FILENO)
            savedStdout = dup(STDOUT_FILENO)
            let devNull = open("/dev/null", O_WRONLY)
            if devNull >= 0 {
                dup2(devNull, STDERR_FILENO)
                dup2(devNull, STDOUT_FILENO)
                close(devNull)
            }
        }

        thread.start()

        if !logsEnabled {
            // Restore after a short delay to let Tor finish its early logging
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if savedStderr >= 0 {
                    dup2(savedStderr, STDERR_FILENO)
                    close(savedStderr)
                }
                if savedStdout >= 0 {
                    dup2(savedStdout, STDOUT_FILENO)
                    close(savedStdout)
                }
            }
        }

        torThread = thread

        log("info", "Waiting for control port \(setup.controlPort)...")
        do {
            try waitForPort(setup.controlPort, timeout: 10.0)
            log("success", "Control port ready")
        } catch {
            log("error", "Control port wait failed: \(error)")
            throw error
        }

        log("info", "Connecting TorController to 127.0.0.1:\(setup.controlPort)")
        let controller = TorController(socketHost: "127.0.0.1", port: UInt16(setup.controlPort))
        torController = controller
        log("info", "TorController initialized (connect called in init)")

        log("info", "Starting authentication...")
        controller.authenticate(with: Data()) { [weak self] success, error in
            guard let self = self else { return }
            if let error = error {
                self.log("error", "Auth failed: \(error), success=\(success)")
                DispatchQueue.main.async { completion(error) }
                return
            }
            if !success {
                self.log("error", "Auth returned success=false without error")
                let authError = NSError(domain: "TorManager", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
                DispatchQueue.main.async { completion(authError) }
                return
            }
            self.log("success", "Auth success, starting bootstrap monitor")
            self.isRunning = true
            self.reconfigureGeneration += 1
            self.startBootstrapMonitoring(controller: controller)
            self.pollConnectionTimeout(controller: controller,
                                        generation: self.reconfigureGeneration)
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Starts pluggable transports via IPtProxy. The IPtProxyController is
    /// reused across calls because IPtProxy is built on a gobind runtime
    /// which only supports a single Go runtime per process.
    private func startPluggableTransports(bridges: TorBridgeConfig, dataDir: URL) throws -> [String: Int] {
        guard bridges.useBridges else { return [:] }

        let controller: IPtProxyController
        if let existing = ptController {
            controller = existing
        } else {
            let ptStateDir = dataDir.appendingPathComponent("pt_state", isDirectory: true)
            try FileManager.default.createDirectory(at: ptStateDir, withIntermediateDirectories: true)

            guard let fresh = IPtProxyNewController(
                ptStateDir.path,
                false,
                false,
                "ERROR",
                nil
            ) else {
                throw NSError(domain: "TorManager", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to create IPtProxyController"])
            }
            controller = fresh
            ptController = fresh
        }

        var ptPorts: [String: Int] = [:]

        if bridges.useObfs4 {
            try controller.start(IPtProxyObfs4, proxy: nil)
            obfs4Running = true
            let obfs4Port = Int(controller.port(IPtProxyObfs4))
            ptPorts["obfs4"] = obfs4Port
            log("success", "obfs4 ready on SOCKS port \(obfs4Port)", tag: "PT")
        }

        if bridges.useSnowflake {
            controller.snowflakeBrokerUrl = "https://1098762253.rsc.cdn77.org/"
            controller.snowflakeFrontDomains = "www.cdn77.com,www.phpmyadmin.net"
            controller.snowflakeIceServers =
                "stun:stun.l.google.com:19302," +
                "stun:stun.antisip.com:3478," +
                "stun:stun.bluesip.net:3478," +
                "stun:stun.dus.net:3478," +
                "stun:stun.epygi.com:3478," +
                "stun:stun.sonetel.com:3478," +
                "stun:stun.uls.co.za:3478," +
                "stun:stun.voipgate.com:3478," +
                "stun:stun.voys.nl:3478"

            try controller.start(IPtProxySnowflake, proxy: nil)
            snowflakeRunning = true
            let snowflakePort = Int(controller.port(IPtProxySnowflake))
            ptPorts["snowflake"] = snowflakePort
            log("success", "snowflake ready on SOCKS port \(snowflakePort)", tag: "PT")
        }

        return ptPorts
    }

    private var obfs4Running = false
    private var snowflakeRunning = false

    private func stopPluggableTransports() {
        if obfs4Running {
            ptController?.stop(IPtProxyObfs4)
            obfs4Running = false
            log("info", "Stopped obfs4 PT", tag: "PT")
        }
        if snowflakeRunning {
            ptController?.stop(IPtProxySnowflake)
            snowflakeRunning = false
            log("info", "Stopped snowflake PT", tag: "PT")
        }
    }

    private func startBootstrapMonitoring(controller: TorController) {
        controller.listen(forEvents: ["STATUS_CLIENT"]) { [weak self] success, _ in
            guard let self = self else { return }
            if success {
                self.log("info", "Subscribed to STATUS_CLIENT events")
                self.checkCurrentBootstrap(controller: controller)
            }
        }

        controller.addObserver(forStatusEvents: { [weak self] type, severity, action, arguments in
            guard let self = self else { return true }

            if action == "BOOTSTRAP", let progressStr = arguments?["PROGRESS"],
               let progress = Int(progressStr) {
                if self.isSuspended { return false }
                let summary = arguments?["SUMMARY"] ?? ""
                self.log(progress >= 100 ? "success" : "warn",
                         "Bootstrap \(progress)%: \(summary)")

                self.bootstrapProgress = progress
                if progress >= 100 && self.awaitingCircuitCheck {
                    // Don't emit "connected" until circuit is verified
                } else {
                    let status = progress >= 100 ? "connected" : "connecting"
                    DispatchQueue.main.async {
                        self.onStatusEvent?(status, progress, nil)
                    }
                }
            }
            return false
        })
    }

    private static let directConnectTimeout: TimeInterval = 60
    private static let bridgeConnectTimeout: TimeInterval = 120

    /// Watches the connection timeout and confirms a real connection via
    /// circuit-established after a reconfiguration. Bootstrap may falsely
    /// report 100% based on cached directory data, so the circuit check
    /// is the source of truth.
    private func pollConnectionTimeout(controller: TorController,
                                       generation: Int,
                                       startTime: Date = Date()) {
        let timeout = currentBridges.useBridges
            ? Self.bridgeConnectTimeout
            : Self.directConnectTimeout

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            guard self.isRunning, !self.isSuspended,
                  generation == self.reconfigureGeneration else {
                self.log("warn", "pollConnectionTimeout: guard failed, exiting")
                return
            }

            if Date().timeIntervalSince(startTime) > timeout {
                self.log("error", "Connection timed out after \(Int(timeout))s")
                self.awaitingCircuitCheck = false
                self.bootstrapProgress = 0
                self.isRunning = false
                self.emitStatus("error", progress: 0,
                                error: "Connection timed out (\(Int(timeout))s)")
                return
            }

            controller.getInfoForKeys(["status/circuit-established"]) { [weak self] values in
                guard let self = self,
                      self.isRunning, !self.isSuspended,
                      generation == self.reconfigureGeneration else { return }

                let circuitVal = values.first ?? "?"
                if circuitVal == "1" {
                    if self.awaitingCircuitCheck {
                        self.awaitingCircuitCheck = false
                        self.bootstrapProgress = 100
                        self.log("success", "Circuit confirmed after reconfiguration")
                        self.emitStatus("connected", progress: 100, error: nil)
                    }
                } else {
                    self.pollConnectionTimeout(controller: controller,
                                               generation: generation,
                                               startTime: startTime)
                }
            }
        }
    }

    private func checkCurrentBootstrap(controller: TorController) {
        controller.getInfoForKeys(["status/bootstrap-phase"]) { [weak self] values in
            guard let self = self, let phase = values.first else { return }
            if self.isSuspended { return }
            if let progress = self.parseProgress(from: phase) {
                self.bootstrapProgress = progress
                let status = progress >= 100 ? "connected" : "connecting"
                DispatchQueue.main.async {
                    self.onStatusEvent?(status, progress, nil)
                }
            }
        }
    }

    private func parseProgress(from bootstrapPhase: String) -> Int? {
        let pattern = #"PROGRESS=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: bootstrapPhase,
                                           range: NSRange(bootstrapPhase.startIndex..., in: bootstrapPhase)),
              let range = Range(match.range(at: 1), in: bootstrapPhase) else {
            return nil
        }
        return Int(bootstrapPhase[range])
    }

    private func waitForPort(_ port: Int, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else {
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            defer { close(sock) }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let connected = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            if connected { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw NSError(
            domain: "TorManager",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Control port \(port) did not become available within \(timeout)s"]
        )
    }
}

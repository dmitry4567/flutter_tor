import Flutter
import UIKit

public class FlutterTorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let methodChannelName = "com.tgbk.flutter_tor"
    private static let eventChannelName  = "com.tgbk.flutter_tor/status"

    private var eventSink: FlutterEventSink?
    private let manager = TorManager.shared

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterTorPlugin()

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)

        registrar.addApplicationDelegate(instance)

        instance.manager.onStatusEvent = { [weak instance] status, progress, error in
            guard let sink = instance?.eventSink else { return }
            let bridges = instance?.manager.currentBridgesMap() ?? [:]
            DispatchQueue.main.async {
                if let error = error {
                    sink([
                        "type": "status",
                        "status": "error",
                        "progress": progress,
                        "error": error,
                        "bridges": bridges,
                    ])
                } else {
                    sink([
                        "type": "status",
                        "status": status,
                        "progress": progress,
                        "bridges": bridges,
                    ])
                }
            }
        }

        instance.manager.onLogEvent = { [weak instance] level, tag, message in
            guard let sink = instance?.eventSink else { return }
            DispatchQueue.main.async {
                sink([
                    "type": "log",
                    "level": level,
                    "tag": tag,
                    "message": message,
                ])
            }
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "initialize":
            let bridges = parseBridgeConfig(call.arguments)
            manager.log("info", "initialize() called", tag: "FlutterTorPlugin")
            manager.initialize(bridges: bridges) { [weak self] error in
                if let error = error {
                    self?.manager.log(
                        "error",
                        "Initialize failed: \(error.localizedDescription) (domain=\(error._domain), code=\(error._code))",
                        tag: "FlutterTorPlugin"
                    )
                    result(FlutterError(code: "TOR_INIT_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    self?.manager.log("success", "Initialize success", tag: "FlutterTorPlugin")
                    result(nil)
                }
            }

        case "stop":
            manager.stop()
            result(nil)

        case "getProxyPort":
            result(manager.socksPort)

        case "setLogsEnabled":
            let enabled = (call.arguments as? Bool) ?? true
            manager.logsEnabled = enabled
            result(nil)

        case "getStatus":
            result([
                "status": manager.isRunning ? (manager.bootstrapProgress >= 100 ? "connected" : "connecting") : "disconnected",
                "progress": manager.bootstrapProgress,
                "bridges": manager.currentBridgesMap(),
            ])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        let currentStatus = manager.isRunning
            ? (manager.bootstrapProgress >= 100 ? "connected" : "connecting")
            : "disconnected"
        events([
            "type": "status",
            "status": currentStatus,
            "progress": manager.bootstrapProgress,
            "bridges": manager.currentBridgesMap(),
        ])
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    public func applicationDidEnterBackground(_ application: UIApplication) {
        manager.log("warn", "App → background, suspending Tor network", tag: "FlutterTorPlugin")
        manager.suspend()
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        manager.log("info", "App → foreground, resuming Tor network", tag: "FlutterTorPlugin")
        manager.resume()
    }

    private func parseBridgeConfig(_ arguments: Any?) -> TorBridgeConfig {
        guard let args = arguments as? [String: Any] else { return TorBridgeConfig() }
        var config = TorBridgeConfig()
        config.useBridges   = args["useBridges"] as? Bool ?? false
        config.useObfs4     = args["useObfs4"] as? Bool ?? false
        config.useSnowflake = args["useSnowflake"] as? Bool ?? false
        config.bridgeLines  = args["bridgeLines"] as? [String] ?? []
        return config
    }
}

import 'dart:async';

import 'package:flutter/services.dart';

import 'models/tor_bridge_config.dart';
import 'models/tor_log_event.dart';
import 'models/tor_status.dart';
import 'models/tor_status_event.dart';

/// Dart-side facade for the embedded Tor client running on iOS.
class TorIos {
  static const _method = MethodChannel('com.tgbk.flutter_tor');
  static const _event = EventChannel('com.tgbk.flutter_tor/status');

  static final StreamController<TorStatusEvent> _statusController =
      StreamController<TorStatusEvent>.broadcast();
  static final StreamController<TorLogEvent> _logController =
      StreamController<TorLogEvent>.broadcast();
  static StreamSubscription<dynamic>? _eventSub;

  static bool _logsEnabled = true;

  /// Controls whether native log events are emitted.
  /// When `false`, logs are suppressed both on the native side (NSLog)
  /// and in Dart ([logStream]).
  static bool get logsEnabled => _logsEnabled;
  static set logsEnabled(bool value) {
    _logsEnabled = value;
    _method.invokeMethod<void>('setLogsEnabled', value);
  }

  static void _ensureEventSubscription() {
    if (_eventSub != null) return;
    _eventSub = _event.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'] as String? ?? 'status';
        if (type == 'log') {
          if (!_logsEnabled) return;
          _logController.add(TorLogEvent(
            level: event['level'] as String? ?? 'info',
            tag: event['tag'] as String? ?? 'Tor',
            message: event['message'] as String? ?? '',
          ));
        } else {
          _statusController.add(_parseStatusEvent(event));
        }
      },
      onError: (Object error) {
        _statusController.addError(error);
      },
    );
  }

  /// Initialize Tor. Optionally pass a bridge configuration.
  static Future<void> initialize([TorBridgeConfig? bridges]) async {
    final resolved = bridges?.resolve();
    await _method.invokeMethod<void>(
      'initialize',
      resolved?.toMap(),
    );
  }

  /// Stop Tor.
  static Future<void> stop() async {
    await _method.invokeMethod<void>('stop');
  }

  /// Get the SOCKS port (available after initialize).
  static Future<int> getProxyPort() async {
    final port = await _method.invokeMethod<int>('getProxyPort');
    return port ?? 0;
  }

  /// Get the current status.
  static Future<TorStatusEvent> getStatus() async {
    final map = await _method.invokeMethod<Map>('getStatus');
    return _parseStatusEvent(map ?? {});
  }

  /// Stream of Tor status events (bootstrap progress + connected/error).
  static Stream<TorStatusEvent> get statusStream {
    _ensureEventSubscription();
    return _statusController.stream;
  }

  /// Stream of text log events from the native side (NSLog/print → UI).
  static Stream<TorLogEvent> get logStream {
    _ensureEventSubscription();
    return _logController.stream;
  }

  static TorStatusEvent _parseStatusEvent(Map map) {
    final statusStr = map['status'] as String? ?? 'disconnected';
    final progress = map['progress'] as int? ?? 0;
    final error = map['error'] as String?;
    final bridges = TorBridgeConfig.fromMap(map['bridges'] as Map?);

    final status = switch (statusStr) {
      'connected' => TorStatus.connected,
      'connecting' => TorStatus.connecting,
      'error' => TorStatus.error,
      _ => TorStatus.disconnected,
    };

    return TorStatusEvent(
      status: status,
      progress: progress,
      errorMessage: error,
      bridges: bridges,
    );
  }
}

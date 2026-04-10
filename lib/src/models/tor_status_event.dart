import 'tor_bridge_config.dart';
import 'tor_status.dart';

/// Snapshot of the Tor client state delivered through [TorIos.statusStream]
/// and [TorIos.getStatus].
class TorStatusEvent {
  final TorStatus status;
  final int progress;
  final String? errorMessage;

  /// Current bridge configuration on the native side. Used so Dart can
  /// recover state after a hot restart: the native TorManager is a
  /// singleton that outlives the Dart isolate, so the real bridge mode
  /// must be read from there rather than from Dart memory.
  final TorBridgeConfig? bridges;

  const TorStatusEvent({
    required this.status,
    required this.progress,
    this.errorMessage,
    this.bridges,
  });

  @override
  String toString() =>
      'TorStatusEvent(status: $status, progress: $progress, bridges: $bridges)';
}

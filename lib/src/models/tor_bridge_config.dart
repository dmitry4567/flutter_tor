import '../bridges/tor_bridge_presets.dart';

/// Tor bridge configuration.
class TorBridgeConfig {
  final bool useBridges;
  final List<String> bridgeLines;
  final bool useObfs4;
  final bool useSnowflake;

  const TorBridgeConfig({
    this.useBridges = false,
    this.bridgeLines = const [],
    this.useObfs4 = false,
    this.useSnowflake = false,
  });

  /// Returns a config with effective bridge lines:
  /// uses [bridgeLines] if provided, otherwise falls back to defaults.
  TorBridgeConfig resolve() {
    if (bridgeLines.isNotEmpty) return this;
    if (useSnowflake) return TorBridgePresets.snowflake;
    if (useObfs4 || useBridges) return TorBridgePresets.obfs4Default;
    return this;
  }

  Map<String, dynamic> toMap() => {
        'useBridges': useBridges,
        'bridgeLines': bridgeLines,
        'useObfs4': useObfs4,
        'useSnowflake': useSnowflake,
      };

  static TorBridgeConfig? fromMap(Map? map) {
    if (map == null) return null;
    return TorBridgeConfig(
      useBridges: map['useBridges'] as bool? ?? false,
      useObfs4: map['useObfs4'] as bool? ?? false,
      useSnowflake: map['useSnowflake'] as bool? ?? false,
      bridgeLines: (map['bridgeLines'] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  String toString() =>
      'TorBridgeConfig(useBridges: $useBridges, useObfs4: $useObfs4, '
      'useSnowflake: $useSnowflake, bridgeLines: ${bridgeLines.length})';
}

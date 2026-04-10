import 'package:flutter_tor/flutter_tor.dart';

/// UI-level selector value for the bridge preset used when starting Tor.
enum BridgeMode { none, obfs4, snowflake, customObfs4, customSnowflake }

extension BridgeModeX on BridgeMode {
  TorBridgeConfig toConfig({List<String> customLines = const []}) {
    switch (this) {
      case BridgeMode.none:
        return TorBridgePresets.noBridges;
      case BridgeMode.obfs4:
        return TorBridgePresets.obfs4Default;
      case BridgeMode.snowflake:
        return TorBridgePresets.snowflake;
      case BridgeMode.customObfs4:
        return TorBridgeConfig(
          useBridges: true,
          useObfs4: true,
          bridgeLines: customLines,
        );
      case BridgeMode.customSnowflake:
        return TorBridgeConfig(
          useBridges: true,
          useSnowflake: true,
          bridgeLines: customLines,
        );
    }
  }

  bool get isCustom =>
      this == BridgeMode.customObfs4 || this == BridgeMode.customSnowflake;

  static BridgeMode fromConfig(TorBridgeConfig? bridges) {
    if (bridges == null || !bridges.useBridges) return BridgeMode.none;

    final hasCustomLines = bridges.bridgeLines.isNotEmpty;

    if (bridges.useObfs4) {
      return hasCustomLines ? BridgeMode.customObfs4 : BridgeMode.obfs4;
    }
    if (bridges.useSnowflake) {
      return hasCustomLines ? BridgeMode.customSnowflake : BridgeMode.snowflake;
    }
    return BridgeMode.none;
  }
}

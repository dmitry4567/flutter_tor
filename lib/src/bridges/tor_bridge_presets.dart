import '../models/tor_bridge_config.dart';
import 'tor_bridge_fetcher.dart';

/// Predefined bridge configurations bundled with the package.
class TorBridgePresets {
  /// Fetches fresh obfs4 bridges from bridges.torproject.org.
  ///
  /// Uses the Tor Project's circumvention API: tries country-aware
  /// `/circumvention/settings` first, falls back to `/circumvention/builtin`.
  ///
  /// Throws if the fetch fails — use [obfs4Default] as a fallback.
  static Future<TorBridgeConfig> fetchObfs4() => TorBridgeFetcher.fetchObfs4();

  /// Fetches fresh snowflake bridges from bridges.torproject.org.
  ///
  /// Uses the Tor Project's circumvention API: tries country-aware
  /// `/circumvention/settings` first, falls back to `/circumvention/builtin`.
  ///
  /// Throws if the fetch fails — use [snowflake] as a fallback.
  static Future<TorBridgeConfig> fetchSnowflake() => TorBridgeFetcher.fetchSnowflake();

  /// Default obfs4 bridges shipped from `backend/torrc`.
  static const List<String> defaultObfs4Bridges = [
    '158.69.55.8:444 27FC184FF5612418A38DA1B038485AD7B63EB322 cert=djModYy0VYC7nTnQPFM5Bo7c1vesLnO1WhXnjUe24cyxYZSrvI872hy6P/zf8nn7UK2QaA iat-mode=0',
    '185.177.207.130:8443 114A6897D35FFD5D27C375C0C2E0B0B8CF8CBA55 cert=Va3ADFJjrJG+kfPnnHRGN3j0l+Os21K66+xTKFV3L/t6HkG8EdIvPFaQrVl3uHPHm6GQNQ iat-mode=0',
    '84.120.92.142:35845 2F5FF5DAD3A38B0F68F6789464C835809A807CEE cert=hKtv54eReJ9qQyjCyiGneyMEFskspWKnlxE5Z+YMC0eIIler99BuEqrOaiL+34Lk5svfYQ iat-mode=0',
  ];

  static TorBridgeConfig get obfs4Default => const TorBridgeConfig(
        useBridges: true,
        useObfs4: true,
        bridgeLines: defaultObfs4Bridges,
      );

  /// Snowflake bridge line from the current Tor Browser 13.x torrc.
  /// Broker parameters (url/fronts/ice) are configured on the iOS side
  /// via IPtProxyController, so only a minimal header with a placeholder
  /// address and the public snowflake relay fingerprint is provided here.
  static TorBridgeConfig get snowflake => const TorBridgeConfig(
        useBridges: true,
        useSnowflake: true,
        bridgeLines: [
          'snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72',
        ],
      );

  static TorBridgeConfig get noBridges => const TorBridgeConfig();
}

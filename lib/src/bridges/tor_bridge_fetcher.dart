import 'dart:convert';
import 'dart:io';

import '../models/tor_bridge_config.dart';

/// Fetches fresh obfs4 bridges from the Tor Project's bridge distribution API.
class TorBridgeFetcher {
  static const _baseUrl = 'https://bridges.torproject.org/moat';
  static const _timeout = Duration(seconds: 15);

  /// Fetches obfs4 bridges from bridges.torproject.org.
  ///
  /// Tries `/circumvention/settings` first (returns bridges suited to
  /// the requester's country based on IP), then falls back to
  /// `/circumvention/builtin` which returns all available built-in bridges.
  ///
  /// Throws if both endpoints fail or return no obfs4 bridges.
  static Future<TorBridgeConfig> fetchObfs4() async {
    final lines =
        await _fetchFromSettings('obfs4') ?? await _fetchBuiltin('obfs4');
    if (lines == null || lines.isEmpty) {
      throw Exception('Failed to fetch obfs4 bridges from torproject.org');
    }
    return TorBridgeConfig(
      useBridges: true,
      useObfs4: true,
      bridgeLines: lines,
    );
  }

  /// Fetches snowflake bridges from bridges.torproject.org.
  ///
  /// Tries `/circumvention/settings` first, then falls back to
  /// `/circumvention/builtin`.
  ///
  /// Throws if both endpoints fail or return no snowflake bridges.
  static Future<TorBridgeConfig> fetchSnowflake() async {
    final lines = await _fetchFromSettings('snowflake') ??
        await _fetchBuiltin('snowflake');
    if (lines == null || lines.isEmpty) {
      throw Exception('Failed to fetch snowflake bridges from torproject.org');
    }
    return TorBridgeConfig(
      useBridges: true,
      useSnowflake: true,
      bridgeLines: lines,
    );
  }

  /// POST /circumvention/settings — country-aware bridge selection.
  static Future<List<String>?> _fetchFromSettings(String transport) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      try {
        final request = await client.postUrl(
          Uri.parse('$_baseUrl/circumvention/settings'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'transports': [transport]
        }));

        final response = await request.close().timeout(_timeout);
        if (response.statusCode != 200) return null;

        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final settings = json['settings'] as List?;
        if (settings == null || settings.isEmpty) return null;

        for (final setting in settings) {
          final bridges = (setting as Map)['bridges'] as Map?;
          if (bridges == null) continue;
          final type = bridges['type'] as String?;
          if (type == transport) {
            final strings = bridges['bridge_strings'] as List?;
            return strings?.cast<String>();
          }
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// GET /circumvention/builtin — all available built-in bridges.
  static Future<List<String>?> _fetchBuiltin(String transport) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      try {
        final request = await client.getUrl(
          Uri.parse('$_baseUrl/circumvention/builtin'),
        );

        final response = await request.close().timeout(_timeout);
        if (response.statusCode != 200) return null;

        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final bridges = json[transport] as List?;
        return bridges?.cast<String>();
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}

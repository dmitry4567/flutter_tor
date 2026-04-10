# flutter_tor

Native Flutter plugin for embedded Tor client on iOS & macOS using [Tor.xcframework](https://github.com/iCepa/Tor.framework) (iCepa) with obfs4/snowflake bridge support via [IPtProxy](https://github.com/nicveeper/IPtProxy).

## Features

- Embedded Tor client — no external processes or VPN profiles required.
- SOCKS5 proxy with automatic port assignment.
- Bridge support: built-in obfs4 and snowflake presets, or custom bridge lines.
- Reactive streams for connection status and native logs.
- Hot-restart safe — native singleton preserves Tor state across Dart restarts.

## Platform support

| iOS | macOS | Android | Web | Windows | Linux |
|:---:|:-----:|:-------:|:---:|:-------:|:-----:|
| ✅  |  ✅   |   —    |  —  |    —   |   —   |

## Getting started

### Requirements

- iOS 15.0+ / macOS 12.0+
- Flutter 3.3+

### Installation

```yaml
dependencies:
  flutter_tor: ^0.2.0
```

### macOS entitlements

Tor requires outbound network access. Add these to your macOS Runner entitlements (`DebugProfile.entitlements` and `Release.entitlements`):

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

## Usage

### Basic connection (no bridges)

```dart
import 'package:flutter_tor/flutter_tor.dart';

// Start Tor
await Tor.initialize();

// Listen for status changes
Tor.statusStream.listen((event) {
  print('${event.status} ${event.progress}%');
});

// Get SOCKS5 proxy port once connected
final port = await Tor.getProxyPort();

// Stop Tor
await Tor.stop();
```

### Using bridges

```dart
// Use built-in obfs4 bridges
await Tor.initialize(TorBridgePresets.obfs4Default);

// Use snowflake
await Tor.initialize(TorBridgePresets.snowflake);

// Use custom bridge lines
await Tor.initialize(TorBridgeConfig(
  useBridges: true,
  bridgeLines: ['obfs4 198.51.100.1:443 ...'],
));
```

### Fetching fresh bridges

Built-in bridge lines can become stale. `TorBridgePresets` can fetch up-to-date bridges from the Tor Project's [circumvention API](https://bridges.torproject.org/moat):

```dart
// Fetch fresh obfs4 bridges (country-aware, falls back to built-in list)
final config = await TorBridgePresets.fetchObfs4();
await Tor.initialize(config);

// Fetch fresh snowflake bridges
final sf = await TorBridgePresets.fetchSnowflake();
await Tor.initialize(sf);
```

Both methods throw on network failure — use the static presets (`obfs4Default`, `snowflake`) as a fallback.

### Making requests through Tor

Use the SOCKS5 proxy port with any HTTP client that supports SOCKS proxies (e.g., [socks5_proxy](https://pub.dev/packages/socks5_proxy)):

```dart
import 'dart:io';
import 'package:socks5_proxy/socks_client.dart';

final port = await Tor.getProxyPort();
final client = HttpClient();
SocksTCPClient.assignToHttpClient(client, [
  ProxySettings(InternetAddress.loopbackIPv4, port),
]);

final request = await client.getUrl(Uri.parse('https://check.torproject.org/api/ip'));
final response = await request.close();
```

### Controlling native logs

Native logs (NSLog and Tor stdout/stderr) can be disabled via a single flag. Set it **before** `initialize()` to also suppress Tor's early startup messages:

```dart
// Disable all native logs
Tor.logsEnabled = false;

await Tor.initialize();

// Re-enable at any time
Tor.logsEnabled = true;
```

### Recovering state after hot restart

Tor runs in a native singleton that outlives Dart restarts. Sync on startup:

```dart
final status = await Tor.getStatus();
if (status.status == TorStatus.connected) {
  final port = await Tor.getProxyPort();
  // ready to use
}
```

## API overview

| Class | Description |
|---|---|
| `Tor` | Main entry point — `initialize()`, `stop()`, `getProxyPort()`, `getStatus()`, `statusStream`, `logStream`, `logsEnabled`. `TorIos` is a deprecated alias |
| `TorBridgeConfig` | Bridge configuration with `useBridges`, `bridgeLines`, `useObfs4`, `useSnowflake` |
| `TorBridgePresets` | Ready-to-use presets: `obfs4Default`, `snowflake`, `noBridges` |
| `TorStatus` | Enum: `disconnected`, `connecting`, `connected`, `error` |
| `TorStatusEvent` | Status snapshot with `status`, `progress`, `errorMessage`, `bridges` |
| `TorLogEvent` | Native log entry with `level`, `tag`, `message`, `timestamp` |

## License

MIT License. See [LICENSE](LICENSE) for details.

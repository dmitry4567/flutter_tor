## 0.2.0

* macOS platform support.
* `TorBridgeFetcher` for fetching fresh obfs4 and snowflake bridges from bridges.torproject.org.
* `TorBridgePresets.fetchObfs4()` and `TorBridgePresets.fetchSnowflake()` convenience methods.
* New `Tor` class as the main entry point (`TorIos` is now a deprecated alias).

## 0.1.0

* Initial release.
* Embedded Tor client via Tor.xcframework (iCepa).
* SOCKS5 proxy support with automatic port assignment.
* Bridge support: obfs4 and snowflake via IPtProxy.
* Reactive status and log streams.
* Hot restart state recovery via native singleton.
* iOS platform support.

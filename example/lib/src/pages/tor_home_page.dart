import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:socks5_proxy/socks_client.dart';
import 'package:flutter_tor/flutter_tor.dart';

import '../models/bridge_mode.dart';
import '../widgets/bridge_selector.dart';
import '../widgets/fetch_section.dart';
import '../widgets/logs_view.dart';
import '../widgets/status_card.dart';

class TorHomePage extends StatefulWidget {
  const TorHomePage({super.key});

  @override
  State<TorHomePage> createState() => _TorHomePageState();
}

class _TorHomePageState extends State<TorHomePage> {
  TorStatusEvent _status = const TorStatusEvent(
    status: TorStatus.disconnected,
    progress: 0,
  );
  int? _proxyPort;
  BridgeMode _bridgeMode = BridgeMode.none;
  bool _bridgesSynced = false;

  final List<TorLogEvent> _logs = [];
  StreamSubscription<TorStatusEvent>? _statusSub;
  StreamSubscription<TorLogEvent>? _logSub;

  final TextEditingController _urlController = TextEditingController(
    text: 'https://check.torproject.org/api/ip',
  );
  final TextEditingController _customBridgeController = TextEditingController();
  String? _fetchResult;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();

    _statusSub = Tor.statusStream.listen((event) {
      setState(() {
        _status = event;
        _bridgesSynced = true;
      });
    });
    _logSub = Tor.logStream.listen((event) {
      setState(() {
        _logs.insert(0, event);
        if (_logs.length > 200) _logs.removeLast();
      });
    });
    _syncNativeState();
  }

  /// Pulls the current status, proxy port and bridge config from the
  /// native side. Tor lives in a native singleton that outlives Dart hot
  /// restarts, so without this sync the UI would show DISCONNECTED even
  /// though Tor is already running.
  Future<void> _syncNativeState() async {
    try {
      final status = await Tor.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _bridgeMode = BridgeModeX.fromConfig(status.bridges);
        _bridgesSynced = true;
      });

      if (status.status == TorStatus.connected ||
          status.status == TorStatus.connecting) {
        final port = await Tor.getProxyPort();
        if (!mounted) return;
        setState(() => _proxyPort = port);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _logSub?.cancel();
    _urlController.dispose();
    _customBridgeController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _fetchResult = null;
      _proxyPort = null;
    });
    try {
      final customLines = _customBridgeController.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      await Tor.initialize(_bridgeMode.toConfig(customLines: customLines));
      final port = await Tor.getProxyPort();
      setState(() => _proxyPort = port);
    } catch (e) {
      _showSnack('Start error: $e');
    }
  }

  Future<void> _stop() async {
    try {
      await Tor.stop();
    } catch (e) {
      _showSnack('Stop error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _status = const TorStatusEvent(
            status: TorStatus.disconnected,
            progress: 0,
          );
          _proxyPort = null;
          _fetchResult = null;
        });
      }
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await Tor.getStatus();
      setState(() => _status = s);
    } catch (e) {
      _showSnack('Status error: $e');
    }
  }

  /// Performs an HTTP(S) request through the Tor SOCKS5 proxy.
  Future<void> _fetchThroughTor() async {
    final port = _proxyPort;
    if (port == null || port == 0) {
      _showSnack('Start Tor first');
      return;
    }
    if (_status.status != TorStatus.connected) {
      _showSnack('Tor is not connected yet (${_status.progress}%)');
      return;
    }

    setState(() {
      _fetching = true;
      _fetchResult = null;
    });

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      SocksTCPClient.assignToHttpClient(client, [
        ProxySettings(InternetAddress.loopbackIPv4, port),
      ]);

      final uri = Uri.parse(_urlController.text.trim());
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);

      setState(() {
        _fetchResult = 'HTTP ${response.statusCode}\n\n$body';
      });
    } catch (e) {
      setState(() => _fetchResult = 'Error: $e');
    } finally {
      setState(() => _fetching = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Color _statusColor() {
    switch (_status.status) {
      case TorStatus.connected:
        return Colors.greenAccent;
      case TorStatus.connecting:
        return Colors.amber;
      case TorStatus.error:
        return Colors.redAccent;
      case TorStatus.disconnected:
        return Colors.white60;
    }
  }

  String _statusLabel() {
    switch (_status.status) {
      case TorStatus.connected:
        return 'CONNECTED';
      case TorStatus.connecting:
        return 'CONNECTING ${_status.progress}%';
      case TorStatus.error:
        return 'ERROR';
      case TorStatus.disconnected:
        return 'DISCONNECTED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning =
        _status.status == TorStatus.connected ||
        _status.status == TorStatus.connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('tor demo'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh status',
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomScrollView(
              physics: ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StatusCard(
                        label: _statusLabel(),
                        color: _statusColor(),
                        progress: _status.progress,
                        proxyPort: _proxyPort,
                        error: _status.errorMessage,
                      ),
                      const SizedBox(height: 12),
                      if (_bridgesSynced)
                        BridgeSelector(
                          current: _bridgeMode,
                          enabled: !isRunning,
                          onChanged: (m) => setState(() => _bridgeMode = m),
                          customBridgeController: _customBridgeController,
                        )
                      else
                        const BridgeSelectorPlaceholder(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Start'),
                              onPressed: isRunning ? null : _start,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              icon: const Icon(Icons.stop),
                              label: const Text('Stop'),
                              onPressed: isRunning ? _stop : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FetchSection(
                        controller: _urlController,
                        fetching: _fetching,
                        onFetch: _fetchThroughTor,
                        result: _fetchResult,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 300, child: LogsView(logs: _logs)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

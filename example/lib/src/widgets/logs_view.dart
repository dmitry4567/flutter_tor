import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tor/flutter_tor.dart';

class LogsView extends StatelessWidget {
  final List<TorLogEvent> logs;

  const LogsView({super.key, required this.logs});

  Color _levelColor(String level) {
    switch (level) {
      case 'error':
        return Colors.redAccent;
      case 'warn':
        return Colors.amber;
      case 'success':
        return Colors.greenAccent;
      case 'header':
        return Colors.cyanAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Native logs (${logs.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.copy, size: 18),
                    disabledColor: Colors.grey.shade700,
                    onPressed: logs.isEmpty
                        ? null
                        : () {
                            final text = logs.reversed
                                .map((e) => '[${e.tag}] ${e.message}')
                                .join('\n');
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Logs copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                  ),
                ),
              ],
            ),
            const Divider(height: 10),
            Expanded(
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Logs will appear after Tor starts',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: logs.length,
                      itemBuilder: (_, i) {
                        final e = logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '[${e.tag}] ${e.message}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: _levelColor(e.level),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

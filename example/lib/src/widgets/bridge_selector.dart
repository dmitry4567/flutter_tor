import 'package:flutter/material.dart';

import '../models/bridge_mode.dart';

class BridgeSelector extends StatelessWidget {
  final BridgeMode current;
  final bool enabled;
  final ValueChanged<BridgeMode> onChanged;
  final TextEditingController customBridgeController;

  const BridgeSelector({
    super.key,
    required this.current,
    required this.enabled,
    required this.onChanged,
    required this.customBridgeController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bridges', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('No bridges'),
                  selected: current == BridgeMode.none,
                  onSelected: enabled
                      ? (_) => onChanged(BridgeMode.none)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('obfs4'),
                  selected: current == BridgeMode.obfs4,
                  onSelected: enabled
                      ? (_) => onChanged(BridgeMode.obfs4)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('Snowflake'),
                  selected: current == BridgeMode.snowflake,
                  onSelected: enabled
                      ? (_) => onChanged(BridgeMode.snowflake)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('Custom obfs4'),
                  selected: current == BridgeMode.customObfs4,
                  onSelected: enabled
                      ? (_) => onChanged(BridgeMode.customObfs4)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('Custom Snowflake'),
                  selected: current == BridgeMode.customSnowflake,
                  onSelected: enabled
                      ? (_) => onChanged(BridgeMode.customSnowflake)
                      : null,
                ),
              ],
            ),
            if (current.isCustom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: customBridgeController,
                enabled: enabled,
                maxLines: 4,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: current == BridgeMode.customObfs4
                      ? 'Enter obfs4 bridge lines (one per line)'
                      : 'Enter snowflake bridge lines (one per line)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder of the same height as [BridgeSelector], rendered until the
/// first bridge-config snapshot arrives from the native side.
class BridgeSelectorPlaceholder extends StatelessWidget {
  const BridgeSelectorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bridges', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

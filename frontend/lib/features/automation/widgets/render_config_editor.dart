import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/render_config.dart';
import '../providers/render_config_presets_provider.dart';

class RenderConfigEditor extends ConsumerWidget {
  const RenderConfigEditor({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final RenderConfig config;
  final ValueChanged<RenderConfig> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(renderConfigPresetsProvider);
    return presets.when(
      data: (items) => Column(
        children: [
          for (final preset in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                (config['format'] ?? 'summary') == preset.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: (config['format'] ?? 'summary') == preset.id
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(preset.name),
              subtitle: preset.description == null
                  ? null
                  : Text(preset.description!),
              selected: (config['format'] ?? 'summary') == preset.id,
              onTap: () => onChanged(preset.config),
            ),
        ],
      ),
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => TextButton.icon(
        onPressed: () => ref.invalidate(renderConfigPresetsProvider),
        icon: const Icon(Icons.refresh),
        label: const Text('重新加载推送格式'),
      ),
    );
  }
}

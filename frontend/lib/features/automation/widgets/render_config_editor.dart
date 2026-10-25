import '../../../core/widgets/app_setting_group.dart';

import 'package:material_ui/material_ui.dart';
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
      data: (items) => RadioGroup<String>(
        groupValue: config['format'] as String? ?? 'summary',
        onChanged: (value) {
          final preset = items.where((item) => item.id == value).firstOrNull;
          if (preset != null) onChanged(preset.config);
        },
        child: AppSettingGroup(
          children: [
            for (final preset in items)
              RadioListTile<String>(
                value: preset.id,
                title: Text(preset.name),
                shape: const RoundedRectangleBorder(),
                subtitle: preset.description == null
                    ? null
                    : Text(preset.description!),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
          ],
        ),
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

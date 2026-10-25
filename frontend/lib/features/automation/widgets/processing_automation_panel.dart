import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/models/system_setting.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/utils/setting_value.dart';
import '../../settings/presentation/widgets/setting_components.dart';
import '../../settings/presentation/widgets/media_archive_settings.dart';

class ProcessingAutomationPanel extends ConsumerWidget {
  const ProcessingAutomationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(systemSettingsProvider);
    return state.when(
      loading: () => const LoadingGroup(),
      error: (_, _) => SettingLoadFailure(
        onRetry: () => ref.invalidate(systemSettingsProvider),
      ),
      data: (settings) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          const SectionHeader(title: '自动处理'),
          SettingGroup(
            children: [
              _toggle(ref, settings, '解析新内容', 'enable_parse_worker', true),
              _toggle(
                ref,
                settings,
                '生成摘要',
                'enable_auto_summary',
                false,
                category: 'llm',
              ),
              _toggle(
                ref,
                settings,
                '建立搜索索引',
                'enable_auto_semantic_indexing',
                true,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: '内容整理'),
          SettingGroup(
            children: [
              _toggle(
                ref,
                settings,
                '自动整理相关内容',
                'enable_content_aggregation',
                false,
              ),
              _toggle(
                ref,
                settings,
                '发送整理结果',
                'enable_aggregation_push',
                false,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: '媒体归档'),
          const MediaArchiveSettings(),
        ],
      ),
    );
  }

  Widget _toggle(
    WidgetRef ref,
    List<SystemSetting> settings,
    String title,
    String key,
    bool defaultValue, {
    String category = 'automation',
  }) => SettingSwitch(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    title: Text(title),
    value: parseBoolSetting(
      getSettingValue(settings, key, defaultValue),
      defaultValue,
    ),
    onChanged: (value) => ref
        .read(systemSettingsProvider.notifier)
        .updateSetting(key, value, category: category),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';

class SystemTab extends ConsumerWidget {
  const SystemTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final settingsAsync = ref.watch(systemSettingsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        const SectionHeader(title: '外观模式'),
        SettingGroup(
          children: [
            SettingTile(
              title: '主题模式',
              subtitle: _getThemeModeName(themeMode),
              icon: Icons.palette_rounded,
              onTap: () => _showThemePicker(context, ref, themeMode),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const SectionHeader(title: '存储与归档策略'),
        _buildStorageSettings(context, ref, settingsAsync),
        const SizedBox(height: 32),
        const SectionHeader(title: '关于与许可'),
        SettingGroup(
          children: [
            SettingTile(
              title: '开源许可',
              subtitle: '查看第三方库授权信息',
              icon: Icons.info_outline_rounded,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'VaultStream',
                applicationVersion: 'v0.1.0-alpha',
              ),
            ),
          ],
        ),
        const SizedBox(height: 64),
        _buildAppInfo(context),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStorageSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        final enableProcessing = settings.firstWhere(
          (s) => s.key == 'enable_archive_media_processing',
          orElse: () => const SystemSetting(key: '', value: true),
        ).value as bool? ?? true;
        
        final webpQuality = settings.firstWhere(
          (s) => s.key == 'archive_image_webp_quality',
          orElse: () => const SystemSetting(key: '', value: 80),
        ).value as int? ?? 80;
        
        final maxCount = settings.firstWhere(
          (s) => s.key == 'archive_image_max_count',
          orElse: () => const SystemSetting(key: '', value: 0), // 0 or null means unlimited
        ).value as int? ?? 0;

        return SettingGroup(
          children: [
            SettingTile(
              title: '启用媒体压缩处理',
              subtitle: enableProcessing ? '自动转码为 WebP 以节省空间' : '保留原始图片格式',
              icon: Icons.compress_rounded,
              trailing: Switch(
                value: enableProcessing,
                // M3 Style: Thumb icon
                thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Icon(Icons.check);
                    }
                    return null; // 默认无图标
                  },
                ),
                onChanged: (val) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting('enable_archive_media_processing', val, category: 'storage'),
              ),
              onTap: () => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting('enable_archive_media_processing', !enableProcessing, category: 'storage'),
            ),
            if (enableProcessing)
              ExpandableSettingTile(
                title: '压缩质量与限制',
                subtitle: 'WebP 质量: $webpQuality% | 数量限制: ${maxCount == 0 ? "无限制" : maxCount}',
                icon: Icons.tune_rounded,
                expandedContent: _buildStorageAdvanced(context, ref, webpQuality, maxCount),
              ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildStorageAdvanced(BuildContext context, WidgetRef ref, int quality, int maxCount) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('WebP 压缩质量', style: textTheme.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$quality%',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Icon(Icons.image_not_supported_rounded, size: 20, color: colorScheme.outline),
            Expanded(
              child: Slider(
                value: quality.toDouble(),
                min: 10,
                max: 100,
                divisions: 9, // 10, 20... 100
                label: '$quality%',
                onChanged: (val) {
                   ref.read(systemSettingsProvider.notifier)
                      .updateSetting('archive_image_webp_quality', val.toInt(), category: 'storage');
                },
              ),
            ),
            Icon(Icons.high_quality_rounded, size: 20, color: colorScheme.primary),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: TextEditingController(text: maxCount.toString()),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '单帖最大图片数限制',
            helperText: '0 表示无限制，推荐设置为 20-50 以节省空间',
            prefixIcon: const Icon(Icons.collections_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          onSubmitted: (val) {
            final num = int.tryParse(val) ?? 0;
            ref.read(systemSettingsProvider.notifier)
               .updateSetting('archive_image_max_count', num, category: 'storage');
          },
        ),
      ],
    );
  }

  String _getThemeModeName(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '深色模式',
  };

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPickerOption(
              context,
              '跟随系统',
              Icons.brightness_auto_rounded,
              currentMode == ThemeMode.system,
              () => _setTheme(context, ref, ThemeMode.system),
            ),
            _buildPickerOption(
              context,
              '浅色模式',
              Icons.light_mode_rounded,
              currentMode == ThemeMode.light,
              () => _setTheme(context, ref, ThemeMode.light),
            ),
            _buildPickerOption(
              context,
              '深色模式',
              Icons.dark_mode_rounded,
              currentMode == ThemeMode.dark,
              () => _setTheme(context, ref, ThemeMode.dark),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerOption(
    BuildContext context,
    String title,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : null),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: onTap,
    );
  }

  void _setTheme(BuildContext context, WidgetRef ref, ThemeMode mode) {
    ref.read(themeModeProvider.notifier).set(mode);
    Navigator.pop(context);
  }

  Widget _buildAppInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.vape_free_rounded,
            size: 48,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'VaultStream',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Version 0.1.0 (Alpha)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

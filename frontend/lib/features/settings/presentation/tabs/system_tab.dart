import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../theme/design_tokens.dart';

class SystemTab extends ConsumerWidget {
  const SystemTab({super.key, this.storageOnly = false});

  final bool storageOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final settingsAsync = ref.watch(systemSettingsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: storageOnly
          ? [_buildStorageSettings(context, ref, settingsAsync)]
          : [
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
              const SectionHeader(title: '关于与许可'),
              SettingGroup(
                children: [
                  SettingTile(
                    title: '开源许可',
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
        bool parseBool(dynamic val, {bool defaultVal = true}) {
          if (val == null) return defaultVal;
          if (val is bool) return val;
          if (val is String) return val.toLowerCase() == 'true';
          return defaultVal;
        }

        int parseInt(dynamic val, {int defaultVal = 0}) {
          if (val == null) return defaultVal;
          if (val is int) return val;
          if (val is num) return val.toInt();
          if (val is String) return int.tryParse(val) ?? defaultVal;
          return defaultVal;
        }

        final enableProcessing = parseBool(
          settings
              .firstWhere(
                (s) => s.key == 'enable_archive_media_processing',
                orElse: () => const SystemSetting(key: '', value: true),
              )
              .value,
          defaultVal: true,
        );
        final enableImages = parseBool(
          settings
              .firstWhere(
                (s) => s.key == 'enable_archive_image_processing',
                orElse: () => const SystemSetting(key: '', value: true),
              )
              .value,
          defaultVal: true,
        );
        final enableVideos = parseBool(
          settings
              .firstWhere(
                (s) => s.key == 'enable_archive_video_processing',
                orElse: () => const SystemSetting(key: '', value: true),
              )
              .value,
          defaultVal: true,
        );

        final webpQuality = parseInt(
          settings
              .firstWhere(
                (s) => s.key == 'archive_image_webp_quality',
                orElse: () => const SystemSetting(key: '', value: 80),
              )
              .value,
          defaultVal: 80,
        );

        final maxCount = parseInt(
          settings
              .firstWhere(
                (s) => s.key == 'archive_image_max_count',
                orElse: () => const SystemSetting(key: '', value: 0),
              )
              .value,
        );
        final videoMaxCount = parseInt(
          settings
              .firstWhere(
                (s) => s.key == 'archive_video_max_count',
                orElse: () => const SystemSetting(key: '', value: 0),
              )
              .value,
        );
        final videoMaxBytes = parseInt(
          settings
              .firstWhere(
                (s) => s.key == 'archive_video_max_bytes',
                orElse: () => const SystemSetting(key: '', value: 0),
              )
              .value,
        );

        return SettingGroup(
          children: [
            SettingTile(
              title: '自动归档远程媒体',
              subtitle: enableProcessing ? '按策略归档图片和视频' : '不下载网络媒体到本地',
              icon: Icons.compress_rounded,
              trailing: Switch(
                value: enableProcessing,
                // M3 Style: Thumb icon
                thumbIcon: WidgetStateProperty.resolveWith<Icon?>((
                  Set<WidgetState> states,
                ) {
                  if (states.contains(WidgetState.selected)) {
                    return const Icon(Icons.check);
                  }
                  return null; // 默认无图标
                }),
                onChanged: (val) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting(
                      'enable_archive_media_processing',
                      val,
                      category: 'storage',
                    ),
              ),
              onTap: () => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'enable_archive_media_processing',
                    !enableProcessing,
                    category: 'storage',
                  ),
            ),
            if (enableProcessing) ...[
              SettingTile(
                title: '归档远程图片',
                subtitle: enableImages ? '启用 WebP 转换和数量限制' : '跳过图片归档',
                icon: Icons.image_rounded,
                trailing: Switch(
                  value: enableImages,
                  onChanged: (val) => ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'enable_archive_image_processing',
                        val,
                        category: 'storage',
                      ),
                ),
              ),
              SettingTile(
                title: '归档远程视频',
                subtitle: enableVideos ? '启用视频数量和体积限制' : '跳过视频归档',
                icon: Icons.movie_creation_rounded,
                trailing: Switch(
                  value: enableVideos,
                  onChanged: (val) => ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'enable_archive_video_processing',
                        val,
                        category: 'storage',
                      ),
                ),
              ),
              ExpandableSettingTile(
                title: '归档质量与限制',
                subtitle:
                    'WebP: $webpQuality% | 图片: ${maxCount == 0 ? "无限制" : maxCount} | 视频: ${videoMaxCount == 0 ? "无限制" : videoMaxCount}',
                icon: Icons.tune_rounded,
                expandedContent: _buildStorageAdvanced(
                  context,
                  ref,
                  webpQuality,
                  maxCount,
                  videoMaxCount,
                  videoMaxBytes,
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildStorageAdvanced(
    BuildContext context,
    WidgetRef ref,
    int quality,
    int maxCount,
    int videoMaxCount,
    int videoMaxBytes,
  ) {
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
                  borderRadius: BorderRadius.circular(AppShape.pill),
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
            Icon(
              Icons.image_not_supported_rounded,
              size: 20,
              color: colorScheme.outline,
            ),
            Expanded(
              child: Slider(
                value: quality.toDouble(),
                min: 10,
                max: 100,
                divisions: 9, // 10, 20... 100
                label: '$quality%',
                onChanged: (val) {
                  ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'archive_image_webp_quality',
                        val.toInt(),
                        category: 'storage',
                      );
                },
              ),
            ),
            Icon(
              Icons.high_quality_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
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
            border: const OutlineInputBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
          ),
          onSubmitted: (val) {
            final num = int.tryParse(val) ?? 0;
            ref
                .read(systemSettingsProvider.notifier)
                .updateSetting(
                  'archive_image_max_count',
                  num,
                  category: 'storage',
                );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: TextEditingController(text: videoMaxCount.toString()),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '单条最大视频数限制',
            helperText: '0 表示无限制',
            prefixIcon: const Icon(Icons.video_library_rounded),
            border: const OutlineInputBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
          ),
          onSubmitted: (val) {
            final num = int.tryParse(val) ?? 0;
            ref
                .read(systemSettingsProvider.notifier)
                .updateSetting(
                  'archive_video_max_count',
                  num,
                  category: 'storage',
                );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: TextEditingController(text: videoMaxBytes.toString()),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '单个视频最大字节数',
            helperText: '0 表示使用默认上限',
            prefixIcon: const Icon(Icons.sd_storage_rounded),
            border: const OutlineInputBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
          ),
          onSubmitted: (val) {
            final num = int.tryParse(val) ?? 0;
            ref
                .read(systemSettingsProvider.notifier)
                .updateSetting(
                  'archive_video_max_bytes',
                  num,
                  category: 'storage',
                );
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
          borderRadius: AppShape.sheetTopBorder,
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
            Icons.inventory_2_rounded,
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
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final version = snapshot.data!.version;
              final buildNumber = snapshot.data!.buildNumber;
              return Text(
                'Version $version ($buildNumber)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

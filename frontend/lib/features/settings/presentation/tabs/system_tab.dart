import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/widgets/app_filter_menu.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';
import '../licenses_page.dart';
import '../widgets/settings_editor_draft.dart';
import '../widgets/settings_slider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../theme/design_tokens.dart';

class SystemTab extends ConsumerWidget {
  const SystemTab({super.key, this.storageOnly = false});

  final bool storageOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: storageOnly
          ? [
              _buildStorageSettings(
                context,
                ref,
                ref.watch(systemSettingsProvider),
              ),
            ]
          : [
              AppFilterMenu(
                label: '外观模式',
                value: ref.watch(themeModeProvider).name,
                options: const {
                  'system': '跟随系统',
                  'light': '浅色模式',
                  'dark': '深色模式',
                },
                onSelected: (value) => ref
                    .read(themeModeProvider.notifier)
                    .set(ThemeMode.values.byName(value)),
              ),
              const SizedBox(height: 32),
              const _AppAboutSection(),
            ],
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
        child: content,
      ),
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

        final switchShape = const RoundedRectangleBorder(
          borderRadius: AppShape.cardMediaBorder,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              shape: switchShape,
              title: const Text('自动归档远程媒体'),
              subtitle: Text(enableProcessing ? '按策略归档图片和视频' : '不下载网络媒体到本地'),
              value: enableProcessing,
              onChanged: (val) => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'enable_archive_media_processing',
                    val,
                    category: 'storage',
                  ),
            ),
            if (enableProcessing) ...[
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                shape: switchShape,
                title: const Text('归档远程图片'),
                value: enableImages,
                onChanged: (val) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting(
                      'enable_archive_image_processing',
                      val,
                      category: 'storage',
                    ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                shape: switchShape,
                title: const Text('归档远程视频'),
                value: enableVideos,
                onChanged: (val) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting(
                      'enable_archive_video_processing',
                      val,
                      category: 'storage',
                    ),
              ),
              const SizedBox(height: 16),
              ExpandableSettingTile(
                title: '归档质量与限制',
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
    return SettingsEditorDraft(
      initialValues: {
        'archive_image_max_count': maxCount.toString(),
        'archive_video_max_count': videoMaxCount.toString(),
        'archive_video_max_bytes': videoMaxBytes.toString(),
      },
      builder: (context, controllers) {
        final textTheme = Theme.of(context).textTheme;
        Widget limitField(String title, String help, String settingKey) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: textTheme.bodyLarge),
              const SizedBox(height: 8),
              Semantics(
                label: title,
                child: TextField(
                  controller: controllers[settingKey],
                  keyboardType: TextInputType.number,
                  onSubmitted: (val) {
                    final num = int.tryParse(val) ?? 0;
                    ref
                        .read(systemSettingsProvider.notifier)
                        .updateSetting(settingKey, num, category: 'storage');
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                help,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSlider(
              title: 'WebP 压缩质量',
              value: quality.toDouble(),
              min: 10,
              max: 100,
              divisions: 9,
              formatValue: (value) => '${value.toInt()}%',
              errorMessage: '压缩质量保存失败',
              onSaved: (value) => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'archive_image_webp_quality',
                    value.toInt(),
                    category: 'storage',
                  ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final columns = constraints.maxWidth >= 600 * scale ? 2 : 1;
                final fieldWidth =
                    (constraints.maxWidth - 24 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: limitField(
                        '单条内容最多图片数',
                        '0 表示不限数量；建议 20–50 张以节省空间。',
                        'archive_image_max_count',
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: limitField(
                        '单条内容最多视频数',
                        '0 表示不限数量。',
                        'archive_video_max_count',
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: limitField(
                        '单个视频上限（字节）',
                        '0 表示使用默认上限。',
                        'archive_video_max_bytes',
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _AppAboutSection extends StatefulWidget {
  const _AppAboutSection();
  @override
  State<_AppAboutSection> createState() => _AppAboutSectionState();
}

class _AppAboutSectionState extends State<_AppAboutSection> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final version = info == null
          ? null
          : '${info.version} (${info.buildNumber})';
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VaultStream', style: theme.textTheme.titleMedium),
                if (version != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '版本 $version',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            shape: const RoundedRectangleBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            title: const Text('开源许可'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context, rootNavigator: true).push<void>(
              MaterialPageRoute(
                builder: (context) =>
                    AppLicensesPage(applicationVersion: version),
              ),
            ),
          ),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';
import '../../../discovery/providers/discovery_settings_provider.dart';
import '../../../discovery/providers/discovery_sources_provider.dart';
import '../../../discovery/models/discovery_models.dart';
import '../../providers/favorites_sync_provider.dart';

class AutomationTab extends ConsumerWidget {
  const AutomationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final discoverySettingsAsync = ref.watch(discoverySettingsStateProvider);
    final discoverySourcesAsync = ref.watch(discoverySourcesProvider);
    final favoritesSyncAsync = ref.watch(favoritesSyncStatusProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        const SectionHeader(title: 'AI 巡逻 (Patrol)', icon: Icons.auto_awesome_rounded),
        _buildPatrolSettings(context, ref, discoverySettingsAsync),
        const SizedBox(height: 32),
        const SectionHeader(title: '发现来源 (Sources)', icon: Icons.sensors_rounded),
        _buildDiscoverySources(context, ref, discoverySourcesAsync),
        const SizedBox(height: 32),
        const SectionHeader(title: '收藏自动同步', icon: Icons.bookmark_added_rounded),
        _buildFavoritesSyncSettings(context, ref, settingsAsync, favoritesSyncAsync),
        const SizedBox(height: 32),
        const SectionHeader(title: '内容生成', icon: Icons.summarize_rounded),
        _buildContentGenSettings(context, ref, settingsAsync),
        const SizedBox(height: 32),
        const SectionHeader(
          title: '大模型引擎 (LLM)',
          icon: Icons.psychology_rounded,
        ),
        _buildLlmSettings(context, ref, settingsAsync),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPatrolSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DiscoverySettings> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) => SettingGroup(
        children: [
          ExpandableSettingTile(
            title: '我的兴趣画像',
            subtitle: settings.interestProfile.isEmpty ? '描述你感兴趣的内容' : settings.interestProfile,
            icon: Icons.face_retouching_natural_rounded,
            expandedContent: _buildInterestProfileEditor(context, ref, settings.interestProfile),
          ),
          SettingTile(
            title: 'AI 评分阈值',
            subtitle: '当前阈值: ${settings.scoreThreshold.toStringAsFixed(1)}',
            icon: Icons.shutter_speed_rounded,
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: settings.scoreThreshold,
                min: 0,
                max: 10,
                divisions: 20,
                onChanged: (val) => ref.read(discoverySettingsStateProvider.notifier).updateSettings(scoreThreshold: val),
              ),
            ),
          ),
          SettingTile(
            title: '发现保留天数',
            subtitle: '${settings.retentionDays} 天后自动清理',
            icon: Icons.auto_delete_rounded,
            trailing: DropdownButton<int>(
              value: settings.retentionDays,
              underline: const SizedBox.shrink(),
              items: [1, 3, 7, 15, 30].map((d) => DropdownMenuItem(
                value: d,
                child: Text('$d 天'),
              )).toList(),
              onChanged: (val) {
                if (val != null) {
                  ref.read(discoverySettingsStateProvider.notifier).updateSettings(retentionDays: val);
                }
              },
            ),
          ),
        ],
      ),
      loading: () => const LoadingGroup(),
      error: (error, _) => const Text('加载失败'),
    );
  }

  Widget _buildInterestProfileEditor(BuildContext context, WidgetRef ref, String currentProfile) {
    final controller = TextEditingController(text: currentProfile);
    return Column(
      children: [
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '描述你感兴趣的领域、技术栈、博主或关键词...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const Gap(12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref.read(discoverySettingsStateProvider.notifier).updateSettings(interestProfile: controller.text);
              if (context.mounted) showToast(context, '兴趣画像已更新');
            },
            child: const Text('更新画像'),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverySources(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<DiscoverySource>> sourcesAsync,
  ) {
    return sourcesAsync.when(
      data: (sources) {
        if (sources.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: OutlinedButton.icon(
                onPressed: () => _showAddSourceDialog(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加第一个发现来源'),
              ),
            ),
          );
        }
        return Column(
          children: [
            SettingGroup(
              children: sources.map((s) => _buildSourceTile(context, ref, s)).toList(),
            ),
            const Gap(12),
            OutlinedButton.icon(
              onPressed: () => _showAddSourceDialog(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加来源'),
            ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) => const Text('加载失败'),
    );
  }

  Widget _buildSourceTile(BuildContext context, WidgetRef ref, DiscoverySource source) {
    return SettingTile(
      title: source.name,
      subtitle: '${source.kind.toUpperCase()} • 每 ${source.syncIntervalMinutes} 分钟同步',
      icon: _sourceIcon(source.kind),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: source.enabled,
            onChanged: (val) => ref.read(discoverySourcesProvider.notifier).updateSource(source.id, enabled: val),
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              await ref.read(discoverySourcesProvider.notifier).triggerSync(source.id);
              if (context.mounted) showToast(context, '已手动触发同步');
            },
          ),
        ],
      ),
      onTap: () => _showEditSourceDialog(context, ref, source),
    );
  }

  IconData _sourceIcon(String kind) {
    switch (kind.toLowerCase()) {
      case 'rss': return Icons.rss_feed_rounded;
      case 'hackernews': return Icons.whatshot_rounded;
      case 'reddit': return Icons.forum_rounded;
      case 'telegram_channel': return Icons.telegram_rounded;
      default: return Icons.sensors_rounded;
    }
  }

  Widget _buildFavoritesSyncSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
    AsyncValue<FavoritesSyncStatus> statusAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        final currentEnabled = _parsePlatformsSetting(
          _getSettingValue(settings, 'favorites_sync_platforms', const <String>[]),
        );
        const intervalOptions = <int>[60, 180, 360, 720, 1440];
        const maxItemOptions = <int>[20, 50, 100, 200];
        const rateOptions = <int>[1, 3, 5, 10, 20];
        final interval = _parseInt(
          _getSettingValue(settings, 'favorites_sync_interval_minutes', 360),
          360,
        );
        final maxItems = _parseInt(
          _getSettingValue(settings, 'favorites_sync_max_items', 50),
          50,
        );

        return statusAsync.when(
          data: (status) {
            final statusMap = <String, FavoritesPlatformStatus>{
              for (final item in status.platforms) item.platform: item,
            };
            final platforms = <String>['zhihu', 'xiaohongshu', 'twitter'];

            return SettingGroup(
              children: [
                for (final platform in platforms)
                  SettingTile(
                    title: _platformLabel(platform),
                    subtitle: _platformSubtitle(
                      platform: platform,
                      configuredRate: _parseDouble(
                        _getSettingValue(
                          settings,
                          'favorites_sync_rate_$platform',
                          5,
                        ),
                        statusMap[platform]?.ratePerMinute ?? 5,
                      ),
                      status: statusMap[platform],
                    ),
                    icon: _platformIcon(platform),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<int>(
                          value: (() {
                            final configuredRate = _parseDouble(
                              _getSettingValue(
                                settings,
                                'favorites_sync_rate_$platform',
                                5,
                              ),
                              statusMap[platform]?.ratePerMinute ?? 5,
                            ).round();
                            return rateOptions.contains(configuredRate) ? configuredRate : 5;
                          })(),
                          underline: const SizedBox.shrink(),
                          items: rateOptions
                              .map(
                                (rate) => DropdownMenuItem<int>(
                                  value: rate,
                                  child: Text('$rate/min'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            await ref.read(systemSettingsProvider.notifier).updateSetting(
                              'favorites_sync_rate_$platform',
                              value,
                              category: 'favorites_sync',
                            );
                            ref.invalidate(favoritesSyncStatusProvider);
                            if (context.mounted) {
                              showToast(context, '${_platformLabel(platform)} 速率已更新');
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: currentEnabled.contains(platform),
                          onChanged: (enabled) async {
                            final updated = [...currentEnabled];
                            if (enabled) {
                              if (!updated.contains(platform)) updated.add(platform);
                            } else {
                              updated.remove(platform);
                            }
                            await ref.read(systemSettingsProvider.notifier).updateSetting(
                              'favorites_sync_platforms',
                              updated,
                              category: 'favorites_sync',
                            );
                            ref.invalidate(favoritesSyncStatusProvider);
                            if (context.mounted) {
                              showToast(context, '${_platformLabel(platform)} 已${enabled ? '启用' : '禁用'}同步');
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.sync_rounded),
                          tooltip: '手动同步 ${_platformLabel(platform)}',
                          onPressed: statusMap[platform]?.available == false
                              ? null
                              : () async {
                                  await ref
                                      .read(favoritesSyncActionsProvider)
                                      .triggerSync(platform: platform);
                                  if (context.mounted) {
                                    showToast(context, '已触发 ${_platformLabel(platform)} 同步');
                                  }
                                },
                        ),
                      ],
                    ),
                    showArrow: false,
                  ),
                SettingTile(
                  title: '同步间隔',
                  subtitle: '当前每 $interval 分钟执行一次',
                  icon: Icons.schedule_rounded,
                  trailing: DropdownButton<int>(
                    value: intervalOptions.contains(interval) ? interval : 360,
                    underline: const SizedBox.shrink(),
                    items: intervalOptions
                        .map(
                          (val) => DropdownMenuItem<int>(
                            value: val,
                            child: Text(val >= 60 ? '${val ~/ 60}h' : '$val min'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      await ref.read(systemSettingsProvider.notifier).updateSetting(
                        'favorites_sync_interval_minutes',
                        value,
                        category: 'favorites_sync',
                      );
                      ref.invalidate(favoritesSyncStatusProvider);
                    },
                  ),
                  showArrow: false,
                ),
                SettingTile(
                  title: '单次拉取上限',
                  subtitle: '每个平台单轮最多拉取 $maxItems 条',
                  icon: Icons.numbers_rounded,
                  trailing: DropdownButton<int>(
                    value: maxItemOptions.contains(maxItems) ? maxItems : 50,
                    underline: const SizedBox.shrink(),
                    items: maxItemOptions
                        .map(
                          (val) => DropdownMenuItem<int>(
                            value: val,
                            child: Text('$val'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      await ref.read(systemSettingsProvider.notifier).updateSetting(
                        'favorites_sync_max_items',
                        value,
                        category: 'favorites_sync',
                      );
                      ref.invalidate(favoritesSyncStatusProvider);
                    },
                  ),
                  showArrow: false,
                ),
                SettingTile(
                  title: '立即同步',
                  subtitle: status.lastSyncAt == null
                      ? '尚未同步'
                      : '上次同步: ${status.lastSyncAt}',
                  icon: status.running ? Icons.play_circle_fill_rounded : Icons.pause_circle_filled_rounded,
                  trailing: FilledButton.tonalIcon(
                    onPressed: () async {
                      await ref.read(favoritesSyncActionsProvider).triggerSync();
                      if (context.mounted) showToast(context, '已触发全平台同步');
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('手动同步'),
                  ),
                  showArrow: false,
                ),
              ],
            );
          },
          loading: () => const LoadingGroup(),
          error: (error, _) => const Text('收藏同步状态加载失败'),
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) => const Text('配置加载失败'),
    );
  }

  String _platformLabel(String platform) {
    switch (platform) {
      case 'zhihu':
        return '知乎';
      case 'xiaohongshu':
        return '小红书';
      case 'twitter':
        return 'Twitter / X';
      default:
        return platform;
    }
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'zhihu':
        return Icons.menu_book_rounded;
      case 'xiaohongshu':
        return Icons.auto_stories_rounded;
      case 'twitter':
        return Icons.alternate_email_rounded;
      default:
        return Icons.bookmark_rounded;
    }
  }

  String _platformSubtitle({
    required String platform,
    required double configuredRate,
    required FavoritesPlatformStatus? status,
  }) {
    final authText = switch ((status?.available ?? true, status?.authenticated ?? false, platform)) {
      (false, _, _) => '状态检查失败',
      (_, true, _) => '已认证',
      (_, false, 'twitter') => 'CLI 未就绪或未登录',
      _ => '未登录',
    };
    return '$authText · ${configuredRate.toStringAsFixed(0)} 条/分钟';
  }

  dynamic _getSettingValue(List<SystemSetting> settings, String key, dynamic fallback) {
    try {
      return settings.firstWhere((s) => s.key == key).value;
    } catch (_) {
      return fallback;
    }
  }

  List<String> _parsePlatformsSetting(dynamic raw) {
    if (raw == null) return <String>[];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double _parseDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  Widget _buildContentGenSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        bool parseBool(dynamic val) {
          if (val == null) return false;
          if (val is bool) return val;
          if (val is String) return val.toLowerCase() == 'true';
          return false;
        }

        final enableAutoSummary = parseBool(
          settings
              .firstWhere(
                (s) => s.key == 'enable_auto_summary',
                orElse: () => const SystemSetting(key: '', value: false),
              )
              .value,
        );

        return SettingGroup(
          children: [
            SettingTile(
              title: '启用 AI 自动生成摘要',
              subtitle: '解析完成后自动调用大模型生成摘要',
              icon: Icons.summarize_rounded,
              trailing: Switch(
                value: enableAutoSummary,
                onChanged: (val) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting(
                      'enable_auto_summary',
                      val,
                      category: 'llm',
                    ),
              ),
              onTap: () => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'enable_auto_summary',
                    !enableAutoSummary,
                    category: 'llm',
                  ),
            ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildLlmSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) => SettingGroup(
        children: [
          ExpandableSettingTile(
            title: '文本大模型 (Text LLM)',
            subtitle: _getLlmSubtitle(settings, 'text'),
            icon: Icons.text_fields_rounded,
            expandedContent: _buildLlmConfigEditor(context, ref, 'text'),
          ),
          ExpandableSettingTile(
            title: '视觉大模型 (Vision LLM)',
            subtitle: _getLlmSubtitle(settings, 'vision'),
            icon: Icons.image_search_rounded,
            expandedContent: _buildLlmConfigEditor(
              context,
              ref,
              'vision',
            ),
          ),
        ],
      ),
      loading: () => const LoadingGroup(),
      error: (error, _) => const Text('加载失败'),
    );
  }

  void _showAddSourceDialog(BuildContext context, WidgetRef ref) {
    // Basic dialog implementation for adding source
    showDialog(
      context: context,
      builder: (ctx) => _SourceEditDialog(onSave: (source) {
        ref.read(discoverySourcesProvider.notifier).createSource(source);
      }),
    );
  }

  void _showEditSourceDialog(BuildContext context, WidgetRef ref, DiscoverySource source) {
    showDialog(
      context: context,
      builder: (ctx) => _SourceEditDialog(
        initialSource: source,
        onSave: (updated) {
          ref.read(discoverySourcesProvider.notifier).updateSource(
            source.id,
            name: updated.name,
            enabled: updated.enabled,
            config: updated.config,
            syncIntervalMinutes: updated.syncIntervalMinutes,
          );
        },
        onDelete: () {
          ref.read(discoverySourcesProvider.notifier).deleteSource(source.id);
        },
      ),
    );
  }


  String _maskKey(String key) {
    if (key.isEmpty) return '未配置';
    if (key.length <= 8) return '********';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  bool _isEnvConfigured(String value) => value.startsWith('***');

  String _getLlmSubtitle(List<SystemSetting> settings, String type) {
    final prefix = type == 'text' ? 'text_llm' : 'vision_llm';
    final model =
        settings
                .firstWhere(
                  (s) => s.key == '${prefix}_model',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';
    final apiKey =
        settings
                .firstWhere(
                  (s) => s.key == '${prefix}_api_key',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';

    if (model.isEmpty && apiKey.isEmpty) return '未配置';
    final keyLabel = _isEnvConfigured(apiKey) ? '密钥已配置' : _maskKey(apiKey);
    if (model.isEmpty) return keyLabel;
    return '$model • $keyLabel';
  }

  Widget _buildLlmConfigEditor(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) {
    // type: 'text' or 'vision'
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final prefix = type == 'text' ? 'text_llm' : 'vision_llm';
        final baseUrl =
            settings
                    .firstWhere(
                      (s) => s.key == '${prefix}_api_base',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final apiKey =
            settings
                    .firstWhere(
                      (s) => s.key == '${prefix}_api_key',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final model =
            settings
                    .firstWhere(
                      (s) => s.key == '${prefix}_model',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';

        final isKeyFromEnv = _isEnvConfigured(apiKey);

        final baseController = TextEditingController(text: baseUrl);
        // 环境变量配置的密钥不填入编辑框，仅提示已配置
        final keyController = TextEditingController(
          text: isKeyFromEnv ? '' : apiKey,
        );
        final modelController = TextEditingController(text: model);

        return Column(
          children: [
            TextField(
              controller: baseController,
              decoration: InputDecoration(
                labelText: 'API Base URL',
                hintText: 'e.g. https://api.openai.com/v1',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: isKeyFromEnv ? '已通过环境变量配置，输入新值可覆盖' : 'sk-...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: InputDecoration(
                labelText: 'Model Name',
                hintText: 'e.g. gpt-4o',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  await notifier.updateSetting(
                    '${prefix}_api_base',
                    baseController.text,
                    category: 'llm',
                  );
                  // 仅在用户实际输入了新密钥时才更新
                  if (keyController.text.isNotEmpty) {
                    await notifier.updateSetting(
                      '${prefix}_api_key',
                      keyController.text,
                      category: 'llm',
                    );
                  }
                  await notifier.updateSetting(
                    '${prefix}_model',
                    modelController.text,
                    category: 'llm',
                  );
                  if (context.mounted) showToast(context, 'LLM 配置已保存');
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Text('加载失败'),
    );
  }
}

class _SourceEditDialog extends StatefulWidget {
  final DiscoverySource? initialSource;
  final Function(DiscoverySource) onSave;
  final VoidCallback? onDelete;

  const _SourceEditDialog({
    this.initialSource,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_SourceEditDialog> createState() => _SourceEditDialogState();
}

class _SourceEditDialogState extends State<_SourceEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _categoryController;
  late String _kind;
  late int _interval;

  // 各来源类型的 URL 输入提示
  static const Map<String, _KindMeta> _kindMeta = {
    'rss': _KindMeta(
      label: 'RSS',
      urlLabel: 'RSS 订阅地址',
      urlHint: 'https://example.com/rss.xml',
    ),
    'telegram_channel': _KindMeta(
      label: 'Telegram 频道',
      urlLabel: 'Telegram 频道链接',
      urlHint: 'https://t.me/channelname',
    ),
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialSource?.name ?? '');
    _urlController = TextEditingController(text: widget.initialSource?.config['url'] ?? '');
    _categoryController = TextEditingController(text: widget.initialSource?.config['category'] ?? '');
    _kind = widget.initialSource?.kind ?? 'rss';
    // 若已有来源的 kind 不在支持列表中，回退到 rss
    if (!_kindMeta.containsKey(_kind)) _kind = 'rss';
    _interval = widget.initialSource?.syncIntervalMinutes ?? 60;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta[_kind]!;
    return AlertDialog(
      title: Text(widget.initialSource == null ? '添加来源' : '编辑来源'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: '来源类型'),
              items: _kindMeta.entries.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value.label),
              )).toList(),
              onChanged: (val) => setState(() => _kind = val!),
            ),
            const Gap(12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名称', hintText: '如: IT之家'),
            ),
            const Gap(12),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: meta.urlLabel,
                hintText: meta.urlHint,
              ),
            ),
            const Gap(12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: '分类标签（可选）',
                hintText: '如: 科技、新闻',
              ),
            ),
            const Gap(12),
            DropdownButtonFormField<int>(
              initialValue: _interval,
              decoration: const InputDecoration(labelText: '同步频率'),
              items: [15, 30, 60, 120, 360, 1440].map((i) => DropdownMenuItem(
                value: i,
                child: Text(i >= 60 ? '${i ~/ 60} 小时' : '$i 分钟'),
              )).toList(),
              onChanged: (val) => setState(() => _interval = val!),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              widget.onDelete!();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final url = _urlController.text.trim();
            final category = _categoryController.text.trim();
            final config = <String, dynamic>{'url': url};
            if (category.isNotEmpty) config['category'] = category;

            final source = DiscoverySource(
              id: widget.initialSource?.id ?? 0,
              kind: _kind,
              name: _nameController.text.trim(),
              enabled: widget.initialSource?.enabled ?? true,
              config: config,
              syncIntervalMinutes: _interval,
              createdAt: widget.initialSource?.createdAt ?? DateTime.now(),
            );
            widget.onSave(source);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 来源类型的元数据，用于驱动表单字段
class _KindMeta {
  final String label;
  final String urlLabel;
  final String urlHint;
  const _KindMeta({
    required this.label,
    required this.urlLabel,
    required this.urlHint,
  });
}

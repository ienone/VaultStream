import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../../utils/setting_value.dart';
import '../widgets/setting_components.dart';
import '../../../../core/network/api_client.dart';
import '../../../discovery/providers/discovery_settings_provider.dart';
import '../../../discovery/providers/discovery_sources_provider.dart';
import '../../../discovery/models/discovery_models.dart';
import '../../../../theme/design_tokens.dart';

class AutomationTab extends ConsumerWidget {
  const AutomationTab({super.key, this.sourcesOnly = false});

  final bool sourcesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: sourcesOnly
          ? [
              _buildDiscoverySources(
                context,
                ref,
                ref.watch(discoverySourcesProvider),
              ),
              const SizedBox(height: 24),
              const SectionHeader(
                title: '筛选与保留',
                icon: Icons.filter_alt_outlined,
              ),
              _buildAutomationPolicySettings(context, ref, settingsAsync),
              _buildPatrolSettings(
                context,
                ref,
                ref.watch(discoverySettingsStateProvider),
              ),
            ]
          : [
              _buildLlmSettings(
                context,
                ref,
                settingsAsync,
                ref.watch(semanticIndexStatusProvider),
              ),
              const SizedBox(height: 24),
              _buildContentGenSettings(context, ref, settingsAsync),
              ExpansionTile(
                title: const Text('能力与连通性'),
                tilePadding: EdgeInsets.zero,
                children: [
                  _buildAiCapabilitySummary(
                    context,
                    ref,
                    ref.watch(aiCapabilitiesProvider),
                  ),
                ],
              ),
            ],
    );
  }

  Widget _buildAutomationPolicySettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        final discoveryPatrolEnabled = parseBoolSetting(
          getSettingValue(settings, 'enable_discovery_patrol', true),
          true,
        );
        final aiScoringEnabled = parseBoolSetting(
          getSettingValue(settings, 'enable_ai_scoring', true),
          true,
        );
        return SettingGroup(
          children: [
            SettingTile(
              title: '发现巡逻',
              subtitle: discoveryPatrolEnabled ? '自动检查新发现的内容' : '已暂停自动检查',
              trailing: Switch(
                value: discoveryPatrolEnabled,
                onChanged: (value) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting(
                      'enable_discovery_patrol',
                      value,
                      category: 'automation',
                    ),
              ),
              showArrow: false,
            ),
            SettingTile(
              title: 'AI 评分',
              subtitle: aiScoringEnabled
                  ? '按兴趣筛选内容，并补充标签和摘要'
                  : '保留内容，不进行 AI 评分',
              trailing: Switch(
                value: aiScoringEnabled,
                onChanged: (value) => ref
                    .read(systemSettingsProvider.notifier)
                    .updateSetting(
                      'enable_ai_scoring',
                      value,
                      category: 'automation',
                    ),
              ),
              showArrow: false,
            ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) => Text('自动化策略加载失败: $error'),
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
            subtitle: settings.interestProfile.isEmpty
                ? '描述你感兴趣的内容'
                : settings.interestProfile,
            icon: Icons.face_retouching_natural_rounded,
            expandedContent: _buildInterestProfileEditor(
              context,
              ref,
              settings.interestProfile,
            ),
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
                onChanged: (val) => ref
                    .read(discoverySettingsStateProvider.notifier)
                    .updateSettings(scoreThreshold: val),
              ),
            ),
          ),
          SettingTile(
            title: '发现保留天数',
            subtitle: '${settings.retentionDays} 天后按清理策略处理；修改后只影响新候选。',
            icon: Icons.auto_delete_rounded,
            trailing: DropdownButton<int>(
              value: settings.retentionDays,
              underline: const SizedBox.shrink(),
              items: [1, 3, 7, 15, 30]
                  .map((d) => DropdownMenuItem(value: d, child: Text('$d 天')))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  ref
                      .read(discoverySettingsStateProvider.notifier)
                      .updateSettings(retentionDays: val);
                }
              },
            ),
          ),
          SettingTile(
            title: '收件箱清理策略',
            subtitle: _cleanupModeDescription(settings.cleanupMode),
            icon: Icons.inventory_2_rounded,
            trailing: DropdownButton<String>(
              value: settings.cleanupMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'hard_delete', child: Text('硬删除')),
                DropdownMenuItem(value: 'expire_only', child: Text('仅过期')),
                DropdownMenuItem(value: 'archive', child: Text('归档')),
              ],
              onChanged: (val) {
                if (val != null) {
                  ref
                      .read(discoverySettingsStateProvider.notifier)
                      .updateSettings(cleanupMode: val);
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

  String _cleanupModeDescription(String mode) {
    return switch (mode) {
      'expire_only' => '过期候选只标记为已过期，不自动删除。',
      'archive' => '过期或已忽略候选软归档隐藏，保留记录便于审计。',
      _ => '过期或已忽略候选会被清理任务硬删除。',
    };
  }

  Widget _buildInterestProfileEditor(
    BuildContext context,
    WidgetRef ref,
    String currentProfile,
  ) {
    final controller = TextEditingController(text: currentProfile);
    return Column(
      children: [
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '描述你感兴趣的领域、技术栈、博主或关键词...',
            border: const OutlineInputBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
          ),
        ),
        const Gap(12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref
                  .read(discoverySettingsStateProvider.notifier)
                  .updateSettings(interestProfile: controller.text);
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
              children: sources
                  .map((s) => _buildSourceTile(context, ref, s))
                  .toList(),
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

  Widget _buildSourceTile(
    BuildContext context,
    WidgetRef ref,
    DiscoverySource source,
  ) {
    return SettingTile(
      title: source.name,
      subtitle:
          '${source.kind.toUpperCase()} • 每 ${source.syncIntervalMinutes} 分钟同步',
      icon: _sourceIcon(source.kind),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: source.enabled,
            onChanged: (val) => ref
                .read(discoverySourcesProvider.notifier)
                .updateSource(source.id, enabled: val),
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              if (!source.enabled) {
                showToast(context, '该发现源已禁用，手动同步已按策略拒绝');
                return;
              }
              try {
                final runId = await ref
                    .read(discoverySourcesProvider.notifier)
                    .triggerSync(source.id);
                if (context.mounted) {
                  final suffix = runId == null
                      ? ''
                      : ' #${runId.length > 8 ? runId.substring(0, 8) : runId}';
                  showToast(context, '已手动触发同步$suffix');
                }
              } catch (e) {
                if (context.mounted) {
                  showToast(
                    context,
                    formatApiErrorMessage(e, fallbackMessage: '手动同步失败'),
                  );
                }
              }
            },
          ),
        ],
      ),
      onTap: () => _showEditSourceDialog(context, ref, source),
    );
  }

  IconData _sourceIcon(String kind) {
    switch (kind.toLowerCase()) {
      case 'rss':
        return Icons.rss_feed_rounded;
      case 'hackernews':
        return Icons.whatshot_rounded;
      case 'reddit':
        return Icons.forum_rounded;
      case 'telegram_channel':
        return Icons.telegram_rounded;
      default:
        return Icons.sensors_rounded;
    }
  }

  Widget _buildContentGenSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        return SettingGroup(
          children: [
            ExpandableSettingTile(
              title: '摘要模型',
              subtitle: _getSummarySubtitle(settings),
              expandedContent: _buildSummaryConfigEditor(context, ref),
            ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, stackTrace) => const Text('摘要配置读取失败，请刷新后重试'),
    );
  }

  Widget _buildLlmSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
    AsyncValue<Map<String, dynamic>> semanticStatusAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingsAsync.when(
          data: (settings) => SettingGroup(
            children: [
              ExpandableSettingTile(
                title: '文本模型',
                subtitle: _getLlmSubtitle(settings, 'text'),
                expandedContent: _buildLlmConfigEditor(context, ref, 'text'),
              ),
              ExpandableSettingTile(
                title: '视觉模型',
                subtitle: _getLlmSubtitle(settings, 'vision'),
                expandedContent: _buildLlmConfigEditor(context, ref, 'vision'),
              ),
              ExpandableSettingTile(
                title: 'Gemini Embedding',
                subtitle: _getEmbeddingSubtitle(settings),
                expandedContent: _buildEmbeddingConfigEditor(
                  context,
                  ref,
                  semanticStatusAsync,
                ),
              ),
            ],
          ),
          loading: () => const LoadingGroup(),
          error: (error, _) => const Text('加载失败'),
        ),
      ],
    );
  }

  Widget _buildAiCapabilitySummary(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> capabilitiesAsync,
  ) {
    return capabilitiesAsync.when(
      data: (capabilities) {
        final visibleCapabilities = capabilities.where((capability) {
          final key = capability['key']?.toString() ?? '';
          return key != 'semantic_search' && key != 'agent';
        }).toList();
        if (visibleCapabilities.isEmpty) {
          return const SettingGroup(
            children: [
              SettingTile(
                title: '能力状态',
                subtitle: '暂无能力状态数据',
                icon: Icons.psychology_alt_rounded,
                showArrow: false,
              ),
            ],
          );
        }
        return SettingGroup(
          children: visibleCapabilities.map((capability) {
            final key = capability['key']?.toString() ?? '';
            final status = capability['status']?.toString() ?? 'unknown';
            final summary = capability['summary']?.toString() ?? '';
            final issues = (capability['issues'] as List<dynamic>? ?? [])
                .map((item) => item.toString())
                .where((item) => item.isNotEmpty)
                .toList();
            final details = capability['details'] is Map
                ? Map<String, dynamic>.from(capability['details'] as Map)
                : <String, dynamic>{};
            final connectivity = details['connectivity'] is Map
                ? Map<String, dynamic>.from(details['connectivity'] as Map)
                : null;
            final testTarget = _aiConnectivityTarget(key, details);
            final connectivityText = _aiConnectivitySummary(connectivity);
            final subtitle = [
              issues.isEmpty ? summary : '${issues.first} · $summary',
              ?connectivityText,
            ].where((item) => item.isNotEmpty).join('\n');
            return SettingTile(
              title: capability['label']?.toString() ?? key,
              subtitle: subtitle,
              icon: _aiCapabilityIcon(key),
              iconColor: _aiCapabilityColor(context, status),
              showArrow: false,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _aiCapabilityStatusLabel(status),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: _aiCapabilityColor(context, status),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (testTarget != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '测试连通性',
                      icon: const Icon(Icons.network_check_rounded),
                      onPressed: () =>
                          _runAiConnectivityTest(context, ref, testTarget),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) => SettingGroup(
        children: [
          SettingTile(
            title: '能力状态',
            subtitle: '加载失败: $error',
            icon: Icons.error_outline_rounded,
            iconColor: Theme.of(context).colorScheme.error,
            showArrow: false,
            trailing: IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(aiCapabilitiesProvider),
            ),
          ),
        ],
      ),
    );
  }

  String? _aiConnectivityTarget(String key, Map<String, dynamic> details) {
    switch (key) {
      case 'text_llm':
        return 'text_llm';
      case 'vision_llm':
        return 'vision_llm';
      case 'content_understanding':
        if (details['text_llm'] == true) return 'text_llm';
        if (details['vision_llm'] == true) return 'vision_llm';
        return null;
      case 'summary_generation':
        return 'summary_generation';
      case 'semantic_search':
        return 'semantic_search';
      case 'agent':
        if (details['agent_chat'] == true) return 'agent_chat';
        return null;
      default:
        return null;
    }
  }

  String? _aiConnectivitySummary(Map<String, dynamic>? connectivity) {
    if (connectivity == null || connectivity.isEmpty) return null;
    final status = connectivity['status']?.toString();
    final result = connectivity['result'] is Map
        ? Map<String, dynamic>.from(connectivity['result'] as Map)
        : <String, dynamic>{};
    final elapsed = result['elapsed_ms'];
    final suffix = elapsed == null ? '' : ' · ${elapsed}ms';
    if (status == 'success') {
      return '最近测试成功$suffix';
    }
    final error = connectivity['error']?.toString();
    return error == null || error.isEmpty ? '最近测试失败' : '最近测试失败: $error';
  }

  Future<void> _runAiConnectivityTest(
    BuildContext context,
    WidgetRef ref,
    String target,
  ) async {
    try {
      final result = await ref.read(aiConnectivityTestProvider).run(target);
      final suffix = result.runId.isEmpty
          ? ''
          : ' #${result.runId.length > 8 ? result.runId.substring(0, 8) : result.runId}';
      if (context.mounted) {
        showToast(context, result.ok ? '连通性测试通过$suffix' : '连通性测试失败$suffix');
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          formatApiErrorMessage(e, fallbackMessage: '连通性测试失败'),
        );
      }
    }
  }

  IconData _aiCapabilityIcon(String key) {
    switch (key) {
      case 'text_llm':
        return Icons.text_fields_rounded;
      case 'vision_llm':
        return Icons.image_search_rounded;
      case 'discovery_patrol':
        return Icons.travel_explore_rounded;
      case 'content_understanding':
        return Icons.psychology_alt_rounded;
      case 'summary_generation':
        return Icons.summarize_rounded;
      case 'semantic_search':
        return Icons.manage_search_rounded;
      case 'agent':
        return Icons.smart_toy_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  Color _aiCapabilityColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'available':
        return colorScheme.primary;
      case 'partial':
      case 'pending':
        return colorScheme.tertiary;
      case 'disabled':
        return colorScheme.outline;
      case 'unavailable':
        return colorScheme.error;
      default:
        return colorScheme.primary;
    }
  }

  String _aiCapabilityStatusLabel(String status) {
    switch (status) {
      case 'available':
        return '可用';
      case 'partial':
        return '部分可用';
      case 'pending':
        return '待索引';
      case 'disabled':
        return '已关闭';
      case 'unavailable':
        return '不可用';
      default:
        return status;
    }
  }

  void _showAddSourceDialog(BuildContext context, WidgetRef ref) {
    // Basic dialog implementation for adding source
    showDialog(
      context: context,
      builder: (ctx) => _SourceEditDialog(
        onSave: (source) {
          ref.read(discoverySourcesProvider.notifier).createSource(source);
        },
      ),
    );
  }

  void _showEditSourceDialog(
    BuildContext context,
    WidgetRef ref,
    DiscoverySource source,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _SourceEditDialog(
        initialSource: source,
        onSave: (updated) {
          ref
              .read(discoverySourcesProvider.notifier)
              .updateSource(
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

  String _getSummarySubtitle(List<SystemSetting> settings) {
    final model =
        settings
                .firstWhere(
                  (s) => s.key == 'summary_model',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';
    final apiKey =
        settings
                .firstWhere(
                  (s) => s.key == 'summary_api_key',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';

    if (model.isEmpty && apiKey.isEmpty) return '未配置';
    final keyLabel = _isEnvConfigured(apiKey) ? '密钥已配置' : _maskKey(apiKey);
    final modelLabel = model.isEmpty ? '使用默认模型' : model;
    return '$modelLabel • $keyLabel';
  }

  String _getEmbeddingSubtitle(List<SystemSetting> settings) {
    final model =
        settings
                .firstWhere(
                  (s) => s.key == 'embedding_model',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';
    final apiKey =
        settings
                .firstWhere(
                  (s) => s.key == 'embedding_api_key',
                  orElse: () => const SystemSetting(key: '', value: ''),
                )
                .value
            as String? ??
        '';
    final dimension = parseIntSetting(
      getSettingValue(settings, 'embedding_output_dimensionality', 1536),
      1536,
    );

    if (model.isEmpty && apiKey.isEmpty) return '未配置';
    final keyLabel = _isEnvConfigured(apiKey) ? '密钥已配置' : _maskKey(apiKey);
    final modelLabel = model.isEmpty ? 'gemini-embedding-2' : model;
    return '$modelLabel • $dimension 维 • $keyLabel';
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
                  borderRadius: AppShape.cardMediaBorder,
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
                  borderRadius: AppShape.cardMediaBorder,
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
                  borderRadius: AppShape.cardMediaBorder,
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

  Widget _buildSummaryConfigEditor(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final apiKey =
            settings
                    .firstWhere(
                      (s) => s.key == 'summary_api_key',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final model =
            settings
                    .firstWhere(
                      (s) => s.key == 'summary_model',
                      orElse: () => const SystemSetting(
                        key: '',
                        value: 'gemini-3.1-flash-lite-preview',
                      ),
                    )
                    .value
                as String? ??
            'gemini-3.1-flash-lite-preview';
        final apiVersion =
            settings
                    .firstWhere(
                      (s) => s.key == 'summary_api_version',
                      orElse: () =>
                          const SystemSetting(key: '', value: 'v1beta'),
                    )
                    .value
                as String? ??
            'v1beta';

        final isKeyFromEnv = _isEnvConfigured(apiKey);
        final keyController = TextEditingController(
          text: isKeyFromEnv ? '' : apiKey,
        );
        final modelController = TextEditingController(text: model);
        final versionController = TextEditingController(text: apiVersion);

        return Column(
          children: [
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Summary API Key',
                hintText: isKeyFromEnv ? '已配置，输入新值可覆盖' : 'AIza...',
                border: OutlineInputBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: InputDecoration(
                labelText: 'Summary Model',
                hintText: 'gemini-3.1-flash-lite-preview',
                helperText: '仅用于摘要、标签和 RAG 切片生成',
                border: OutlineInputBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: versionController,
              decoration: InputDecoration(
                labelText: 'Gemini API Version',
                hintText: 'v1beta',
                border: OutlineInputBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  if (keyController.text.isNotEmpty) {
                    await notifier.updateSetting(
                      'summary_api_key',
                      keyController.text,
                      category: 'summary',
                    );
                  }
                  await notifier.updateSetting(
                    'summary_model',
                    modelController.text.trim().isEmpty
                        ? 'gemini-3.1-flash-lite-preview'
                        : modelController.text.trim(),
                    category: 'summary',
                  );
                  await notifier.updateSetting(
                    'summary_api_version',
                    versionController.text.trim().isEmpty
                        ? 'v1beta'
                        : versionController.text.trim(),
                    category: 'summary',
                  );
                  if (context.mounted) showToast(context, '摘要模型配置已保存');
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

  Widget _buildEmbeddingConfigEditor(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, dynamic>> semanticStatusAsync,
  ) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final apiKey =
            settings
                    .firstWhere(
                      (s) => s.key == 'embedding_api_key',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final model =
            settings
                    .firstWhere(
                      (s) => s.key == 'embedding_model',
                      orElse: () => const SystemSetting(
                        key: '',
                        value: 'gemini-embedding-2',
                      ),
                    )
                    .value
                as String? ??
            'gemini-embedding-2';
        final dimension = parseIntSetting(
          getSettingValue(settings, 'embedding_output_dimensionality', 1536),
          1536,
        );

        final isKeyFromEnv = _isEnvConfigured(apiKey);
        final keyController = TextEditingController(
          text: isKeyFromEnv ? '' : apiKey,
        );
        final modelController = TextEditingController(text: model);
        final dimController = TextEditingController(text: '$dimension');

        return Column(
          children: [
            _buildSemanticIndexStatusCard(context, ref, semanticStatusAsync),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Embedding API Key',
                hintText: isKeyFromEnv ? '已配置，输入新值可覆盖' : 'AIza...',
                border: OutlineInputBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: InputDecoration(
                labelText: 'Embedding Model',
                hintText: 'gemini-embedding-2',
                border: OutlineInputBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dimController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '输出维度',
                helperText: '推荐 768 / 1536 / 3072',
                border: OutlineInputBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  if (keyController.text.isNotEmpty) {
                    await notifier.updateSetting(
                      'embedding_api_key',
                      keyController.text,
                      category: 'embedding',
                    );
                  }
                  await notifier.updateSetting(
                    'embedding_model',
                    modelController.text.trim().isEmpty
                        ? 'gemini-embedding-2'
                        : modelController.text.trim(),
                    category: 'embedding',
                  );
                  final dimension =
                      int.tryParse(dimController.text.trim()) ?? 1536;
                  await notifier.updateSetting(
                    'embedding_output_dimensionality',
                    dimension,
                    category: 'embedding',
                  );
                  if (context.mounted) showToast(context, 'Embedding 配置已保存');
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

  Widget _buildSemanticIndexStatusCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, dynamic>> statusAsync,
  ) {
    final theme = Theme.of(context);
    return statusAsync.when(
      data: (status) {
        final counts = <String, int>{
          for (final item in (status['status_counts'] as List<dynamic>? ?? []))
            if (item is Map)
              item['status']?.toString() ?? 'unknown':
                  (item['count'] as num?)?.toInt() ?? 0,
        };
        final indexed = (status['indexed_total'] as num?)?.toInt() ?? 0;
        final parseSuccess =
            (status['parse_success_total'] as num?)?.toInt() ?? 0;
        final pending =
            (status['pending_total'] as num?)?.toInt() ??
            (counts['pending'] ?? 0);
        final failed =
            (status['failed_total'] as num?)?.toInt() ??
            (counts['failed'] ?? 0);
        final lastAttempt = status['last_attempt_at']?.toString();
        final failures = (status['recent_failures'] as List<dynamic>? ?? [])
            .whereType<Map>();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            borderRadius: AppShape.cardMediaBorder,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.monitor_heart_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('RAG 索引状态', style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: '刷新索引状态',
                    onPressed: () =>
                        ref.invalidate(semanticIndexStatusProvider),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusPill(label: '可检索', value: '$indexed/$parseSuccess'),
                  _StatusPill(label: '等待', value: '$pending'),
                  _StatusPill(label: '失败', value: '$failed'),
                ],
              ),
              if (lastAttempt != null && lastAttempt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('最近尝试: $lastAttempt', style: theme.textTheme.bodySmall),
              ],
              if (failures.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...failures.take(3).map((item) {
                  final title =
                      item['title']?.toString() ?? '内容 ${item['content_id']}';
                  final reason = item['failure_reason']?.toString() ?? '未知失败';
                  final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$title · 重试 $retry · $reason',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final result = await ref
                            .read(semanticIndexActionsProvider)
                            .retryFailed();
                        if (context.mounted) {
                          final runId = result.runId;
                          final suffix = runId == null
                              ? ''
                              : ' #${runId.length > 8 ? runId.substring(0, 8) : runId}';
                          showToast(context, '已调度失败索引重试$suffix');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showToast(
                            context,
                            formatApiErrorMessage(e, fallbackMessage: '索引重试失败'),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('重试失败项'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, _) => Text('RAG 状态加载失败: $error'),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppShape.cardMediaBorder,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text('$label $value', style: theme.textTheme.labelMedium),
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
    _nameController = TextEditingController(
      text: widget.initialSource?.name ?? '',
    );
    _urlController = TextEditingController(
      text: widget.initialSource?.config['url'] ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.initialSource?.config['category'] ?? '',
    );
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
    return AdaptiveTaskSurface(
      title: widget.initialSource == null ? '添加来源' : '编辑来源',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '来源类型'),
            items: _kindMeta.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value.label),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _kind = val!),
          ),
          const Gap(12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '如: IT之家',
            ),
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
            items: [15, 30, 60, 120, 360, 1440]
                .map(
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text(i >= 60 ? '${i ~/ 60} 小时' : '$i 分钟'),
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _interval = val!),
          ),
        ],
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              widget.onDelete!();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
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

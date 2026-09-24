import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../../utils/setting_value.dart';
import '../widgets/setting_components.dart';
import '../widgets/settings_editor_draft.dart';
import '../widgets/settings_slider.dart';
import '../../../../core/network/api_client.dart';
import '../../../discovery/providers/discovery_settings_provider.dart';
import '../../../discovery/providers/discovery_sources_provider.dart';
import '../../../discovery/models/discovery_models.dart';
import '../../../../theme/design_tokens.dart';
import '../../../../core/widgets/adaptive_form_dialog.dart';
import '../../../../core/widgets/app_filter_menu.dart';

class AutomationTab extends ConsumerWidget {
  const AutomationTab({super.key, this.sourcesOnly = false});

  final bool sourcesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final content = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: sourcesOnly
          ? [
              _buildDiscoverySources(
                context,
                ref,
                ref.watch(discoverySourcesProvider),
              ),
              const SizedBox(height: 8),
              const SectionHeader(title: '筛选与保留'),
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
              _buildContentGenSettings(context, ref, settingsAsync),
              const SizedBox(height: 24),
              ExpandableSettingTile(
                title: '能力与连通性',
                expandedContent: _buildAiCapabilitySummary(
                  context,
                  ref,
                  ref.watch(aiCapabilitiesProvider),
                ),
              ),
            ],
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
        child: content,
      ),
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
        return Column(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              shape: const RoundedRectangleBorder(
                borderRadius: AppShape.cardMediaBorder,
              ),
              title: const Text('发现巡逻'),
              subtitle: Text(discoveryPatrolEnabled ? '自动检查新发现的内容' : '已暂停自动检查'),
              value: discoveryPatrolEnabled,
              onChanged: (value) => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'enable_discovery_patrol',
                    value,
                    category: 'automation',
                  ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              shape: const RoundedRectangleBorder(
                borderRadius: AppShape.cardMediaBorder,
              ),
              title: const Text('AI 评分'),
              subtitle: Text(
                aiScoringEnabled ? '按兴趣筛选内容，并补充标签和摘要' : '保留内容，不进行 AI 评分',
              ),
              value: aiScoringEnabled,
              onChanged: (value) => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'enable_ai_scoring',
                    value,
                    category: 'automation',
                  ),
            ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) =>
          Text(formatApiErrorMessage(error, fallbackMessage: '自动化策略加载失败')),
    );
  }

  Widget _buildPatrolSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DiscoverySettings> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpandableSettingTile(
            title: '兴趣偏好',
            subtitle: '描述你感兴趣的领域与内容',
            expandedContent: _buildInterestProfileEditor(
              context,
              ref,
              settings.interestProfile,
            ),
          ),
          const Gap(16),
          SettingsSlider(
            title: 'AI 评分阈值',
            min: 0,
            max: 10,
            divisions: 20,
            formatValue: (value) => value.toStringAsFixed(1),
            errorMessage: '评分阈值保存失败',
            value: settings.scoreThreshold,
            onSaved: (value) => ref
                .read(discoverySettingsStateProvider.notifier)
                .updateSettings(scoreThreshold: value),
          ),
          const Gap(24),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final width = constraints.maxWidth >= 600 * scale
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              final days = {1, 3, 7, 15, 30, settings.retentionDays}.toList()
                ..sort();
              return Wrap(
                spacing: 16,
                runSpacing: 24,
                children: [
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppFilterMenu(
                          label: '候选保留时间',
                          value: '${settings.retentionDays}',
                          options: {for (final day in days) '$day': '$day 天'},
                          onOpened: () => FocusScope.of(context).unfocus(),
                          onSelected: (value) => ref
                              .read(discoverySettingsStateProvider.notifier)
                              .updateSettings(retentionDays: int.parse(value)),
                        ),
                        const Gap(8),
                        Text(
                          '到期后按所选方式处理；修改仅影响新候选。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppFilterMenu(
                          label: '清理方式',
                          value: settings.cleanupMode,
                          options: const {
                            'hard_delete': '删除',
                            'expire_only': '仅标记过期',
                            'archive': '归档',
                          },
                          onOpened: () => FocusScope.of(context).unfocus(),
                          onSelected: (value) => ref
                              .read(discoverySettingsStateProvider.notifier)
                              .updateSettings(cleanupMode: value),
                        ),
                        const Gap(8),
                        Text(
                          _cleanupModeDescription(settings.cleanupMode),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
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
      'archive' => '隐藏过期或已忽略的候选，并保留记录。',
      _ => '过期或已忽略的候选将被永久删除。',
    };
  }

  Widget _buildInterestProfileEditor(
    BuildContext context,
    WidgetRef ref,
    String currentProfile,
  ) {
    return SettingsEditorDraft(
      initialValues: {'profile': currentProfile},
      builder: (context, controllers) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '兴趣偏好',
            child: TextField(
              controller: controllers['profile'],
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: '感兴趣的主题、作者或关键词'),
            ),
          ),
          const Gap(12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () async {
                try {
                  await ref
                      .read(discoverySettingsStateProvider.notifier)
                      .updateSettings(
                        interestProfile: controllers['profile']!.text,
                      );
                  if (context.mounted) showToast(context, '兴趣偏好已更新');
                } catch (error) {
                  if (context.mounted) {
                    showToast(
                      context,
                      formatApiErrorMessage(error, fallbackMessage: '兴趣偏好保存失败'),
                    );
                  }
                }
              },
              child: const Text('保存偏好'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverySources(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<DiscoverySource>> sourcesAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '发现来源',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showAddSourceDialog(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加'),
            ),
          ],
        ),
        const Gap(8),
        sourcesAsync.when(
          data: (sources) => sources.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('还没有发现来源'),
                )
              : Column(
                  children: [
                    for (final source in sources)
                      _buildSourceTile(context, ref, source),
                  ],
                ),
          loading: () => const LoadingGroup(),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatApiErrorMessage(
                  error,
                  fallbackMessage: '暂时无法读取来源列表',
                  includeRequestId: false,
                ),
              ),
              TextButton.icon(
                onPressed: () => ref.invalidate(discoverySourcesProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceTile(
    BuildContext context,
    WidgetRef ref,
    DiscoverySource source,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            shape: const RoundedRectangleBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            title: Text(source.name),
            subtitle: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(source.kind == 'rss' ? 'RSS' : 'Telegram 频道'),
                Text('每 ${_sourceIntervalLabel(source.syncIntervalMinutes)}同步'),
              ],
            ),
            trailing: const Icon(Icons.edit_outlined, size: 20),
            onTap: () => _showEditSourceDialog(context, ref, source),
          ),
          Wrap(
            spacing: 20,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('启用'),
                  const Gap(8),
                  Semantics(
                    label: '启用${source.name}',
                    child: Switch(
                      value: source.enabled,
                      onChanged: (value) => ref
                          .read(discoverySourcesProvider.notifier)
                          .updateSource(source.id, enabled: value),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.sync_rounded),
                label: const Text('立即同步'),
                onPressed: !source.enabled
                    ? null
                    : () async {
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
                              formatApiErrorMessage(
                                e,
                                fallbackMessage: '手动同步失败',
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContentGenSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        return ExpandableSettingTile(
          title: '摘要模型',
          subtitle: _getSummarySubtitle(settings),
          expandedContent: _buildSummaryConfigEditor(context, ref),
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
          data: (settings) => Column(
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
                title: '向量模型',
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
    final theme = Theme.of(context);
    return capabilitiesAsync.when(
      data: (capabilities) {
        final visibleCapabilities = capabilities.where((capability) {
          final key = capability['key']?.toString() ?? '';
          return key != 'semantic_search' && key != 'agent';
        }).toList();
        if (visibleCapabilities.isEmpty) {
          return const Text('暂无能力状态数据');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        capability['label']?.toString() ?? key,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _aiCapabilityStatusLabel(status),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _aiCapabilityColor(context, status),
                        ),
                      ),
                    ],
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(summary, style: theme.textTheme.bodyMedium),
                  ],
                  if (issues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      issues.first,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _aiCapabilityColor(context, status),
                      ),
                    ),
                  ],
                  if (connectivityText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      connectivityText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (testTarget != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.network_check_rounded),
                        label: const Text('测试连通性'),
                        onPressed: () =>
                            _runAiConnectivityTest(context, ref, testTarget),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatApiErrorMessage(
              error,
              fallbackMessage: '暂时无法读取能力状态，请稍后重试',
              includeRequestId: false,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              label: const Text('重新加载'),
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
    showDialog(
      context: context,
      builder: (ctx) => _SourceEditDialog(
        onSave: (source) =>
            ref.read(discoverySourcesProvider.notifier).createSource(source),
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
        onSave: (updated) => ref
            .read(discoverySourcesProvider.notifier)
            .updateSource(
              source.id,
              name: updated.name,
              enabled: updated.enabled,
              config: updated.config,
              syncIntervalMinutes: updated.syncIntervalMinutes,
            ),
        onDelete: () =>
            ref.read(discoverySourcesProvider.notifier).deleteSource(source.id),
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

        return SettingsEditorDraft(
          initialValues: {
            'base': baseUrl,
            'key': isKeyFromEnv ? '' : apiKey,
            'model': model,
          },
          builder: (context, controllers) {
            final baseController = controllers['base']!;
            final keyController = controllers['key']!;
            final modelController = controllers['model']!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsField(
                  controller: baseController,
                  label: 'API 地址',
                  hint: 'https://api.example.com/v1',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                _SettingsField(
                  controller: keyController,
                  label: 'API 密钥',
                  obscureText: true,
                  description: isKeyFromEnv ? '已通过环境变量配置；仅在更换密钥时输入。' : null,
                ),
                const SizedBox(height: 12),
                _SettingsField(controller: modelController, label: '模型名称'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final notifier = ref.read(
                        systemSettingsProvider.notifier,
                      );
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
        return SettingsEditorDraft(
          initialValues: {
            'key': isKeyFromEnv ? '' : apiKey,
            'model': model,
            'version': apiVersion,
          },
          builder: (context, controllers) {
            final keyController = controllers['key']!;
            final modelController = controllers['model']!;
            final versionController = controllers['version']!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsField(
                  controller: keyController,
                  label: 'API 密钥',
                  obscureText: true,
                  description: isKeyFromEnv ? '已通过环境变量配置；仅在更换密钥时输入。' : null,
                ),
                const SizedBox(height: 12),
                _SettingsField(
                  controller: modelController,
                  label: '模型名称',
                  description: '用于摘要、标签和 RAG 切片生成。',
                ),
                const SizedBox(height: 12),
                _SettingsField(controller: versionController, label: 'API 版本'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final notifier = ref.read(
                        systemSettingsProvider.notifier,
                      );
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
        return SettingsEditorDraft(
          initialValues: {
            'key': isKeyFromEnv ? '' : apiKey,
            'model': model,
            'dimension': '$dimension',
          },
          builder: (context, controllers) {
            final keyController = controllers['key']!;
            final modelController = controllers['model']!;
            final dimController = controllers['dimension']!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsField(
                  controller: keyController,
                  label: 'API 密钥',
                  obscureText: true,
                  description: isKeyFromEnv ? '已通过环境变量配置；仅在更换密钥时输入。' : null,
                ),
                const SizedBox(height: 12),
                _SettingsField(controller: modelController, label: '模型名称'),
                const SizedBox(height: 12),
                _SettingsField(
                  controller: dimController,
                  label: '输出维度',
                  description: '推荐 768 / 1536 / 3072',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final notifier = ref.read(
                        systemSettingsProvider.notifier,
                      );
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
                      if (context.mounted) {
                        showToast(context, 'Embedding 配置已保存');
                      }
                    },
                    child: const Text('保存配置'),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSemanticIndexStatus(context, ref, semanticStatusAsync),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Text('加载失败'),
    );
  }

  Widget _buildSemanticIndexStatus(
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
        final lastAttempt = DateTime.tryParse(
          status['last_attempt_at']?.toString() ?? '',
        );
        final failures = (status['recent_failures'] as List<dynamic>? ?? [])
            .whereType<Map>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('索引状态', style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: '刷新索引状态',
                  onPressed: () => ref.invalidate(semanticIndexStatusProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text(
                  '可检索 $indexed / $parseSuccess',
                  style: theme.textTheme.bodyMedium,
                ),
                Text('等待 $pending', style: theme.textTheme.bodyMedium),
                Text(
                  '失败 $failed',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: failed > 0 ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
            if (lastAttempt != null) ...[
              const SizedBox(height: 8),
              Text(
                '最近尝试：${DateFormat('yyyy-MM-dd HH:mm').format(lastAttempt.toLocal())}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('最近失败', style: theme.textTheme.titleSmall),
              ...failures.take(3).map((item) {
                final title =
                    item['title']?.toString() ?? '内容 ${item['content_id']}';
                final reason = item['failure_reason']?.toString() ?? '未知失败';
                final retry = (item['retry_count'] as num?)?.toInt() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已重试 $retry 次',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
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
        );
      },
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatApiErrorMessage(
              error,
              fallbackMessage: '暂时无法读取索引状态，请稍后重试',
              includeRequestId: false,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref.invalidate(semanticIndexStatusProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载索引状态'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceEditDialog extends StatefulWidget {
  final DiscoverySource? initialSource;
  final Future<void> Function(DiscoverySource) onSave;
  final Future<void> Function()? onDelete;

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
  String? _pendingAction;
  String? _error;

  bool get _busy => _pendingAction != null;

  Future<void> _runAction(String action, Future<void> Function() submit) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _pendingAction = action;
      _error = null;
    });
    try {
      await submit();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingAction = null;
        _error = formatApiErrorMessage(
          error,
          fallbackMessage: action == 'delete' ? '来源删除失败，请稍后重试' : '来源保存失败，请稍后重试',
          includeRequestId: false,
        );
      });
    }
  }

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
    final intervals = {15, 30, 60, 120, 360, 1440, _interval}.toList()..sort();
    return PopScope(
      canPop: !_busy,
      child: AdaptiveFormDialog(
        title: widget.initialSource == null ? '添加来源' : '编辑来源',
        contentBuilder: (context, width, short) => AbsorbPointer(
          absorbing: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.initialSource == null)
                AppFilterMenu(
                  label: '来源类型',
                  value: _kind,
                  options: {
                    for (final entry in _kindMeta.entries)
                      entry.key: entry.value.label,
                  },
                  onOpened: () => FocusScope.of(context).unfocus(),
                  onSelected: (value) => setState(() => _kind = value),
                )
              else
                Text(
                  '来源类型：${meta.label}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const Gap(16),
              _SettingsField(
                controller: _nameController,
                label: '名称',
                hint: '如：IT之家',
              ),
              const Gap(16),
              _SettingsField(
                controller: _urlController,
                label: meta.urlLabel,
                hint: meta.urlHint,
                keyboardType: TextInputType.url,
              ),
              const Gap(16),
              _SettingsField(
                controller: _categoryController,
                label: '分类标签（可选）',
                hint: '如：科技、新闻',
              ),
              const Gap(16),
              AppFilterMenu(
                label: '同步频率',
                value: '$_interval',
                options: {
                  for (final minutes in intervals)
                    '$minutes': _sourceIntervalLabel(minutes),
                },
                onOpened: () => FocusScope.of(context).unfocus(),
                onSelected: (value) =>
                    setState(() => _interval = int.parse(value)),
              ),
              if (_error != null) ...[
                const Gap(16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 12,
          overflowSpacing: 8,
          children: [
            if (widget.onDelete != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _runAction('delete', widget.onDelete!),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(_pendingAction == 'delete' ? '删除中…' : '删除'),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
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
                        createdAt:
                            widget.initialSource?.createdAt ?? DateTime.now(),
                      );
                      _runAction('save', () => widget.onSave(source));
                    },
              child: Text(_pendingAction == 'save' ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
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

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    this.description,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? description;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodyLarge),
      if (description != null) ...[
        const SizedBox(height: 4),
        Text(
          description!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 8),
      Semantics(
        label: label,
        child: TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: hint),
        ),
      ),
    ],
  );
}

String _sourceIntervalLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60} 小时' : '$minutes 分钟';

import '../../../../core/layout/app_page_body.dart';

import 'package:material_ui/material_ui.dart';

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
import '../../../discovery/models/discovery_models.dart';
import '../../../../core/widgets/app_filter_menu.dart';

enum AutomationView { models, policy }

class AutomationTab extends ConsumerStatefulWidget {
  const AutomationTab({super.key, this.view = AutomationView.models});

  final AutomationView view;

  @override
  ConsumerState<AutomationTab> createState() => _AutomationTabState();
}

class _AutomationTabState extends ConsumerState<AutomationTab> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final content = widget.view == AutomationView.policy
        ? ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildAutomationPolicySettings(context, ref, settingsAsync),
              const SizedBox(height: 24),
              _buildPatrolSettings(
                context,
                ref,
                ref.watch(discoverySettingsStateProvider),
              ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildLlmSettings(
                context,
                ref,
                settingsAsync,
                ref.watch(semanticIndexStatusProvider),
              ),
            ],
          );
    return AppPageBody(child: content);
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
            SettingSwitch(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              shape: const RoundedRectangleBorder(),
              title: const Text('自动检查新内容'),
              value: discoveryPatrolEnabled,
              onChanged: (value) => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'enable_discovery_patrol',
                    value,
                    category: 'automation',
                  ),
            ),
            SettingSwitch(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              shape: const RoundedRectangleBorder(),
              title: const Text('AI 评分'),
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
      error: (error, _) => SettingLoadFailure(
        onRetry: () => ref.invalidate(systemSettingsProvider),
      ),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: _buildInterestProfileEditor(
              context,
              ref,
              settings.interestProfile,
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: SettingsSlider(
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
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: AppFilterMenuRow(
              menus: [
                AppFilterMenu(
                  label: '候选保留时间',
                  value: '${settings.retentionDays}',
                  options: {
                    for (final day in ({
                      1,
                      3,
                      7,
                      15,
                      30,
                      settings.retentionDays,
                    }.toList()..sort()))
                      '$day': '$day 天',
                  },
                  onOpened: () => FocusScope.of(context).unfocus(),
                  onSelected: (value) => ref
                      .read(discoverySettingsStateProvider.notifier)
                      .updateSettings(retentionDays: int.parse(value)),
                ),
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
              ],
            ),
          ),
        ],
      ),
      loading: () => const LoadingGroup(),
      error: (error, _) => SettingLoadFailure(
        onRetry: () => ref.invalidate(discoverySettingsStateProvider),
      ),
    );
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
              decoration: const InputDecoration(
                labelText: '兴趣偏好',
                hintText: '感兴趣的主题、作者或关键词',
              ),
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

  Widget _buildLlmSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
    AsyncValue<Map<String, dynamic>> semanticStatusAsync,
  ) => settingsAsync.when(
    data: (settings) => SettingGroup(
      children: [
        SettingSection(
          title: '通用模型',
          child: _buildModelConfigEditor(context, ref, 'text_llm'),
        ),
        SettingSection(
          title: '向量模型',
          child: _buildModelConfigEditor(
            context,
            ref,
            'embedding',
            footer: _buildSemanticIndexStatus(
              context,
              ref,
              semanticStatusAsync,
            ),
          ),
        ),
        SettingSection(
          title: '摘要模型',
          child: _buildModelConfigEditor(context, ref, 'summary'),
        ),
      ],
    ),
    loading: () => const LoadingGroup(),
    error: (error, _) => SettingLoadFailure(
      onRetry: () => ref.invalidate(systemSettingsProvider),
    ),
  );

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

  bool _isEnvConfigured(String value) => value.startsWith('***');

  Widget _buildModelConfigEditor(
    BuildContext context,
    WidgetRef ref,
    String target, {
    Widget? footer,
  }) {
    final defaults = switch (target) {
      'text_llm' => {'api_base': '', 'api_key': '', 'model': ''},
      'summary' => {
        'api_key': '',
        'model': 'gemini-3.1-flash-lite-preview',
        'api_version': 'v1beta',
      },
      'embedding' => {
        'api_key': '',
        'model': 'gemini-embedding-2',
        'output_dimensionality': '1536',
      },
      _ => throw ArgumentError.value(target),
    };
    const labels = {
      'api_base': 'API 地址',
      'api_key': 'API 密钥',
      'model': '模型名称',
      'api_version': 'API 版本',
      'output_dimensionality': '输出维度',
    };
    return ref
        .watch(systemSettingsProvider)
        .when(
          data: (settings) {
            final values = {
              for (final entry in defaults.entries)
                entry.key:
                    (getSettingValue(
                              settings,
                              '${target}_${entry.key}',
                              entry.value,
                            ) ??
                            entry.value)
                        .toString(),
            };
            final hasSavedKey = _isEnvConfigured(values['api_key']!);
            if (hasSavedKey) values['api_key'] = '';
            return SettingsEditorDraft(
              key: ValueKey(target),
              initialValues: values,
              builder: (context, controllers) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final field in defaults.keys) ...[
                    _SettingsField(
                      controller: controllers[field]!,
                      label: labels[field]!,
                      obscureText: field == 'api_key',
                      hint: field == 'api_base'
                          ? 'https://api.example.com/v1'
                          : null,
                      keyboardType: field == 'api_base'
                          ? TextInputType.url
                          : field == 'output_dimensionality'
                          ? TextInputType.number
                          : null,
                      description: field == 'api_key' && hasSavedKey
                          ? '留空保留原密钥'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.network_check_rounded),
                        label: const Text('测试连接'),
                        onPressed: () => _runAiConnectivityTest(
                          context,
                          ref,
                          switch (target) {
                            'embedding' => 'semantic_search',
                            'summary' => 'summary_generation',
                            _ => 'text_llm',
                          },
                        ),
                      ),
                      _ModelSaveButton(
                        onSave: () async {
                          final updates = <String, dynamic>{};
                          for (final field in defaults.keys) {
                            final text = controllers[field]!.text.trim();
                            if (field == 'api_key' && text.isEmpty) continue;
                            if (field == 'output_dimensionality') {
                              final dimension = int.tryParse(text);
                              if (dimension == null ||
                                  dimension < 128 ||
                                  dimension > 3072) {
                                showToast(context, '输出维度须为 128–3072 的整数');
                                return;
                              }
                              updates[field] = dimension;
                            } else {
                              updates[field] = text.isEmpty
                                  ? defaults[field]!
                                  : text;
                            }
                          }
                          final notifier = ref.read(
                            systemSettingsProvider.notifier,
                          );
                          for (final entry in updates.entries) {
                            await notifier.updateSetting(
                              '${target}_${entry.key}',
                              entry.value,
                              category: target == 'text_llm' ? 'llm' : target,
                            );
                          }
                          if (context.mounted) showToast(context, '模型配置已保存');
                        },
                      ),
                    ],
                  ),
                  if (footer != null) ...[const SizedBox(height: 24), footer],
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => SettingLoadFailure(
            onRetry: () => ref.invalidate(systemSettingsProvider),
          ),
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
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

class _ModelSaveButton extends StatefulWidget {
  const _ModelSaveButton({required this.onSave});

  final Future<void> Function() onSave;

  @override
  State<_ModelSaveButton> createState() => _ModelSaveButtonState();
}

class _ModelSaveButtonState extends State<_ModelSaveButton> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          formatApiErrorMessage(error, fallbackMessage: '配置保存失败，请重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: _saving ? null : _save,
    icon: _saving
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.save_outlined),
    label: Text(_saving ? '保存中…' : '保存配置'),
  );
}

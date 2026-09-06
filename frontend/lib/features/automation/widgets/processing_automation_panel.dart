import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../theme/design_tokens.dart';
import '../../dashboard/models/stats.dart';
import '../../dashboard/providers/dashboard_provider.dart' as dashboard;
import '../../settings/models/system_setting.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/utils/setting_value.dart';

class ProcessingAutomationPanel extends ConsumerWidget {
  const ProcessingAutomationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(dashboard.queueStatsProvider);
    final diagnostics = ref.watch(dashboard.backgroundTaskDiagnosticsProvider);
    final settings = ref.watch(systemSettingsProvider);
    final semantic = ref.watch(semanticIndexStatusProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboard.queueStatsProvider);
        ref.invalidate(dashboard.backgroundTaskDiagnosticsProvider);
        ref.invalidate(systemSettingsProvider);
        ref.invalidate(semanticIndexStatusProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = _buildStages(
                ref: ref,
                queueState: queue,
                diagnostics: diagnostics.value,
                settingsState: settings,
                semanticState: semantic,
              );
              final twoColumns = ResponsiveLayout.widthClassFor(
                constraints.maxWidth,
              ).supportsSupportingPane;
              if (!twoColumns) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: (constraints.maxWidth - AppSpacing.sm) / 2,
                      child: card,
                    ),
                ],
              );
            },
          ),
          if (queue.hasError ||
              diagnostics.hasError ||
              settings.hasError ||
              semantic.hasError) ...[
            const SizedBox(height: AppSpacing.sm),
            _LoadWarning(
              onRetry: () {
                ref.invalidate(dashboard.queueStatsProvider);
                ref.invalidate(dashboard.backgroundTaskDiagnosticsProvider);
                ref.invalidate(systemSettingsProvider);
                ref.invalidate(semanticIndexStatusProvider);
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildStages({
    required WidgetRef ref,
    required AsyncValue<QueueOverviewStats> queueState,
    required BackgroundTaskDiagnostics? diagnostics,
    required AsyncValue<List<SystemSetting>> settingsState,
    required AsyncValue<Map<String, dynamic>> semanticState,
  }) {
    final queue = queueState.value;
    final settings = settingsState.value;
    final semantic = semanticState.value;
    final parseEnabled = _boolSetting(settings, 'enable_parse_worker', true);
    final archiveEnabled = _boolSetting(
      settings,
      'enable_archive_media_processing',
      true,
    );
    final archiveImages = _boolSetting(
      settings,
      'enable_archive_image_processing',
      true,
    );
    final archiveVideos = _boolSetting(
      settings,
      'enable_archive_video_processing',
      true,
    );
    final summaryEnabled = _boolSetting(settings, 'enable_auto_summary', false);
    final semanticEnabled = _boolSetting(
      settings,
      'enable_auto_semantic_indexing',
      true,
    );
    final parse = queue?.parse;
    final parseRun = _latestRun(diagnostics, const {
      'content_parse',
      'content_reparse',
    });
    final summaryRun = _latestRun(diagnostics, const {'content_summary'});
    final semanticRun = _latestRun(diagnostics, const {
      'content_embedding',
      'semantic_reindex',
    });
    final settingsReady = settings != null;
    final indexed = (semantic?['indexed_total'] as num?)?.toInt() ?? 0;
    final pending = (semantic?['pending_total'] as num?)?.toInt() ?? 0;

    return [
      _ProcessingStageSection(
        title: '解析',
        policyEnabled: settingsReady ? parseEnabled : null,
        onPolicyChanged: (value) => ref
            .read(systemSettingsProvider.notifier)
            .updateSetting(
              'enable_parse_worker',
              value,
              category: 'automation',
            ),
        icon: Icons.account_tree_rounded,
        tone: queueState.hasError || settingsState.hasError
            ? _StageTone.warning
            : !settingsReady || parse == null
            ? _StageTone.loading
            : !parseEnabled
            ? _StageTone.inactive
            : parse.parseFailed > 0
            ? _StageTone.warning
            : parse.processing > 0
            ? _StageTone.running
            : _StageTone.ok,
        status: queueState.hasError
            ? '解析状态读取失败'
            : settingsState.hasError
            ? '解析策略读取失败'
            : !parseEnabled
            ? '已暂停领取，新内容继续排队'
            : parse == null
            ? '正在读取解析状态'
            : '${parse.processing} 处理中 · ${parse.unprocessed} 待处理 · ${parse.parseFailed} 失败',
        latestRun: parseRun,
        failures: diagnostics?.failedParseTasks ?? const [],
      ),
      _ProcessingStageSection(
        title: '媒体归档',
        icon: Icons.perm_media_rounded,
        tone: settingsState.hasError
            ? _StageTone.warning
            : !settingsReady
            ? _StageTone.loading
            : archiveEnabled && (archiveImages || archiveVideos)
            ? _StageTone.ok
            : _StageTone.inactive,
        status: settingsState.hasError
            ? '媒体归档策略读取失败'
            : !settingsReady
            ? '正在读取媒体归档策略'
            : !archiveEnabled
            ? '已关闭，不下载远程媒体'
            : '随解析归档${archiveImages ? '图片' : ''}${archiveImages && archiveVideos ? '和' : ''}${archiveVideos ? '视频' : ''}${!archiveImages && !archiveVideos ? '（子项均关闭）' : ''}',
        settingsPath: '/settings?tab=storage',
        settingsLabel: '媒体归档设置',
      ),
      _ProcessingStageSection(
        title: '自动摘要',
        policyEnabled: settingsReady ? summaryEnabled : null,
        onPolicyChanged: (value) => ref
            .read(systemSettingsProvider.notifier)
            .updateSetting('enable_auto_summary', value, category: 'llm'),
        icon: Icons.summarize_rounded,
        tone: settingsState.hasError
            ? _StageTone.warning
            : !settingsReady
            ? _StageTone.loading
            : summaryEnabled
            ? _toneForRun(summaryRun)
            : _StageTone.inactive,
        status: settingsState.hasError
            ? '摘要策略读取失败'
            : !settingsReady
            ? '正在读取内容理解策略'
            : summaryEnabled
            ? '解析后自动生成摘要'
            : '仅在内容详情手动生成摘要',
        latestRun: summaryRun,
        settingsPath: '/settings?tab=automation',
        settingsLabel: '模型配置',
      ),
      _ProcessingStageSection(
        title: '全文 / 语义索引',
        policyEnabled: settingsReady ? semanticEnabled : null,
        onPolicyChanged: (value) => ref
            .read(systemSettingsProvider.notifier)
            .updateSetting(
              'enable_auto_semantic_indexing',
              value,
              category: 'automation',
            ),
        icon: Icons.manage_search_rounded,
        tone: semanticState.hasError || settingsState.hasError
            ? _StageTone.warning
            : !settingsReady || semantic == null
            ? _StageTone.loading
            : !semanticEnabled
            ? _StageTone.inactive
            : _toneForRun(semanticRun),
        status: semanticState.hasError
            ? '语义索引状态读取失败'
            : settingsState.hasError
            ? '自动索引策略读取失败'
            : semantic == null
            ? '全文检索可用；正在读取语义索引状态'
            : '全文检索可用 · 语义已索引 $indexed · 待索引 $pending${semanticEnabled ? '' : ' · 自动索引已关闭'}',
        latestRun: semanticRun,
        settingsPath: '/settings?tab=automation',
        settingsLabel: '模型配置',
      ),
    ];
  }
}

class _ProcessingStageSection extends StatelessWidget {
  const _ProcessingStageSection({
    required this.title,
    required this.icon,
    required this.tone,
    required this.status,
    this.settingsPath,
    this.settingsLabel,
    this.policyEnabled,
    this.onPolicyChanged,
    this.latestRun,
    this.failures = const [],
  });

  final String title;
  final IconData icon;
  final _StageTone tone;
  final String status;
  final String? settingsPath;
  final String? settingsLabel;
  final bool? policyEnabled;
  final ValueChanged<bool>? onPolicyChanged;
  final BackgroundTaskRun? latestRun;
  final List<FailedParseTask> failures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toneColor = _toneColor(cs, tone);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: toneColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onPolicyChanged != null)
                Semantics(
                  label: title,
                  child: Switch.adaptive(
                    value: policyEnabled ?? false,
                    onChanged: policyEnabled == null ? null : onPolicyChanged,
                  ),
                )
              else
                _StageBadge(tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(status, style: theme.textTheme.bodyMedium),
          if (failures.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final failure in failures.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.error_outline_rounded, color: cs.error),
                title: Text('内容 #${failure.contentId ?? failure.id}'),
                subtitle: Text(
                  '解析未完成，打开内容查看原因或重新解析',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: failure.contentId == null
                    ? null
                    : const Icon(Icons.chevron_right_rounded),
                onTap: failure.contentId == null
                    ? null
                    : () => context.push('/collection/${failure.contentId}'),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (settingsPath != null)
                OutlinedButton.icon(
                  onPressed: () => context.push(settingsPath!),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(settingsLabel!),
                ),
              if (latestRun != null && latestRun!.runId.isNotEmpty)
                TextButton.icon(
                  onPressed: () => context.push('/tasks/${latestRun!.runId}'),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text('最近运行'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.tone});

  final _StageTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _toneColor(cs, tone);
    final label = switch (tone) {
      _StageTone.ok => '已启用',
      _StageTone.running => '运行中',
      _StageTone.warning => '需处理',
      _StageTone.inactive => '未启用',
      _StageTone.loading => '读取中',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppShape.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _LoadWarning extends StatelessWidget {
  const _LoadWarning({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: AppShape.cardBorder,
      child: ListTile(
        leading: const Icon(Icons.sync_problem_rounded),
        title: const Text('部分阶段状态暂时不可用'),
        subtitle: const Text('已保留其余可用状态，可单独重试读取。'),
        trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
      ),
    );
  }
}

enum _StageTone { ok, running, warning, inactive, loading }

_StageTone _toneForRun(BackgroundTaskRun? run) {
  return switch (run?.status) {
    'error' => _StageTone.warning,
    'running' || 'pending' => _StageTone.running,
    _ => _StageTone.ok,
  };
}

Color _toneColor(ColorScheme colors, _StageTone tone) {
  return switch (tone) {
    _StageTone.ok => colors.primary,
    _StageTone.running => colors.tertiary,
    _StageTone.warning => colors.error,
    _StageTone.inactive => colors.outline,
    _StageTone.loading => colors.outline,
  };
}

BackgroundTaskRun? _latestRun(
  BackgroundTaskDiagnostics? diagnostics,
  Set<String> tasks,
) {
  if (diagnostics == null) return null;
  for (final run in diagnostics.recentTaskRuns) {
    if (tasks.contains(run.task)) return run;
  }
  return null;
}

bool _boolSetting(List<SystemSetting>? settings, String key, bool fallback) {
  if (settings == null) return fallback;
  return parseBoolSetting(getSettingValue(settings, key, fallback), fallback);
}

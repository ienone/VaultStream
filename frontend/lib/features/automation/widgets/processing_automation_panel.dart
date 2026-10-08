import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              ..._buildStages(
                ref: ref,
                queueState: queue,
                diagnostics: diagnostics.value,
                settingsState: settings,
                semanticState: semantic,
              ),
              if (queue.hasError ||
                  diagnostics.hasError ||
                  settings.hasError ||
                  semantic.hasError)
                _LoadWarning(
                  onRetry: () {
                    ref.invalidate(dashboard.queueStatsProvider);
                    ref.invalidate(dashboard.backgroundTaskDiagnosticsProvider);
                    ref.invalidate(systemSettingsProvider);
                    ref.invalidate(semanticIndexStatusProvider);
                  },
                ),
            ],
          ),
        ),
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
    final aggregationEnabled = _boolSetting(
      settings,
      'enable_content_aggregation',
      false,
    );
    final aggregationPushEnabled = _boolSetting(
      settings,
      'enable_aggregation_push',
      false,
    );
    final aggregationRun = _latestRun(diagnostics, const {
      'content_aggregation',
    });
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
      const _StageGroupHeading(title: '保存与归档'),
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
            ? '已暂停'
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
            ? '已关闭'
            : '随解析归档${archiveImages ? '图片' : ''}${archiveImages && archiveVideos ? '和' : ''}${archiveVideos ? '视频' : ''}${!archiveImages && !archiveVideos ? '（子项均关闭）' : ''}',
        settingsPath: '/settings?tab=storage',
        settingsLabel: '媒体归档设置',
      ),
      const _StageGroupHeading(title: '理解与整理', showModelSettings: true),
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
            ? '正在读取摘要设置'
            : summaryEnabled
            ? '解析后自动生成摘要'
            : '已关闭',
        latestRun: summaryRun,
      ),
      _ProcessingStageSection(
        title: '自动整理相关内容',
        policyEnabled: settingsReady ? aggregationEnabled : null,
        onPolicyChanged: (value) => ref
            .read(systemSettingsProvider.notifier)
            .updateSetting(
              'enable_content_aggregation',
              value,
              category: 'automation',
            ),
        icon: Icons.hub_rounded,
        tone: settingsState.hasError
            ? _StageTone.warning
            : !settingsReady
            ? _StageTone.loading
            : aggregationEnabled
            ? _toneForRun(aggregationRun)
            : _StageTone.inactive,
        status: settingsState.hasError
            ? '整理设置读取失败'
            : !settingsReady
            ? '正在读取整理设置'
            : aggregationEnabled
            ? '每小时整理一次'
            : '已关闭',
        latestRun: aggregationRun,
      ),
      _ProcessingStageSection(
        title: '发送整理后的内容',
        policyEnabled: settingsReady ? aggregationPushEnabled : null,
        onPolicyChanged: (value) => ref
            .read(systemSettingsProvider.notifier)
            .updateSetting(
              'enable_aggregation_push',
              value,
              category: 'automation',
            ),
        icon: Icons.outbound_rounded,
        tone: settingsState.hasError
            ? _StageTone.warning
            : !settingsReady
            ? _StageTone.loading
            : aggregationPushEnabled
            ? _StageTone.ok
            : _StageTone.inactive,
        status: settingsState.hasError
            ? '发送设置读取失败'
            : !settingsReady
            ? '正在读取发送设置'
            : aggregationPushEnabled
            ? '按分发规则发送'
            : '已关闭',
      ),
      _ProcessingStageSection(
        title: '搜索索引',
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
            ? '正在读取索引状态'
            : '已索引 $indexed · 待索引 $pending${semanticEnabled ? '' : ' · 自动索引已关闭'}',
        latestRun: semanticRun,
      ),
    ];
  }
}

class _StageGroupHeading extends StatelessWidget {
  const _StageGroupHeading({
    required this.title,
    this.showModelSettings = false,
  });

  final String title;
  final bool showModelSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (showModelSettings)
          TextButton(
            onPressed: () => context.push('/settings?tab=automation'),
            child: const Text('模型配置'),
          ),
      ],
    ),
  );
}

class _ProcessingStageSection extends StatefulWidget {
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
  final Future<void> Function(bool)? onPolicyChanged;
  final BackgroundTaskRun? latestRun;
  final List<FailedParseTask> failures;

  @override
  State<_ProcessingStageSection> createState() =>
      _ProcessingStageSectionState();
}

class _ProcessingStageSectionState extends State<_ProcessingStageSection> {
  bool _saving = false;
  String? _saveError;

  Future<void> _changePolicy(bool value) async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onPolicyChanged!(value);
    } catch (_) {
      if (mounted) setState(() => _saveError = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toneColor = _toneColor(cs, widget.tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: AppShape.cardBorder,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, color: toneColor),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.onPolicyChanged != null)
                    Semantics(
                      label: widget.title,
                      child: Switch(
                        value: widget.policyEnabled ?? false,
                        onChanged: widget.policyEnabled == null || _saving
                            ? null
                            : _changePolicy,
                      ),
                    )
                  else
                    _StageBadge(tone: widget.tone),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(widget.status, style: theme.textTheme.bodyMedium),
              if (_saveError != null)
                Text(
                  _saveError!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                ),
              if (widget.failures.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final failure in widget.failures.take(3))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.error_outline_rounded, color: cs.error),
                    title: Text(
                      failure.title?.trim().isNotEmpty == true
                          ? failure.title!
                          : '解析失败',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: failure.contentId == null
                        ? null
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: failure.contentId == null
                        ? null
                        : () =>
                              context.push('/collection/${failure.contentId}'),
                  ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (widget.settingsPath != null)
                    OutlinedButton.icon(
                      onPressed: () => context.push(widget.settingsPath!),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: Text(widget.settingsLabel!),
                    ),
                  if (widget.latestRun != null &&
                      widget.latestRun!.runId.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          context.push('/tasks/${widget.latestRun!.runId}'),
                      icon: const Icon(Icons.receipt_long_rounded, size: 18),
                      label: const Text('最近运行'),
                    ),
                ],
              ),
            ],
          ),
        ),
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

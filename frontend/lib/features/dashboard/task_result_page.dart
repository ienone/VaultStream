import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/toast.dart';
import '../../theme/design_tokens.dart';
import '../settings/providers/favorites_sync_provider.dart';
import 'models/stats.dart';
import 'providers/dashboard_provider.dart';

class TaskResultPage extends ConsumerWidget {
  const TaskResultPage({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runAsync = ref.watch(backgroundTaskRunProvider(runId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务结果'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(backgroundTaskRunProvider(runId)),
          ),
        ],
      ),
      body: runAsync.when(
        data: (run) => _TaskResultBody(run: run),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _TaskLoadError(
          error: error,
          onRetry: () => ref.invalidate(backgroundTaskRunProvider(runId)),
        ),
      ),
    );
  }
}

class _TaskLoadError extends StatelessWidget {
  const _TaskLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('任务结果加载失败: $error', textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskResultBody extends StatelessWidget {
  const _TaskResultBody({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context) {
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TaskSummaryCard(run: run),
        if (run.presentation.resultSections.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _BusinessResultCard(run: run),
        ],
      ],
    );
    final contextPane = _RunContextCard(run: run);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                main,
                const SizedBox(height: AppSpacing.md),
                contextPane,
                if (run.metadata.isNotEmpty ||
                    (run.result?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: AppSpacing.md),
                  _TechnicalDetails(run: run),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskSummaryCard extends StatelessWidget {
  const _TaskSummaryCard({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = _statusColor(colors, run.status);
    final presentation = run.presentation;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: AppShape.cardMediaBorder,
                  ),
                  child: Icon(_kindIcon(presentation.kind), color: statusColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _statusLabel(run.status),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(presentation.summary, style: theme.textTheme.bodyLarge),
            if (presentation.allowedActions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final action in presentation.allowedActions)
                    if (action.isPrimary)
                      FilledButton(
                        onPressed: () => context.push(action.href),
                        child: Text(action.label),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => context.push(action.href),
                        child: Text(action.label),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BusinessResultCard extends ConsumerWidget {
  const _BusinessResultCard({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final presentation = run.presentation;
    final favoritesResults = presentation.kind == 'favorites_sync'
        ? _favoritesPlatformResults(run.result)
        : const <Map<String, dynamic>>[];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppShape.paneBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (
              var index = 0;
              index < presentation.resultSections.length;
              index++
            ) ...[
              if (index > 0) const Divider(height: AppSpacing.xxl),
              _ResultSection(section: presentation.resultSections[index]),
            ],
            if (favoritesResults.any(_hasFavoriteFailure)) ...[
              const Divider(height: AppSpacing.xxl),
              _FavoritesFailureSection(
                runId: run.runId,
                results: favoritesResults,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FavoritesFailureSection extends ConsumerWidget {
  const _FavoritesFailureSection({required this.runId, required this.results});

  final String runId;
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failed = results.where(_hasFavoriteFailure).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '失败项与处理',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _retryFavoritesRun(context, ref, runId),
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('重新运行'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final result in failed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.18),
                borderRadius: AppShape.cardMediaBorder,
                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: _FavoritePlatformFailure(
                sourceRunId: runId,
                result: result,
              ),
            ),
          ),
      ],
    );
  }
}

class _FavoritePlatformFailure extends ConsumerWidget {
  const _FavoritePlatformFailure({
    required this.sourceRunId,
    required this.result,
  });

  final String sourceRunId;
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final platform = _mapText(result, 'platform') ?? 'unknown';
    final items = _mapList(result, 'failed_items');
    final total = _mapCount(result, 'failed_items_total') > 0
        ? _mapCount(result, 'failed_items_total')
        : _mapCount(result, 'failed');
    final error =
        _mapText(result, 'error_hint') ??
        _mapText(result, 'error') ??
        _mapText(result, 'error_message');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.report_problem_outlined, size: 18, color: colors.error),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '$platform · $total 个失败项',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (items.isNotEmpty)
              TextButton.icon(
                onPressed: () => _retryFavoriteItems(
                  context,
                  ref,
                  platform: platform,
                  sourceRunId: sourceRunId,
                  items: items,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试全部'),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ],
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final item in items.take(20))
            _FavoriteFailedItem(
              item: item,
              onRetry: () => _retryFavoriteItem(
                context,
                ref,
                platform: platform,
                sourceRunId: sourceRunId,
                item: item,
              ),
            ),
          if (result['failed_items_truncated'] == true || total > items.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '仅展示已记录的 ${items.length} 个失败项。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _FavoriteFailedItem extends StatelessWidget {
  const _FavoriteFailedItem({required this.item, required this.onRetry});

  final Map<String, dynamic> item;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _mapText(item, 'title');
    final url = _mapText(item, 'url');
    final error = _mapText(item, 'error') ?? _mapText(item, 'error_code');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                SelectableText(
                  url ?? '失败项缺少 URL',
                  style: theme.textTheme.bodySmall,
                ),
                if (error != null)
                  Text(error, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: '重试此项',
            onPressed: url == null ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.section});

  final TaskRunResultSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth >= 300
                ? (constraints.maxWidth - AppSpacing.sm) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in section.items)
                  SizedBox(
                    width: item.value.length > 30
                        ? constraints.maxWidth
                        : itemWidth,
                    child: _ResultItem(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ResultItem extends StatelessWidget {
  const _ResultItem({required this.item});

  final TaskRunResultItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          SelectableText(item.value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _RunContextCard extends StatelessWidget {
  const _RunContextCard({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final presentation = run.presentation;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '运行信息',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (run.startedAt != null)
              _DetailLine(label: '开始时间', value: _formatTime(run.startedAt!)),
            if (run.finishedAt != null)
              _DetailLine(label: '结束时间', value: _formatTime(run.finishedAt!)),
            if (run.startedAt != null && run.finishedAt != null)
              _DetailLine(
                label: '耗时',
                value: _formatDuration(
                  run.finishedAt!.difference(run.startedAt!),
                ),
              ),
            if (presentation.entityLinks.isNotEmpty) ...[
              const Divider(height: AppSpacing.xxl),
              Text('关联对象', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final link in presentation.entityLinks)
                    ActionChip(
                      avatar: Icon(_entityIcon(link.kind), size: 18),
                      label: Text(link.label),
                      onPressed: () => context.push(link.href),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('技术详情'),
        subtitle: const Text('原始输入与运行结果'),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          if (run.presentation.errorCode case final code?) Text('错误代码：$code'),
          _DetailLine(label: 'Run ID', value: run.runId),
          _DetailLine(label: '任务类型', value: run.task),
          _DetailLine(
            label: '触发来源',
            value: run.metadata['trigger']?.toString() ?? '-',
          ),

          if (run.metadata.isNotEmpty)
            _JsonBlock(title: 'Metadata', data: run.metadata),
          if (run.metadata.isNotEmpty && (run.result?.isNotEmpty ?? false))
            const SizedBox(height: AppSpacing.sm),
          if (run.result?.isNotEmpty ?? false)
            _JsonBlock(title: 'Result', data: run.result!),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.title, required this.data});

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: AppShape.cardMediaBorder,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(data),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _favoritesPlatformResults(
  Map<String, dynamic>? result,
) {
  if (result == null) return const [];
  final allResults = result['results'];
  if (allResults is Map) {
    return allResults.entries
        .where((entry) => entry.value is Map)
        .map((entry) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          item.putIfAbsent('platform', () => entry.key.toString());
          return item;
        })
        .toList(growable: false);
  }
  final single = result['result'];
  if (single is Map) {
    return [Map<String, dynamic>.from(single)];
  }
  if (result.containsKey('platform')) return [result];
  return const [];
}

bool _hasFavoriteFailure(Map<String, dynamic> result) {
  final status = _mapText(result, 'status');
  return status == 'failed' ||
      status == 'partial_success' ||
      _mapCount(result, 'failed') > 0 ||
      _mapCount(result, 'failed_items_total') > 0;
}

String? _mapText(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _mapCount(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _mapList(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

Future<void> _retryFavoritesRun(
  BuildContext context,
  WidgetRef ref,
  String runId,
) async {
  try {
    final nextRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryRun(runId);
    if (!context.mounted) return;
    Toast.show(
      context,
      '已重新触发收藏同步',
      action: nextRunId == null
          ? null
          : SnackBarAction(
              label: '查看新任务',
              onPressed: () => context.push('/tasks/$nextRunId'),
            ),
    );
  } catch (error) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(error, fallbackMessage: '重新运行收藏同步失败'),
        isError: true,
      );
    }
  }
}

Future<void> _retryFavoriteItem(
  BuildContext context,
  WidgetRef ref, {
  required String platform,
  required String sourceRunId,
  required Map<String, dynamic> item,
}) async {
  final url = _mapText(item, 'url');
  if (url == null) return;
  try {
    final nextRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryItem(
          platform: platform,
          url: url,
          title: _mapText(item, 'title'),
          itemId: _mapText(item, 'item_id'),
          sourceRunId: sourceRunId,
        );
    if (!context.mounted) return;
    Toast.show(
      context,
      '已重试失败项',
      action: nextRunId == null
          ? null
          : SnackBarAction(
              label: '查看新任务',
              onPressed: () => context.push('/tasks/$nextRunId'),
            ),
    );
  } catch (error) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(error, fallbackMessage: '重试失败项失败'),
        isError: true,
      );
    }
  }
}

Future<void> _retryFavoriteItems(
  BuildContext context,
  WidgetRef ref, {
  required String platform,
  required String sourceRunId,
  required List<Map<String, dynamic>> items,
}) async {
  final inputs = items
      .where((item) => _mapText(item, 'url') != null)
      .map(
        (item) => <String, dynamic>{
          'url': _mapText(item, 'url'),
          if (_mapText(item, 'title') case final title?) 'title': title,
          if (_mapText(item, 'item_id') case final itemId?) 'item_id': itemId,
        },
      )
      .toList(growable: false);
  if (inputs.isEmpty) return;
  try {
    final nextRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryItems(
          platform: platform,
          items: inputs,
          sourceRunId: sourceRunId,
        );
    if (!context.mounted) return;
    Toast.show(
      context,
      '已批量重试 ${inputs.length} 个失败项',
      action: nextRunId == null
          ? null
          : SnackBarAction(
              label: '查看新任务',
              onPressed: () => context.push('/tasks/$nextRunId'),
            ),
    );
  } catch (error) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(error, fallbackMessage: '批量重试失败项失败'),
        isError: true,
      );
    }
  }
}

IconData _kindIcon(String kind) {
  return switch (kind) {
    'favorites_sync' => Icons.sync_rounded,
    'content_processing' => Icons.auto_fix_high_rounded,
    'semantic_index' => Icons.manage_search_rounded,
    'discovery' => Icons.explore_rounded,
    'distribution' => Icons.send_rounded,
    'connectivity_test' => Icons.cable_rounded,
    'account_sync' => Icons.manage_accounts_rounded,
    _ => Icons.task_alt_rounded,
  };
}

IconData _entityIcon(String kind) {
  return switch (kind) {
    'content' => Icons.article_outlined,
    'discovery_source' => Icons.rss_feed_rounded,
    'queue_item' => Icons.outbox_outlined,
    'account' => Icons.account_circle_outlined,
    _ => Icons.link_rounded,
  };
}

Color _statusColor(ColorScheme colors, String status) {
  return switch (status) {
    'success' || 'ok' => colors.tertiary,
    'running' => colors.primary,
    'error' || 'failed' => colors.error,
    _ => colors.onSurfaceVariant,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'success' || 'ok' => '已完成',
    'running' => '运行中',
    'error' || 'failed' => '需要处理',
    _ => status,
  };
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds < 1) return '${duration.inMilliseconds} 毫秒';
  if (duration.inMinutes < 1) return '${duration.inSeconds} 秒';
  final seconds = duration.inSeconds.remainder(60);
  return '${duration.inMinutes} 分 ${seconds.toString().padLeft(2, '0')} 秒';
}

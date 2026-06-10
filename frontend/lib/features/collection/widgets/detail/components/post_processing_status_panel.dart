import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_client.dart';
import '../../../../../core/utils/toast.dart';
import '../../../providers/collection_provider.dart';

class PostProcessingStatusPanel extends ConsumerWidget {
  final int contentId;

  const PostProcessingStatusPanel({super.key, required this.contentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(contentProcessingStatusProvider(contentId));
    final colorScheme = Theme.of(context).colorScheme;

    return statusAsync.when(
      data: (status) {
        final stages = (status['stages'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        if (stages.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '处理状态',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final stage in stages)
                _StageRow(contentId: contentId, stage: stage),
            ],
          ),
        );
      },
      loading: () => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('处理状态加载中'),
          ],
        ),
      ),
      error: (_, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(width: 10),
            const Expanded(child: Text('处理状态加载失败')),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () =>
                  ref.invalidate(contentProcessingStatusProvider(contentId)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends ConsumerWidget {
  final int contentId;
  final Map<String, dynamic> stage;

  const _StageRow({required this.contentId, required this.stage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = stage['status']?.toString() ?? 'unknown';
    final color = _statusColor(context, status);
    final label = stage['label']?.toString() ?? stage['key']?.toString() ?? '';
    final message = stage['message']?.toString() ?? '';
    final failures = _extractFailures(stage);
    final issues = _extractStringList(stage['issues']);
    final actions = _extractStringList(stage['actions']);
    final action = _stageAction(stage, status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_statusIcon(status), size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (message.isNotEmpty)
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (failures.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _failureSummary(failures),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    if (issues.isNotEmpty)
                      _StageHintLine(
                        label: '问题',
                        values: issues,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    if (actions.isNotEmpty)
                      _StageHintLine(
                        label: '建议',
                        values: actions,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel(status),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (action != null || failures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (action != null)
                    FilledButton.tonalIcon(
                      onPressed: () => _runAction(context, ref, action),
                      icon: Icon(action.icon, size: 16),
                      label: Text(action.label),
                    ),
                  if (failures.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _showFailureDetails(context, failures),
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text('失败详情'),
                    ),
                  if (_isSemanticStage)
                    for (final failure in failures)
                      if (failure['id'] != null)
                        TextButton.icon(
                          onPressed: () =>
                              _retryEmbedding(context, ref, failure),
                          icon: const Icon(Icons.replay_rounded, size: 16),
                          label: Text(_retryEmbeddingLabel(failure)),
                        ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractFailures(Map<String, dynamic> stage) {
    final details = stage['details'];
    if (details is! Map) return const [];
    final failures = details['failures'];
    if (failures is! List) return const [];
    return failures
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _extractStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _failureSummary(List<Map<String, dynamic>> failures) {
    final first = failures.first;
    final text =
        first['last_error'] ??
        first['failure_reason'] ??
        first['last_error_type'] ??
        '未知错误';
    final suffix = failures.length > 1 ? ' 等 ${failures.length} 项' : '';
    return '$text$suffix';
  }

  _StageAction? _stageAction(Map<String, dynamic> stage, String status) {
    final key = stage['key']?.toString();
    if (key == 'summary' &&
        !{'success', 'waiting_parse', 'disabled'}.contains(status)) {
      return const _StageAction(
        label: '生成摘要',
        icon: Icons.auto_awesome_rounded,
        kind: _StageActionKind.summary,
      );
    }
    if (key == 'semantic_index' && {'failed', 'not_indexed'}.contains(status)) {
      return const _StageAction(
        label: '重建索引',
        icon: Icons.hub_rounded,
        kind: _StageActionKind.semanticIndex,
      );
    }
    if (key == 'distribution' && {'failed', 'not_matched'}.contains(status)) {
      return _StageAction(
        label: status == 'failed' ? '重试分发' : '重新匹配',
        icon: Icons.outbox_rounded,
        kind: _StageActionKind.distribution,
      );
    }
    if (key == 'patrol' && {'pending', 'not_scored'}.contains(status)) {
      return const _StageAction(
        label: '触发评分',
        icon: Icons.rate_review_rounded,
        kind: _StageActionKind.patrol,
      );
    }
    return null;
  }

  bool get _isSemanticStage => stage['key']?.toString() == 'semantic_index';

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    _StageAction action,
  ) async {
    final dio = ref.read(apiClientProvider);
    try {
      String successMessage;
      String? runId;
      switch (action.kind) {
        case _StageActionKind.summary:
          final response = await dio.post(
            '/contents/$contentId/generate-summary?force=true',
          );
          runId = _extractRunId(response.data);
          ref.invalidate(contentDetailProvider(contentId));
          successMessage = '已开始生成摘要';
          break;
        case _StageActionKind.semanticIndex:
          final response = await dio.post(
            '/search/semantic/reindex',
            data: {
              'scope': 'single',
              'content_id': contentId,
              'dry_run': false,
            },
          );
          runId = _extractRunId(response.data);
          successMessage = '已调度语义索引重建';
          break;
        case _StageActionKind.distribution:
          final failures = _extractFailures(stage);
          if (failures.isNotEmpty) {
            for (final failure in failures) {
              final id = failure['id'];
              if (id == null) continue;
              await dio.post(
                '/distribution-queue/items/$id/retry',
                data: {'reset_attempts': true},
              );
            }
            successMessage = '已重试失败分发项';
          } else {
            await dio.post(
              '/distribution-queue/enqueue/$contentId',
              data: {'force': true},
            );
            successMessage = '已重新匹配分发规则';
          }
          break;
        case _StageActionKind.patrol:
          final response = await dio.post('/contents/$contentId/patrol-score');
          runId = _extractRunId(response.data);
          ref.invalidate(contentDetailProvider(contentId));
          successMessage = '已触发巡逻评分';
          break;
      }
      ref.invalidate(contentProcessingStatusProvider(contentId));
      if (context.mounted) {
        _showSuccessToast(context, successMessage, runId);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(e, fallbackMessage: '${action.label}失败'),
          isError: true,
        );
      }
    }
  }

  Future<void> _retryEmbedding(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> failure,
  ) async {
    final id = failure['id'];
    if (id == null) return;

    final dio = ref.read(apiClientProvider);
    try {
      final response = await dio.post('/search/semantic/embeddings/$id/retry');
      final runId = _extractRunId(response.data);
      ref.invalidate(contentProcessingStatusProvider(contentId));
      ref.invalidate(contentDetailProvider(contentId));
      if (context.mounted) {
        _showSuccessToast(context, '已重试语义分块', runId);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(e, fallbackMessage: '重试语义分块失败'),
          isError: true,
        );
      }
    }
  }

  String _retryEmbeddingLabel(Map<String, dynamic> failure) {
    final chunk = failure['chunk_index'];
    return chunk == null ? '重试分块' : '重试分块 $chunk';
  }

  void _showSuccessToast(BuildContext context, String message, String? runId) {
    Toast.show(
      context,
      message,
      action: runId == null
          ? null
          : SnackBarAction(
              label: '查看日志',
              onPressed: () =>
                  context.go('/tasks/${Uri.encodeComponent(runId)}'),
            ),
    );
  }

  String? _extractRunId(dynamic data) {
    if (data is! Map) return null;
    final value = data['run_id']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  void _showFailureDetails(
    BuildContext context,
    List<Map<String, dynamic>> failures,
  ) {
    final detailsText = failures
        .map(
          (item) => item.entries
              .where((entry) => entry.value != null)
              .map((entry) => '${entry.key}: ${entry.value}')
              .join('\n'),
        )
        .join('\n\n');

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('失败详情'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(detailsText)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'success':
      case 'pushed':
        return Icons.check_circle_rounded;
      case 'queued':
      case 'pending':
        return Icons.schedule_rounded;
      case 'failed':
      case 'unavailable':
        return Icons.error_rounded;
      case 'disabled':
      case 'not_matched':
      case 'not_indexed':
      case 'not_scored':
      case 'waiting_parse':
        return Icons.info_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'success':
      case 'pushed':
        return Colors.green;
      case 'queued':
      case 'pending':
        return Colors.orange;
      case 'failed':
      case 'unavailable':
        return colorScheme.error;
      case 'disabled':
      case 'not_matched':
      case 'not_indexed':
      case 'not_scored':
      case 'waiting_parse':
        return colorScheme.outline;
      default:
        return colorScheme.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'success':
        return '成功';
      case 'pushed':
        return '已推送';
      case 'queued':
        return '队列中';
      case 'pending':
        return '处理中';
      case 'failed':
        return '失败';
      case 'unavailable':
        return '不可用';
      case 'disabled':
        return '已关闭';
      case 'not_matched':
        return '未匹配';
      case 'not_indexed':
        return '未索引';
      case 'not_scored':
        return '未评分';
      case 'waiting_parse':
        return '等解析';
      default:
        return status;
    }
  }
}

class _StageHintLine extends StatelessWidget {
  final String label;
  final List<String> values;
  final Color color;

  const _StageHintLine({
    required this.label,
    required this.values,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: ${values.join('；')}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

enum _StageActionKind { summary, semanticIndex, distribution, patrol }

class _StageAction {
  const _StageAction({
    required this.label,
    required this.icon,
    required this.kind,
  });

  final String label;
  final IconData icon;
  final _StageActionKind kind;
}

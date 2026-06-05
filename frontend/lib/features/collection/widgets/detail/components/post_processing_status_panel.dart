import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              for (final stage in stages) _StageRow(stage: stage),
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

class _StageRow extends StatelessWidget {
  final Map<String, dynamic> stage;

  const _StageRow({required this.stage});

  @override
  Widget build(BuildContext context) {
    final status = stage['status']?.toString() ?? 'unknown';
    final color = _statusColor(context, status);
    final label = stage['label']?.toString() ?? stage['key']?.toString() ?? '';
    final message = stage['message']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
      case 'waiting_parse':
        return '等解析';
      default:
        return status;
    }
  }
}

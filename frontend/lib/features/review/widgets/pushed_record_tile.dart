import 'package:flutter/material.dart';
import '../models/pushed_record.dart';

class PushedRecordTile extends StatelessWidget {
  final PushedRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  const PushedRecordTile({
    super.key,
    required this.record,
    this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: _getStatusColor(colorScheme).withValues(alpha: 0.1),
        child: Icon(
          _getStatusIcon(),
          color: _getStatusColor(colorScheme),
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Text(
            record.targetPlatform,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getStatusColor(colorScheme).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _getStatusLabel(),
              style: TextStyle(
                fontSize: 10,
                color: _getStatusColor(colorScheme),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目标: ${record.targetId}',
            style: theme.textTheme.bodySmall,
          ),
          if (record.messageId != null)
            Text(
              '消息ID: ${record.messageId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (record.errorMessage != null)
            Text(
              record.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            _formatDateTime(record.pushedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
      trailing: record.isFailed
          ? IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: onRetry,
              tooltip: '重试推送',
            )
          : null,
      isThreeLine: true,
    );
  }

  Color _getStatusColor(ColorScheme colorScheme) {
    if (record.isSuccess) return Colors.green;
    if (record.isFailed) return colorScheme.error;
    return colorScheme.tertiary;
  }

  IconData _getStatusIcon() {
    if (record.isSuccess) return Icons.check_circle;
    if (record.isFailed) return Icons.error;
    return Icons.hourglass_empty;
  }

  String _getStatusLabel() {
    if (record.isSuccess) return '成功';
    if (record.isFailed) return '失败';
    if (record.isPending) return '待处理';
    return record.pushStatus;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

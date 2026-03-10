import 'package:flutter/material.dart';
import '../models/stats.dart';
import 'donut_chart.dart';

/// 解析队列状态饼图卡片。
///
/// 内部将队列数据映射为 [DonutEntry] 列表，交由 [DonutOverviewCard] 渲染。
/// [onStatusTap] 回调参数为 ContentStatus 字符串值：
/// `'unprocessed'` | `'processing'` | `'parse_success'` | `'parse_failed'`
class QueueStatusCard extends StatelessWidget {
  final QueueOverviewStats queue;
  final void Function(String status)? onStatusTap;

  const QueueStatusCard({
    super.key,
    required this.queue,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parse = queue.parse;

    return DonutOverviewCard(
      centerSubLabel: '总计',
      emptyMessage: '队列为空',
      totalOverride: parse.total,
      entries: [
        DonutEntry(
          label: '未处理',
          value: parse.unprocessed,
          color: cs.tertiary,
          leading: Icon(Icons.hourglass_empty_rounded, size: 16, color: cs.tertiary),
          onTap: onStatusTap != null ? () => onStatusTap!('unprocessed') : null,
        ),
        DonutEntry(
          label: '解析中',
          value: parse.processing,
          color: cs.primary,
          leading: Icon(Icons.sync_rounded, size: 16, color: cs.primary),
          onTap: onStatusTap != null ? () => onStatusTap!('processing') : null,
        ),
        DonutEntry(
          label: '解析成功',
          value: parse.parseSuccess,
          color: cs.secondary,
          leading: Icon(Icons.check_circle_outline_rounded, size: 16, color: cs.secondary),
          onTap: onStatusTap != null ? () => onStatusTap!('parse_success') : null,
        ),
        DonutEntry(
          label: '解析失败',
          value: parse.parseFailed,
          color: cs.error,
          leading: Icon(Icons.error_outline_rounded, size: 16, color: cs.error),
          onTap: onStatusTap != null ? () => onStatusTap!('parse_failed') : null,
        ),
      ],
    );
  }
}

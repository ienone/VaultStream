import 'package:flutter/material.dart';
import '../../discovery/models/discovery_models.dart';
import 'donut_chart.dart';

/// 探索概览饼图卡片。
///
/// 将 [DiscoveryStats.byState] 映射为 [DonutEntry] 列表，
/// 次要状态（merged / expired）仅在数量 > 0 时展示。
/// [onStateTap] 回调 `(state, showAll)`，由调用方决定导航逻辑。
class DiscoveryOverviewCard extends StatelessWidget {
  final DiscoveryStats stats;
  final void Function(String? state, bool showAll)? onStateTap;

  const DiscoveryOverviewCard({
    super.key,
    required this.stats,
    this.onStateTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // (key, label, icon, color, showAll)
    final defs = [
      _Def('visible',  '待查阅', Icons.visibility_rounded,            cs.primary,        false),
      _Def('promoted', '已收录', Icons.bookmark_added_rounded,        cs.secondary,      true),
      _Def('ingested', '待摄入', Icons.inbox_rounded,                 cs.tertiary,       true),
      _Def('scored',   '已评分', Icons.bar_chart_rounded,             cs.primaryFixed,   true),
      _Def('ignored',  '已移除', Icons.remove_circle_outline_rounded, cs.error,          true),
      _Def('expired',  '已过期', Icons.timer_off_rounded,             cs.outlineVariant, true),
      _Def('merged',   '已合并', Icons.merge_rounded,                 cs.outline,        true),
    ];

    final entries = defs
        .where((d) {
          // 次要状态只在有数据时展示
          final isMinor = d.key == 'expired' || d.key == 'merged';
          return !isMinor || (stats.byState[d.key] ?? 0) > 0;
        })
        .map((d) => DonutEntry(
              label: d.label,
              value: stats.byState[d.key] ?? 0,
              color: d.color,
              leading: Icon(d.icon, size: 16, color: d.color),
              onTap: onStateTap != null
                  ? () => onStateTap!(d.key, d.showAll)
                  : null,
            ))
        .toList();

    return DonutOverviewCard(
      centerSubLabel: '总计',
      emptyMessage: '暂无探索数据',
      totalOverride: stats.total,
      entries: entries,
    );
  }
}

class _Def {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final bool showAll;
  const _Def(this.key, this.label, this.icon, this.color, this.showAll);
}

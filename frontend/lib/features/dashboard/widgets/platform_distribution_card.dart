import 'package:flutter/material.dart';
import '../models/stats.dart';
import 'donut_chart.dart';

/// 平台分布饼图卡片。
///
/// 将 [DashboardStats.platformCounts] 映射为 [DonutEntry] 列表，
/// 交由 [DonutOverviewCard] 渲染。点击图例行触发 [onPlatformTap]。
class PlatformDistributionCard extends StatelessWidget {
  final DashboardStats stats;
  final void Function(String) onPlatformTap;

  const PlatformDistributionCard({
    super.key,
    required this.stats,
    required this.onPlatformTap,
  });

  static final List<Color Function(ColorScheme)> _colorPickers = [
    (cs) => cs.primary,
    (cs) => cs.secondary,
    (cs) => cs.tertiary,
    (cs) => cs.error,
    (cs) => cs.primaryFixed,
    (cs) => cs.secondaryFixed,
    (cs) => cs.tertiaryFixed,
  ];

  @override
  Widget build(BuildContext context) {
    final total = stats.platformCounts.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text('暂无数据'));

    final cs = Theme.of(context).colorScheme;
    final sorted = stats.platformCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Color colorAt(int i) => _colorPickers[i % _colorPickers.length](cs);

    return DonutOverviewCard(
      centerSubLabel: '总内容',
      totalOverride: total,
      entries: sorted.asMap().entries.map((e) {
        final i = e.key;
        final platform = e.value.key;
        final count = e.value.value;
        final color = colorAt(i);
        return DonutEntry(
          label: platform.toUpperCase(),
          value: count,
          color: color,
          leading: _PlatformIcon(platform: platform, color: color),
          onTap: () => onPlatformTap(platform),
        );
      }).toList(),
    );
  }
}

class _PlatformIcon extends StatelessWidget {
  final String platform;
  final Color color;

  const _PlatformIcon({required this.platform, required this.color});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (platform.toLowerCase()) {
      case 'bilibili':
        icon = Icons.video_library_rounded;
      case 'zhihu':
        icon = Icons.article_rounded;
      case 'weibo':
        icon = Icons.share_rounded;
      case 'twitter':
        icon = Icons.alternate_email_rounded;
      case 'xiaohongshu':
        icon = Icons.explore_rounded;
      case 'telegram':
        icon = Icons.send_rounded;
      case 'rss':
        icon = Icons.rss_feed_rounded;
      default:
        icon = Icons.device_hub_rounded;
    }
    return Icon(icon, size: 16, color: color);
  }
}

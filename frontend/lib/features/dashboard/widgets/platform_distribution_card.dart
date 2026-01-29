import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/stats.dart';

class PlatformDistributionCard extends StatelessWidget {
  final DashboardStats stats;
  final Function(String) onPlatformTap;

  const PlatformDistributionCard({
    super.key, 
    required this.stats,
    required this.onPlatformTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = stats.platformCounts.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text('暂无数据'));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: stats.platformCounts.entries.indexed.map((indexedEntry) {
            final index = indexedEntry.$1;
            final entry = indexedEntry.$2;
            final percent = total > 0 ? entry.value / total : 0.0;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: InkWell(
                onTap: () => onPlatformTap(entry.key),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              _getPlatformIcon(entry.key),
                              const SizedBox(width: 12),
                              Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Text(
                            '${entry.value} (${(percent * 100).toStringAsFixed(1)}%)',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 12,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ).animate().fadeIn(delay: (index * 150).ms).scaleX(begin: 0, end: 1, alignment: Alignment.centerLeft),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _getPlatformIcon(String platform) {
    IconData iconData;
    switch (platform.toLowerCase()) {
      case 'bilibili': iconData = Icons.video_library; break;
      case 'zhihu': iconData = Icons.article; break;
      case 'weibo': iconData = Icons.share; break;
      case 'twitter': iconData = Icons.alternate_email; break;
      case 'xiaohongshu': iconData = Icons.explore; break;
      default: iconData = Icons.device_hub;
    }
    return Icon(iconData, size: 18);
  }
}
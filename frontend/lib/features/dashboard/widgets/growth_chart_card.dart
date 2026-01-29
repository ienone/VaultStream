import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/stats.dart';

class GrowthChartCard extends StatelessWidget {
  final DashboardStats stats;
  final Function(DateTimeRange) onDateTap;

  const GrowthChartCard({
    super.key, 
    required this.stats,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    if (stats.dailyGrowth.isEmpty) return const Center(child: Text('暂无数据'));

    final maxCount = stats.dailyGrowth.fold(
      0,
      (max, day) => (day['count'] as int) > max ? day['count'] as int : max,
    );

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: stats.dailyGrowth.asMap().entries.map((entry) {
              final index = entry.key;
              final day = entry.value;
              final count = day['count'] as int;
              final heightFactor = maxCount > 0 ? count / maxCount : 0.0;
              final date = DateTime.parse(day['date']);

              return Expanded(
                child: InkWell(
                  onTap: () {
                    final start = DateTime(date.year, date.month, date.day);
                    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
                    onDateTap(DateTimeRange(start: start, end: end));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        count.toString(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: count > 0 ? colorScheme.primary : colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ).animate().fadeIn(delay: (index * 100 + 400).ms),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: '${day['date']}: $count',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          height: (heightFactor * 140).clamp(6.0, 140.0),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withValues(alpha: 0.5),
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                              bottom: Radius.circular(4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ).animate().scaleY(
                          begin: 0,
                          end: 1,
                          duration: 600.ms,
                          delay: (index * 100).ms,
                          curve: Curves.easeOutBack,
                          alignment: Alignment.bottomCenter,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${date.month}/${date.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
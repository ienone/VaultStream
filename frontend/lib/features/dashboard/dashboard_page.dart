import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/dashboard_provider.dart';
import 'models/stats.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final queueAsync = ref.watch(queueStatsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(dashboardStatsProvider);
              ref.invalidate(queueStatsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(queueStatsProvider);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '系统概览',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildStatsGrid(context, statsAsync, queueAsync),
              const SizedBox(height: 32),
              Text(
                '平台分布',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildPlatformDistribution(context, statsAsync),
              const SizedBox(height: 32),
              Text(
                '最近 7 天增长',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildGrowthChart(context, statsAsync),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(
    BuildContext context,
    AsyncValue<DashboardStats> statsAsync,
    AsyncValue<QueueStats> queueAsync,
  ) {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          context,
          '总内容',
          statsAsync.when(
            data: (s) =>
                s.platformCounts.values.fold(0, (a, b) => a + b).toString(),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          Icons.library_books_outlined,
          Theme.of(context).colorScheme.primary,
        ),
        _buildStatCard(
          context,
          '存储占用',
          statsAsync.when(
            data: (s) => _formatBytes(s.storageUsageBytes),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          Icons.storage_outlined,
          Theme.of(context).colorScheme.secondary,
        ),
        _buildStatCard(
          context,
          '队列积压',
          queueAsync.when(
            data: (q) => q.pending.toString(),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          Icons.hourglass_empty,
          Theme.of(context).colorScheme.tertiary,
        ),
        _buildStatCard(
          context,
          '解析失败',
          queueAsync.when(
            data: (q) => q.failed.toString(),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          Icons.error_outline,
          Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformDistribution(
    BuildContext context,
    AsyncValue<DashboardStats> statsAsync,
  ) {
    return statsAsync.when(
      data: (stats) {
        final total = stats.platformCounts.values.fold(0, (a, b) => a + b);
        if (total == 0) return const Center(child: Text('暂无数据'));

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: stats.platformCounts.entries.map((entry) {
                final percent = total > 0 ? entry.value / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${entry.value} (${(percent * 100).toStringAsFixed(1)}%)',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: percent,
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 8,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  Widget _buildGrowthChart(
    BuildContext context,
    AsyncValue<DashboardStats> statsAsync,
  ) {
    return statsAsync.when(
      data: (stats) {
        if (stats.dailyGrowth.isEmpty) return const Center(child: Text('暂无数据'));

        final maxCount = stats.dailyGrowth.fold(
          0,
          (max, day) => (day['count'] as int) > max ? day['count'] as int : max,
        );

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: stats.dailyGrowth.map((day) {
                  final count = day['count'] as int;
                  final heightFactor = maxCount > 0 ? count / maxCount : 0.0;
                  final date = DateTime.parse(day['date']);

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: '${day['date']}: $count',
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: (heightFactor * 140).clamp(4.0, 140.0),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${date.month}/${date.day}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}";
  }
}

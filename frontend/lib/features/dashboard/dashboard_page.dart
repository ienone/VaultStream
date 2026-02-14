import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'providers/dashboard_provider.dart';
import 'models/stats.dart';
import '../collection/providers/collection_filter_provider.dart';
import 'widgets/stat_card.dart';
import 'widgets/bot_overview_card.dart';
import 'widgets/queue_status_card.dart';
import 'widgets/platform_distribution_card.dart';
import 'widgets/growth_chart_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  void _navigateToCollection(BuildContext context, WidgetRef ref, {List<String>? statuses, List<String>? platforms, DateTimeRange? dateRange}) {
    // Clear existing filters first
    ref.read(collectionFilterProvider.notifier).clearFilters();
    
    // Set new filters if provided
    ref.read(collectionFilterProvider.notifier).setFilters(
      statuses: statuses,
      platforms: platforms,
      dateRange: dateRange,
    );
    
    // Navigate (switch tab)
    context.go('/collection');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final queueAsync = ref.watch(queueStatsProvider);

    final hasError = statsAsync.hasError || queueAsync.hasError;

    return Scaffold(
      appBar: FrostedAppBar(
        title: const Text('仪表盘'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(dashboardStatsProvider);
              ref.invalidate(queueStatsProvider);
              ref.invalidate(systemHealthProvider);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: hasError
          ? _buildConnectionError(context, ref, statsAsync.error ?? queueAsync.error)
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(dashboardStatsProvider);
                ref.invalidate(queueStatsProvider);
                ref.invalidate(systemHealthProvider);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(context, '系统概览', Icons.analytics_rounded),
                    const SizedBox(height: 24),
                    _buildStatsGrid(context, ref, statsAsync, queueAsync),
                    const SizedBox(height: 40),
                    
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isWide = constraints.maxWidth > 700;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionHeader(context, '队列状态', Icons.queue_rounded),
                                    const SizedBox(height: 16),
                                    queueAsync.when(
                                      data: (q) => QueueStatusCard(queue: q),
                                      loading: () => const _LoadingPlaceholder(height: 240),
                                      error: (e, _) => _ErrorCard(message: '加载队列失败: $e'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionHeader(context, 'Bot 概览', Icons.smart_toy_rounded),
                                    const SizedBox(height: 16),
                                    const BotOverviewCard(),
                                  ],
                                ),
                              ),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(context, '队列状态', Icons.queue_rounded),
                              const SizedBox(height: 16),
                              queueAsync.when(
                                data: (q) => QueueStatusCard(queue: q),
                                loading: () => const _LoadingPlaceholder(height: 240),
                                error: (e, _) => _ErrorCard(message: '加载队列失败: $e'),
                              ),
                              const SizedBox(height: 32),
                              _buildSectionHeader(context, 'Bot 概览', Icons.smart_toy_rounded),
                              const SizedBox(height: 16),
                              const BotOverviewCard(),
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 40),

                    _buildSectionHeader(context, '最近 7 天增长', Icons.trending_up_rounded),
                    const SizedBox(height: 16),
                    statsAsync.when(
                      data: (s) => GrowthChartCard(
                        stats: s,
                        onDateTap: (range) => _navigateToCollection(context, ref, dateRange: range),
                      ),
                      loading: () => const _LoadingPlaceholder(height: 220),
                      error: (e, _) => _ErrorCard(message: '加载图表失败: $e'),
                    ),
                    const SizedBox(height: 40),

                    _buildSectionHeader(context, '平台分布', Icons.pie_chart_rounded),
                    const SizedBox(height: 16),
                    statsAsync.when(
                      data: (s) => PlatformDistributionCard(
                        stats: s,
                        onPlatformTap: (p) => _navigateToCollection(context, ref, platforms: [p]),
                      ),
                      loading: () => const _LoadingPlaceholder(height: 300),
                      error: (e, _) => _ErrorCard(message: '加载分布失败: $e'),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms),
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DashboardStats> statsAsync,
    AsyncValue<QueueOverviewStats> queueAsync,
  ) {
    final isWide = MediaQuery.of(context).size.width > 900;
    
    return GridView.count(
      crossAxisCount: isWide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      childAspectRatio: isWide ? 1.6 : 1.3,
      children: [
        StatCard(
          label: '总内容',
          value: statsAsync.when(
            data: (s) => s.platformCounts.values.fold(0, (a, b) => a + b).toString(),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          icon: Icons.library_books_rounded,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => _navigateToCollection(context, ref),
        ),
        StatCard(
          label: '存储占用',
          value: statsAsync.when(
            data: (s) => _formatBytes(s.storageUsageBytes),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          icon: Icons.storage_rounded,
          color: Theme.of(context).colorScheme.secondary,
        ),
        StatCard(
          label: '队列积压',
          value: queueAsync.when(
            data: (q) => q.parse.unprocessed.toString(),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          icon: Icons.hourglass_top_rounded,
          color: Theme.of(context).colorScheme.tertiary,
          onTap: () => _navigateToCollection(context, ref, statuses: ['unprocessed', 'processing']),
        ),
        StatCard(
          label: '解析失败',
          value: queueAsync.when(
            data: (q) => q.parse.parseFailed.toString(),
            loading: () => '...',
            error: (_, _) => '!',
          ),
          icon: Icons.error_outline_rounded,
          color: Theme.of(context).colorScheme.error,
          onTap: () => _navigateToCollection(context, ref, statuses: ['parse_failed']),
        ),
      ],
    );
  }

  Widget _buildConnectionError(BuildContext context, WidgetRef ref, Object? error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 80,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '连接服务器失败',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '无法获取实时数据。请确保后端服务已启动并检查 API 配置。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    ref.invalidate(dashboardStatsProvider);
                    ref.invalidate(queueStatsProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试连接'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('前往设置'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}";
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  final double height;
  const _LoadingPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
      ),
      child: const Center(child: CircularProgressIndicator()),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds);
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    );
  }
}
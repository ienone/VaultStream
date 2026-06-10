import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/widgets/frosted_app_bar.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/async_placeholders.dart';
import '../discovery/providers/discovery_stats_provider.dart';
import '../discovery/providers/discovery_filter_provider.dart';
import 'widgets/discovery_overview_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  void _navigateToDiscovery(
    BuildContext context,
    WidgetRef ref, {
    String? state,
    bool showAll = false,
  }) {
    // 原子化设置筛选条件，避免 clearFilters+setFilters 两步触发双重请求导致空列表被覆盖
    ref
        .read(discoveryFilterProvider.notifier)
        .resetToFilters(discoveryState: state, showAll: showAll);
    context.go('/inbox');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryStatsAsync = ref.watch(discoveryStatsProvider);

    final hasError = discoveryStatsAsync.hasError;
    final theme = Theme.of(context);
    final sectionStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5,
    );

    return Scaffold(
      appBar: FrostedAppBar(title: const Text('动态')),
      body: hasError
          ? _buildConnectionError(context, ref, discoveryStatsAsync.error)
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(discoveryStatsProvider);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDynamicIntro(context),
                    const SizedBox(height: 32),

                    SectionHeader(
                      title: '推荐候选',
                      icon: Icons.auto_awesome_rounded,
                      padding: EdgeInsets.zero,
                      textStyle: sectionStyle,
                      action: TextButton.icon(
                        onPressed: () => _navigateToDiscovery(context, ref),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('查看候选'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    discoveryStatsAsync.when(
                      data: (s) => DiscoveryOverviewCard(
                        stats: s,
                        onStateTap: (state, showAll) => _navigateToDiscovery(
                          context,
                          ref,
                          state: state,
                          showAll: showAll,
                        ),
                      ),
                      loading: () => const LoadingPlaceholder(height: 260),
                      error: (e, _) => ErrorCard(message: '加载探索数据失败: $e'),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ).animate().fadeIn(duration: 600.ms),
            ),
    );
  }

  Widget _buildDynamicIntro(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '动态正在从系统仪表盘过渡为个人信息流',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这里将聚合订阅源、发现源和 AI 推荐内容；任务进度、同步结果和系统异常会从顶部通知入口进入通知中心。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.76,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionError(
    BuildContext context,
    WidgetRef ref,
    Object? error,
  ) {
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
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
                    ref.invalidate(discoveryStatsProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试连接'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('前往设置'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
    );
  }
}

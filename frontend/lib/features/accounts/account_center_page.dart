import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/toast.dart';
import '../../core/widgets/frosted_app_bar.dart';
import '../auth/presentation/widgets/interactive_login_dialog.dart';
import '../settings/providers/favorites_sync_provider.dart';
import '../settings/providers/platform_health_provider.dart';

class AccountCenterPage extends ConsumerWidget {
  const AccountCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(platformHealthProvider);

    return Scaffold(
      appBar: FrostedAppBar(
        title: const Text('账号中心'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(platformHealthProvider),
          ),
        ],
      ),
      body: healthAsync.when(
        data: (health) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(platformHealthProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _AccountOverview(response: health),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100
                      ? 3
                      : constraints.maxWidth >= 720
                      ? 2
                      : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: health.platforms.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 280,
                    ),
                    itemBuilder: (context, index) =>
                        _PlatformHealthCard(platform: health.platforms[index]),
                  );
                },
              ),
              if (health.recentFavoritesRuns.isNotEmpty) ...[
                const SizedBox(height: 24),
                _RecentFavoritesRuns(runs: health.recentFavoritesRuns),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          error: error,
          onRetry: () => ref.invalidate(platformHealthProvider),
        ),
      ),
    );
  }
}

class _AccountOverview extends StatelessWidget {
  const _AccountOverview({required this.response});

  final PlatformHealthResponse response;

  @override
  Widget build(BuildContext context) {
    final ok = response.platforms.where((item) => item.health == 'ok').length;
    final error = response.platforms
        .where((item) => item.health == 'error')
        .length;
    final syncEnabled = response.platforms
        .where((item) => item.favoritesEnabled)
        .length;
    final connected = response.platforms.where((item) => item.hasCookie).length;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _OverviewTile(
          icon: Icons.verified_user_rounded,
          label: '健康平台',
          value: ok,
        ),
        _OverviewTile(
          icon: Icons.report_gmailerrorred_rounded,
          label: '需处理',
          value: error,
        ),
        _OverviewTile(
          icon: Icons.cookie_rounded,
          label: '已连接',
          value: connected,
        ),
        _OverviewTile(
          icon: Icons.bookmark_added_rounded,
          label: '收藏同步',
          value: syncEnabled,
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlatformHealthCard extends ConsumerWidget {
  const _PlatformHealthCard({required this.platform});

  final PlatformHealthStatus platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final healthColor = _healthColor(context, platform.health);
    final browserAuthSupported =
        platform.auth['browser_auth_supported'] == true;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_platformIcon(platform.platform), color: healthColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    platform.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _healthLabel(platform.health),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: healthColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CapabilityLine(
              icon: Icons.cookie_rounded,
              label: '登录 Cookie',
              value: platform.hasCookie ? '已配置' : '未配置',
              state: platform.hasCookie,
            ),
            _CapabilityLine(
              icon: Icons.verified_rounded,
              label: '登录检测',
              value: platform.browserAuthValid == null
                  ? (browserAuthSupported ? '待检测' : '不支持')
                  : (platform.browserAuthValid! ? '有效' : '失效'),
              state: platform.browserAuthValid,
            ),
            _CapabilityLine(
              icon: Icons.bookmark_added_rounded,
              label: '收藏同步',
              value: platform.favoritesSupported
                  ? (platform.favoritesEnabled ? '已启用' : '未启用')
                  : '不支持',
              state: platform.favoritesSupported && platform.favoritesEnabled,
            ),
            if (platform.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                platform.issues.join('；'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: browserAuthSupported
                      ? () => _checkLogin(context, ref)
                      : null,
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('检测登录'),
                ),
                OutlinedButton.icon(
                  onPressed: browserAuthSupported
                      ? () => _openLoginDialog(context, ref)
                      : null,
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(platform.hasCookie ? '重新连接' : '连接'),
                ),
                if (platform.favoritesSupported)
                  FilledButton.tonalIcon(
                    onPressed: () => _previewFavoritesSync(context, ref),
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('预览同步'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkLogin(BuildContext context, WidgetRef ref) async {
    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post(
        '/browser-auth/${platform.platform}/check',
      );
      final ok = response.data['is_valid'] == true;
      ref.invalidate(platformHealthProvider);
      if (context.mounted) {
        Toast.show(context, ok ? '登录状态有效' : '登录状态不可用', isError: !ok);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(e, fallbackMessage: '检测登录失败'),
          isError: true,
        );
      }
    }
  }

  Future<void> _openLoginDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => InteractiveLoginDialog(
        platform: platform.platform,
        platformLabel: platform.label,
      ),
    );
    if (result == true) {
      ref.invalidate(platformHealthProvider);
      if (context.mounted) {
        Toast.show(context, '${platform.label} 已连接');
      }
    }
  }

  Future<void> _previewFavoritesSync(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final preview = await ref
          .read(favoritesSyncActionsProvider)
          .previewSync(platform: platform.platform);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _FavoritesPreviewDialog(preview: preview),
      );
    } catch (e) {
      if (context.mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(e, fallbackMessage: '预览同步失败'),
          isError: true,
        );
      }
    }
  }
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.state,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool? state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = state == null
        ? cs.onSurfaceVariant
        : state!
        ? cs.primary
        : cs.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _FavoritesPreviewDialog extends StatelessWidget {
  const _FavoritesPreviewDialog({required this.preview});

  final FavoritesSyncPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: Text('${_platformLabel(preview.platform)} 收藏同步预览'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PreviewChip(label: '拉取', value: preview.fetched),
                _PreviewChip(label: '预计新增', value: preview.estimatedNew),
                _PreviewChip(label: '已存在', value: preview.existing),
                _PreviewChip(label: '跳过', value: preview.skipped),
              ],
            ),
            const SizedBox(height: 16),
            ...preview.platforms.map((item) {
              final failed = item.status == 'failed';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  failed
                      ? '${_platformLabel(item.platform)}：${item.errorHint ?? item.error ?? '预览失败'}'
                      : '${_platformLabel(item.platform)}：新增 ${item.estimatedNew}，重复 ${item.existing}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: failed ? cs.error : cs.onSurface,
                  ),
                ),
              );
            }),
            Text(
              '预览不会导入内容或推进 cursor。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Chip(
      label: Text('$label $value'),
      side: BorderSide(color: cs.outlineVariant),
      backgroundColor: cs.surfaceContainerHighest,
      labelStyle: theme.textTheme.labelMedium,
    );
  }
}

class _RecentFavoritesRuns extends StatelessWidget {
  const _RecentFavoritesRuns({required this.runs});

  final List<Map<String, dynamic>> runs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近收藏同步',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...runs.take(5).map((run) {
          final status = run['status']?.toString() ?? 'unknown';
          final runId = run['run_id']?.toString() ?? '-';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              status == 'error'
                  ? Icons.error_outline_rounded
                  : Icons.task_alt_rounded,
              color: status == 'error'
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            title: Text('${_shortId(runId)} · ${run['scope'] ?? 'all'}'),
            subtitle: Text(
              '${_runLabel(status)} · ${run['started_at'] ?? '-'}',
            ),
          );
        }),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 44, color: cs.error),
          const SizedBox(height: 12),
          Text('账号健康状态加载失败：$error'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

Color _healthColor(BuildContext context, String health) {
  final cs = Theme.of(context).colorScheme;
  return switch (health) {
    'ok' => cs.primary,
    'error' => cs.error,
    'inactive' => cs.outline,
    _ => cs.onSurfaceVariant,
  };
}

String _healthLabel(String health) {
  return switch (health) {
    'ok' => '正常',
    'error' => '需处理',
    'inactive' => '未启用',
    _ => health,
  };
}

String _platformLabel(String platform) {
  return switch (platform) {
    'zhihu' => '知乎',
    'xiaohongshu' => '小红书',
    'twitter' => 'Twitter',
    'weibo' => '微博',
    'bilibili' => 'Bilibili',
    'all' => '全平台',
    _ => platform,
  };
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'zhihu' => Icons.question_answer_rounded,
    'xiaohongshu' => Icons.auto_awesome_rounded,
    'twitter' => Icons.alternate_email_rounded,
    'weibo' => Icons.public_rounded,
    'bilibili' => Icons.smart_display_rounded,
    _ => Icons.account_circle_rounded,
  };
}

String _runLabel(String status) {
  return switch (status) {
    'success' => '成功',
    'error' => '失败',
    'running' => '运行中',
    _ => status,
  };
}

String _shortId(String value) {
  return value.length > 8 ? value.substring(0, 8) : value;
}

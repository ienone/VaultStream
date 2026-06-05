import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../discovery/models/discovery_models.dart';
import '../../discovery/providers/discovery_sources_provider.dart';
import '../../settings/providers/platform_health_provider.dart';
import '../models/bot_chat.dart';
import '../providers/bot_chats_provider.dart';

class AutomationHealthMatrixPanel extends ConsumerWidget {
  const AutomationHealthMatrixPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platformAsync = ref.watch(platformHealthProvider);
    final sourcesAsync = ref.watch(discoverySourcesProvider);
    final chatsAsync = ref.watch(botChatsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(platformHealthProvider);
        ref.invalidate(discoverySourcesProvider);
        ref.invalidate(botChatsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _OverviewBand(
            platformAsync: platformAsync,
            sourcesAsync: sourcesAsync,
            chatsAsync: chatsAsync,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 980;
              final cards = [
                _HealthSection(
                  title: '平台账号',
                  icon: Icons.manage_accounts_rounded,
                  actionLabel: '账号中心',
                  onAction: () => context.push('/accounts'),
                  child: platformAsync.when(
                    data: (health) =>
                        _PlatformHealthList(platforms: health.platforms),
                    loading: () => const _SectionLoading(),
                    error: (error, _) => _SectionError(message: '$error'),
                  ),
                ),
                _HealthSection(
                  title: '发现源',
                  icon: Icons.sensors_rounded,
                  child: sourcesAsync.when(
                    data: (sources) =>
                        _DiscoverySourceHealthList(sources: sources),
                    loading: () => const _SectionLoading(),
                    error: (error, _) => _SectionError(message: '$error'),
                  ),
                ),
                _HealthSection(
                  title: '推送目标',
                  icon: Icons.outbox_rounded,
                  child: chatsAsync.when(
                    data: (chats) => _PushTargetHealthList(chats: chats),
                    loading: () => const _SectionLoading(),
                    error: (error, _) => _SectionError(message: '$error'),
                  ),
                ),
              ];

              if (!twoColumns) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: card,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OverviewBand extends StatelessWidget {
  const _OverviewBand({
    required this.platformAsync,
    required this.sourcesAsync,
    required this.chatsAsync,
  });

  final AsyncValue<PlatformHealthResponse> platformAsync;
  final AsyncValue<List<DiscoverySource>> sourcesAsync;
  final AsyncValue<List<BotChat>> chatsAsync;

  @override
  Widget build(BuildContext context) {
    final platformIssues =
        platformAsync.value?.platforms
            .where((platform) => platform.health == 'error')
            .length ??
        0;
    final sourceIssues =
        sourcesAsync.value
            ?.where((source) => source.enabled && source.lastError != null)
            .length ??
        0;
    final pushIssues =
        chatsAsync.value
            ?.where(
              (chat) =>
                  chat.isPushTarget &&
                  (!chat.enabled ||
                      !chat.isAccessible ||
                      chat.syncError != null),
            )
            .length ??
        0;
    final issueCount = platformIssues + sourceIssues + pushIssues;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: issueCount == 0
            ? cs.primaryContainer.withValues(alpha: 0.38)
            : cs.errorContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: issueCount == 0 ? cs.primaryContainer : cs.errorContainer,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              issueCount == 0
                  ? Icons.health_and_safety_rounded
                  : Icons.warning_amber_rounded,
              color: issueCount == 0 ? cs.primary : cs.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issueCount == 0 ? '自动化健康状态良好' : '自动化存在 $issueCount 个需处理项',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '覆盖平台账号、发现源和推送目标。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
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
}

class _HealthSection extends StatelessWidget {
  const _HealthSection({
    required this.title,
    required this.icon,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _PlatformHealthList extends ConsumerWidget {
  const _PlatformHealthList({required this.platforms});

  final List<PlatformHealthStatus> platforms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (platforms.isEmpty) return const _EmptyState(message: '暂无平台账号');
    return Column(
      children: [
        for (final platform in platforms.take(6))
          _HealthRow(
            icon: _platformIcon(platform.platform),
            title: platform.label,
            subtitle: platform.issues.isEmpty
                ? 'Cookie ${platform.hasCookie ? '已配置' : '未配置'} · 收藏同步 ${platform.favoritesEnabled ? '已启用' : '未启用'}'
                : platform.issues.join('；'),
            state: _platformState(platform),
            action: OutlinedButton.icon(
              onPressed: platform.auth['browser_auth_supported'] == true
                  ? () => _checkPlatformLogin(context, ref, platform)
                  : null,
              icon: const Icon(Icons.fact_check_rounded, size: 16),
              label: const Text('检测'),
            ),
          ),
      ],
    );
  }
}

class _DiscoverySourceHealthList extends ConsumerWidget {
  const _DiscoverySourceHealthList({required this.sources});

  final List<DiscoverySource> sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sources.isEmpty) return const _EmptyState(message: '暂无发现源');
    return Column(
      children: [
        for (final source in sources.take(6))
          _HealthRow(
            icon: _sourceIcon(source.kind),
            title: source.name,
            subtitle:
                source.lastError ??
                '${source.kind.toUpperCase()} · 每 ${source.syncIntervalMinutes} 分钟同步',
            state: source.lastError != null
                ? _HealthState.error
                : source.enabled
                ? _HealthState.ok
                : _HealthState.inactive,
            action: OutlinedButton.icon(
              onPressed: source.enabled
                  ? () => _syncDiscoverySource(context, ref, source)
                  : null,
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: const Text('同步'),
            ),
          ),
      ],
    );
  }
}

class _PushTargetHealthList extends ConsumerWidget {
  const _PushTargetHealthList({required this.chats});

  final List<BotChat> chats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = chats.where((chat) => chat.isPushTarget).toList();
    if (targets.isEmpty) return const _EmptyState(message: '暂无推送目标');
    return Column(
      children: [
        for (final chat in targets.take(6))
          _HealthRow(
            icon: _targetIcon(chat),
            title: chat.displayName,
            subtitle:
                chat.syncError ??
                '${chat.chatTypeLabel} · 已推送 ${chat.totalPushed}',
            state: !chat.enabled
                ? _HealthState.inactive
                : (!chat.isAccessible || chat.syncError != null)
                ? _HealthState.error
                : _HealthState.ok,
            action: OutlinedButton.icon(
              onPressed: () => _syncPushTarget(context, ref, chat),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('刷新'),
            ),
          ),
      ],
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _HealthState state;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _stateColor(context, state);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _stateLabel(state),
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      '加载失败: $message',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _HealthState { ok, inactive, error }

_HealthState _platformState(PlatformHealthStatus platform) {
  return switch (platform.health) {
    'ok' => _HealthState.ok,
    'inactive' => _HealthState.inactive,
    'error' => _HealthState.error,
    _ => platform.issues.isEmpty ? _HealthState.inactive : _HealthState.error,
  };
}

Color _stateColor(BuildContext context, _HealthState state) {
  final cs = Theme.of(context).colorScheme;
  return switch (state) {
    _HealthState.ok => cs.primary,
    _HealthState.inactive => cs.outline,
    _HealthState.error => cs.error,
  };
}

String _stateLabel(_HealthState state) {
  return switch (state) {
    _HealthState.ok => '正常',
    _HealthState.inactive => '未启用',
    _HealthState.error => '异常',
  };
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'zhihu' => Icons.question_answer_rounded,
    'xiaohongshu' => Icons.menu_book_rounded,
    'twitter' => Icons.alternate_email_rounded,
    'bilibili' => Icons.live_tv_rounded,
    _ => Icons.manage_accounts_rounded,
  };
}

IconData _sourceIcon(String kind) {
  return switch (kind) {
    'rss' => Icons.rss_feed_rounded,
    'telegram_channel' => Icons.telegram_rounded,
    _ => Icons.sensors_rounded,
  };
}

IconData _targetIcon(BotChat chat) {
  if (chat.isQQ) return Icons.chat_rounded;
  if (chat.isChannel) return Icons.campaign_rounded;
  return Icons.outbox_rounded;
}

Future<void> _checkPlatformLogin(
  BuildContext context,
  WidgetRef ref,
  PlatformHealthStatus platform,
) async {
  try {
    final response = await ref
        .read(apiClientProvider)
        .post('/browser-auth/${platform.platform}/check');
    ref.invalidate(platformHealthProvider);
    final ok = response.data is Map && response.data['is_valid'] == true;
    if (context.mounted) {
      Toast.show(
        context,
        ok ? '${platform.label} 登录有效' : '${platform.label} 登录不可用',
        isError: !ok,
      );
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

Future<void> _syncDiscoverySource(
  BuildContext context,
  WidgetRef ref,
  DiscoverySource source,
) async {
  try {
    final runId = await ref
        .read(discoverySourcesProvider.notifier)
        .triggerSync(source.id);
    if (context.mounted) {
      Toast.show(
        context,
        '已触发 ${source.name} 同步${runId == null ? '' : ' #${_shortId(runId)}'}',
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '发现源同步失败'),
        isError: true,
      );
    }
  }
}

Future<void> _syncPushTarget(
  BuildContext context,
  WidgetRef ref,
  BotChat chat,
) async {
  try {
    await ref.read(botChatsProvider.notifier).syncChats(chatId: chat.chatId);
    if (context.mounted) {
      Toast.show(context, '已刷新 ${chat.displayName}');
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '推送目标刷新失败'),
        isError: true,
      );
    }
  }
}

String _shortId(String runId) =>
    runId.length > 8 ? runId.substring(0, 8) : runId;

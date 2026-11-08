import '../../core/layout/app_page_body.dart';
import '../settings/presentation/tabs/push_tab.dart';
import '../automation/widgets/favorites_sync_automation_panel.dart';
import '../settings/providers/favorites_sync_provider.dart';
import 'telegram_account_page.dart';
import '../../routing/app_navigation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/metadata_wrap.dart';

import '../../core/utils/toast.dart';
import '../../theme/design_tokens.dart';
import '../settings/presentation/tabs/connection_tab.dart';
import '../settings/providers/platform_auth_controller.dart';
import '../settings/providers/platform_health_provider.dart';

class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({
    super.key,
    required this.platform,
    this.onClose,
    this.showBackButton = true,
  });

  final VoidCallback? onClose;
  final bool showBackButton;

  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (platform == 'telegram') {
      return TelegramAccountPage(
        onClose: onClose,
        showBackButton: showBackButton,
      );
    }
    if (platform == 'qq') {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: !showBackButton
              ? null
              : onClose == null
              ? const AppBackButton(fallback: '/accounts')
              : BackButton(onPressed: onClose),
          title: const Text('QQ'),
        ),
        body: AppPageBody(
          maxWidth: 720,
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: PushTab(platform: 'qq'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class AccountPlatformPanel extends ConsumerWidget {
  const AccountPlatformPanel({super.key, required this.account});

  final PlatformHealthStatus account;

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => account.platform == 'twitter'
          ? const XSessionCookieDialog()
          : PlatformLoginDialog(
              platform: account.platform,
              label: account.label,
            ),
    );
    if (success == true && context.mounted) {
      ref.read(platformAuthActionsProvider.notifier).refreshHealth();
      Toast.show(context, '${account.label} 登录已更新');
    }
  }

  Future<void> _check(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(platformAuthActionsProvider.notifier)
          .check(account.platform);
      if (context.mounted) Toast.show(context, result.message);
    } on PlatformAuthException catch (error) {
      if (context.mounted) Toast.show(context, error.message, isError: true);
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (dialogContext) => AlertDialog(
        title: Text('清除 ${account.label} 登录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await ref
          .read(platformAuthActionsProvider.notifier)
          .logout(account.platform);
      if (context.mounted) Toast.show(context, result.message);
    } on PlatformAuthException catch (error) {
      if (context.mounted) Toast.show(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    container: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: _AccountOverview(
        account: account,
        controls: _AccountControls(
          account: account,
          onLogin: () => _login(context, ref),
          onCheck: () => _check(context, ref),
          onLogout: () => _logout(context, ref),
        ),
      ),
    ),
  );
}

class _AccountOverview extends ConsumerWidget {
  const _AccountOverview({required this.account, required this.controls});

  final Widget controls;

  final PlatformHealthStatus account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _accountStatus(account);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.start,
          spacing: AppSpacing.md,
          overflowSpacing: AppSpacing.sm,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(status.icon, size: 20, color: status.color(scheme)),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.label, style: theme.textTheme.titleMedium),
                    if (account.hasCookie || account.health == 'error')
                      Text(
                        status.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            controls,
          ],
        ),
        if (account.issues.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final issue in account.issues)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(issue, style: theme.textTheme.bodyMedium),
            ),
        ],
        if (account.hasCookie && account.favoritesSupported) ...[
          const SizedBox(height: AppSpacing.lg),
          ref
              .watch(favoritesSyncStatusProvider)
              .when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => TextButton(
                  onPressed: () => ref.invalidate(favoritesSyncStatusProvider),
                  child: const Text('同步设置读取失败，重试'),
                ),
                data: (data) {
                  final sync = data.platforms
                      .where((s) => s.platform == account.platform)
                      .firstOrNull;
                  return sync == null
                      ? const SizedBox.shrink()
                      : AccountFavoritesSyncControls(
                          status: sync,
                          loginAvailable:
                              account.hasCookie &&
                              account.browserAuthValid != false,
                        );
                },
              ),
        ],
        if (account.platform == 'bilibili')
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('手动凭据'),
            children: [
              const ConnectionTab().buildBiliAdvancedEditor(context, ref),
            ],
          ),
        if (account.lastFavoritesRun != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _LastSyncCard(
            run: account.lastFavoritesRun!,
            status: account.lastFavoritesStatus ?? 'unknown',
          ),
        ],
      ],
    );
  }
}

class _AccountControls extends ConsumerWidget {
  const _AccountControls({
    required this.account,
    required this.onLogin,
    required this.onCheck,
    required this.onLogout,
  });

  final PlatformHealthStatus account;
  final VoidCallback onLogin;
  final VoidCallback onCheck;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(platformAuthActionsProvider);
    final busy = pending.any((key) => key.startsWith('${account.platform}:'));
    final canLogin =
        account.browserAuthSupported || account.platform == 'twitter';
    final connected = account.hasCookie && account.browserAuthValid == true;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (canLogin && !connected)
          FilledButton.tonalIcon(
            onPressed: busy ? null : onLogin,
            icon: Icon(
              account.platform == 'twitter'
                  ? Icons.key_rounded
                  : Icons.qr_code_2_rounded,
            ),
            label: Text(
              !account.hasCookie
                  ? '连接账号'
                  : account.browserAuthValid == false
                  ? '重新登录'
                  : '更新登录',
            ),
          ),
        if (account.hasCookie)
          PopupMenuButton<String>(
            tooltip: '账号操作',
            enabled: !busy,
            onSelected: (value) {
              switch (value) {
                case 'login':
                  onLogin();
                case 'check':
                  onCheck();
                case 'logout':
                  onLogout();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '账号操作',
                    style: TextStyle(
                      color: busy
                          ? Theme.of(context).disabledColor
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
            itemBuilder: (_) => [
              if (canLogin && connected)
                const PopupMenuItem(value: 'login', child: Text('更新登录')),
              if (canLogin)
                const PopupMenuItem(value: 'check', child: Text('检测有效性')),
              const PopupMenuItem(value: 'logout', child: Text('清除登录')),
            ],
          ),
      ],
    );
  }
}

class _LastSyncCard extends StatelessWidget {
  const _LastSyncCard({required this.run, required this.status});

  final Map<String, dynamic> run;
  final String status;

  @override
  Widget build(BuildContext context) {
    final runId = run['run_id']?.toString();
    final startedAt = DateTime.tryParse(run['started_at']?.toString() ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: AppShape.cardMediaBorder,
      ),
      title: const Text('最近收藏同步'),
      subtitle: MetadataWrap(
        items: [
          _runStatus(status),
          if (startedAt != null) _formatDate(startedAt),
        ],
      ),
      trailing: runId == null || runId.isEmpty
          ? null
          : const Icon(Icons.chevron_right_rounded),
      onTap: runId == null || runId.isEmpty
          ? null
          : () => context.push('/tasks/${Uri.encodeComponent(runId)}'),
    );
  }
}

({String label, IconData icon, Color Function(ColorScheme) color})
_accountStatus(PlatformHealthStatus account) {
  if (account.browserAuthValid == false || account.health == 'error') {
    return (
      label: account.browserAuthValid == false ? '登录失效' : '账号异常',
      icon: Icons.error_outline_rounded,
      color: (scheme) => scheme.error,
    );
  }
  if (!account.hasCookie) {
    return (
      label: '未连接',
      icon: Icons.account_circle_outlined,
      color: (scheme) => scheme.outline,
    );
  }
  return (
    label: account.browserAuthValid == true ? '已连接' : '登录待检查',
    icon: Icons.verified_user_outlined,
    color: (scheme) => scheme.primary,
  );
}

String _runStatus(String status) => switch (status) {
  'success' || 'ok' => '成功',
  'error' || 'failed' => '失败',
  'partial_success' => '部分失败',
  'skipped' => '已跳过',
  'unknown' => '状态未知',
  'running' => '运行中',
  _ => status,
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

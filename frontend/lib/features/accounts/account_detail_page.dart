import '../../core/layout/app_list_detail_workspace.dart';
import '../../core/layout/app_page_body.dart';
import '../settings/presentation/tabs/push_tab.dart';
import 'telegram_account_page.dart';
import '../../routing/app_navigation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/toast.dart';
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
    final accounts = ref.watch(platformHealthProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBackButton
            ? BackButton(onPressed: onClose ?? () => context.go('/accounts'))
            : null,
        title: Text(
          accounts.value?.platforms
                  .where((item) => item.platform == platform)
                  .firstOrNull
                  ?.label ??
              '账号',
        ),
      ),
      body: accounts.when(
        loading: () => const WorkspacePlaceholder(loading: true, label: ''),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(platformHealthProvider),
            child: const Text('重新加载'),
          ),
        ),
        data: (value) {
          final account = value.platforms
              .where((item) => item.platform == platform)
              .firstOrNull;
          return account == null
              ? const Center(child: Text('账号不存在'))
              : AppPageBody(
                  maxWidth: 720,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [AccountPlatformPanel(account: account)],
                  ),
                );
        },
      ),
    );
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
      if (context.mounted) Toast.show(context, result);
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
      if (context.mounted) Toast.show(context, result);
    } on PlatformAuthException catch (error) {
      if (context.mounted) Toast.show(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = _accountStatus(account);
    final busy = ref
        .watch(platformAuthActionsProvider)
        .any((key) => key.startsWith('${account.platform}:'));
    final canLogin =
        account.browserAuthSupported || account.platform == 'twitter';
    return ListTile(
      leading: Icon(
        status.icon,
        color: status.color(Theme.of(context).colorScheme),
      ),
      title: Text(account.label),
      subtitle: Text(status.label),
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canLogin && (!account.hasCookie || account.login == 'invalid'))
            TextButton(
              onPressed: busy ? null : () => _login(context, ref),
              child: Text(account.hasCookie ? '重新登录' : '连接'),
            ),
          PopupMenuButton<String>(
            tooltip: '${account.label}操作',
            enabled: !busy,
            onSelected: (action) async {
              switch (action) {
                case 'login':
                  await _login(context, ref);
                case 'check':
                  await _check(context, ref);
                case 'logout':
                  await _logout(context, ref);
                case 'sync':
                  context.push('/sources/sync?platform=${account.platform}');
                case 'cookie':
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('手动登录哔哩哔哩'),
                      content: const ConnectionTab().buildBiliAdvancedEditor(
                        context,
                        ref,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              if (account.favoritesSupported)
                const PopupMenuItem(value: 'sync', child: Text('收藏同步')),
              if (account.hasCookie)
                const PopupMenuItem(value: 'check', child: Text('检查登录状态')),
              if (canLogin && account.hasCookie)
                const PopupMenuItem(value: 'login', child: Text('更新登录')),
              if (account.platform == 'bilibili')
                const PopupMenuItem(
                  value: 'cookie',
                  child: Text('使用 Cookie 登录'),
                ),
              if (account.hasCookie)
                const PopupMenuItem(value: 'logout', child: Text('清除登录')),
            ],
          ),
        ],
      ),
    );
  }
}

({String label, IconData icon, Color Function(ColorScheme) color})
_accountStatus(PlatformHealthStatus account) {
  if (account.login == 'invalid') {
    return (
      label: '登录失效',
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
    label: '已配置登录',
    icon: Icons.verified_user_outlined,
    color: (scheme) => scheme.primary,
  );
}

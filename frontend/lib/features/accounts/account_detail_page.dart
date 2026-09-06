import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/toast.dart';
import '../../theme/design_tokens.dart';
import '../settings/presentation/tabs/connection_tab.dart';
import '../settings/providers/platform_auth_controller.dart';
import '../settings/providers/platform_health_provider.dart';

class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(platformHealthProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          health.maybeWhen(
            data: (data) => _findPlatform(data, platform)?.label ?? '平台账号详情',
            orElse: () => '平台账号详情',
          ),
        ),
        actions: [
          IconButton(
            tooltip: '刷新账号状态',
            onPressed: () => ref.invalidate(platformHealthProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: health.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _AccountDetailError(error: error),
        data: (data) {
          final account = _findPlatform(data, platform);
          if (account == null) {
            return const _UnknownAccount();
          }
          return _AccountDetailBody(account: account);
        },
      ),
    );
  }
}

PlatformHealthStatus? _findPlatform(
  PlatformHealthResponse response,
  String platform,
) {
  for (final item in response.platforms) {
    if (item.platform == platform) return item;
  }
  return null;
}

class _AccountDetailBody extends ConsumerWidget {
  const _AccountDetailBody({required this.account});

  final PlatformHealthStatus account;

  Future<void> _login(BuildContext context, WidgetRef ref) async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          PlatformLoginDialog(platform: account.platform, label: account.label),
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
      builder: (dialogContext) => AlertDialog(
        title: Text('清除 ${account.label} 登录'),
        content: const Text('只清除 VaultStream 保存的登录信息，不会修改平台账号本身。'),
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
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = WindowMetrics.fromSize(
        Size(constraints.maxWidth, constraints.maxHeight),
      );
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: EdgeInsets.all(
              metrics.isCompact ? AppSpacing.md : AppSpacing.xl,
            ),
            children: [
              _AccountOverview(
                account: account,
                controls: _AccountControls(
                  account: account,
                  onLogin: () => _login(context, ref),
                  onCheck: () => _check(context, ref),
                  onLogout: () => _logout(context, ref),
                ),
              ),
              if (account.issues.isNotEmpty)
                ExpansionTile(
                  title: const Text('如何修复'),
                  children: [_RepairGuide(account: account)],
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _AccountOverview extends StatelessWidget {
  const _AccountOverview({required this.account, required this.controls});

  final Widget controls;

  final PlatformHealthStatus account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _accountStatus(account);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: status.color(scheme).withValues(alpha: 0.12),
            borderRadius: AppShape.paneBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.label, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(status.label, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                status.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        controls,
        const SizedBox(height: AppSpacing.lg),
        Text('能力与状态', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Column(
          children: [
            _CapabilityRow(
              title: '本地登录信息',
              value: account.hasCookie ? '已保存' : '未保存',
            ),
            _CapabilityRow(
              title: '浏览器登录',
              value: account.browserAuthSupported ? '支持' : '不支持',
            ),
            _CapabilityRow(title: '收藏同步', value: _favoritesCapability(account)),
            _CapabilityRow(
              title: '同步认证',
              value: _optionalValidity(account.favoritesAuthenticated),
            ),
          ],
        ),
        if (account.issues.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('当前问题', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final issue in account.issues)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.error_outline_rounded, color: scheme.error),
              title: Text(issue),
            ),
        ],
        if (account.lastFavoritesRun != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _LastSyncCard(run: account.lastFavoritesRun!),
        ],
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (account.browserAuthSupported)
              FilledButton.tonalIcon(
                onPressed: busy ? null : onLogin,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(
                  !account.hasCookie
                      ? '连接账号'
                      : account.browserAuthValid == false
                      ? '重新登录'
                      : '更新登录',
                ),
              ),
            if (account.hasCookie && account.browserAuthSupported)
              OutlinedButton.icon(
                onPressed: busy ? null : onCheck,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('检测有效性'),
              ),
            if (account.hasCookie)
              TextButton.icon(
                onPressed: busy ? null : onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('清除登录'),
              ),
            if (account.favoritesSupported)
              TextButton.icon(
                onPressed: () => context.push('/automation/sync'),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('管理收藏同步'),
              ),
          ],
        ),
      ],
    );
  }
}

class _RepairGuide extends StatelessWidget {
  const _RepairGuide({required this.account});

  final PlatformHealthStatus account;

  @override
  Widget build(BuildContext context) {
    final steps = _repairSteps(account);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (steps.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline_rounded),
            title: Text('账号状态可用'),
          )
        else
          for (var index = 0; index < steps.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${index + 1}')),
              title: Text(steps[index]),
            ),
      ],
    );
  }
}

class _LastSyncCard extends StatelessWidget {
  const _LastSyncCard({required this.run});

  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    final runId = run['run_id']?.toString();
    final status = run['status']?.toString() ?? 'unknown';
    final startedAt = DateTime.tryParse(run['started_at']?.toString() ?? '');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          status == 'success'
              ? Icons.check_circle_outline_rounded
              : status == 'error'
              ? Icons.error_outline_rounded
              : Icons.schedule_rounded,
        ),
        title: const Text('最近收藏同步'),
        subtitle: Text(
          '${_runStatus(status)}${startedAt == null ? '' : ' · ${_formatDate(startedAt)}'}',
        ),
        trailing: runId == null || runId.isEmpty
            ? null
            : const Icon(Icons.chevron_right_rounded),
        onTap: runId == null || runId.isEmpty
            ? null
            : () => context.push('/tasks/${Uri.encodeComponent(runId)}'),
      ),
    );
  }
}

class _AccountDetailError extends ConsumerWidget {
  const _AccountDetailError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text(
            formatApiErrorMessage(error, fallbackMessage: '无法读取平台账号'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonal(
            onPressed: () => ref.invalidate(platformHealthProvider),
            child: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

class _UnknownAccount extends StatelessWidget {
  const _UnknownAccount();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_circle_outlined, size: 48),
          SizedBox(height: AppSpacing.md),
          Text('服务器没有返回这个平台账号'),
        ],
      ),
    ),
  );
}

({
  String label,
  String description,
  IconData icon,
  Color Function(ColorScheme) color,
})
_accountStatus(PlatformHealthStatus account) {
  if (account.browserAuthValid == false || account.health == 'error') {
    return (
      label: '需要处理',
      description: account.issues.isEmpty ? '账号检查返回异常。' : account.issues.first,
      icon: Icons.error_outline_rounded,
      color: (scheme) => scheme.error,
    );
  }
  if (!account.hasCookie) {
    return (
      label: '尚未连接',
      description: account.browserAuthSupported
          ? '点击“连接账号”登录。'
          : '该平台需要通过手动配置提供登录信息。',
      icon: Icons.account_circle_outlined,
      color: (scheme) => scheme.outline,
    );
  }
  return (
    label: '已连接',
    description: account.browserAuthValid == true
        ? '最近一次登录有效性检查通过。'
        : 'VaultStream 已保存登录信息，尚无最近有效性结论。',
    icon: Icons.verified_user_outlined,
    color: (scheme) => scheme.primary,
  );
}

String _favoritesCapability(PlatformHealthStatus account) {
  if (!account.favoritesSupported) return '不支持';
  if (account.favoritesSync['available'] == false) return '当前不可用';
  return account.favoritesEnabled ? '已启用' : '未启用';
}

String _optionalValidity(bool? value) => switch (value) {
  true => '有效',
  false => '无效',
  null => '未检查',
};

List<String> _repairSteps(PlatformHealthStatus account) {
  final steps = <String>[];
  if (!account.hasCookie) {
    steps.add(
      account.browserAuthSupported
          ? '使用“连接账号”完成平台扫码登录。'
          : '返回账号中心，在该平台的手动凭据区域完成配置。',
    );
  } else if (account.browserAuthValid == false) {
    steps.add('使用“重新登录”更新失效的登录信息。');
  }
  if (account.hasCookie && account.browserAuthSupported) {
    steps.add('点击“检测有效性”检查登录状态。');
  }
  if (account.favoritesSupported && !account.favoritesEnabled) {
    steps.add('进入收藏同步设置，仅在需要时启用该平台。');
  } else if (account.favoritesAuthenticated == false) {
    steps.add('登录恢复后再次运行收藏同步认证检查。');
  }
  return steps;
}

String _runStatus(String status) => switch (status) {
  'success' || 'ok' => '成功',
  'error' => '失败',
  'running' => '运行中',
  _ => status,
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

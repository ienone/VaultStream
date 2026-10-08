import '../settings/presentation/tabs/push_tab.dart';
import 'telegram_login_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/toast.dart';
import '../../routing/app_navigation.dart';
import '../../theme/design_tokens.dart';

class TelegramAccountStatus {
  TelegramAccountStatus.fromJson(Map<String, dynamic> json)
    : configured = json['configured'] as bool,
      sessionPresent = json['session_present'] as bool,
      running = json['running'] as bool,
      channelsEnabled = json['channels_enabled'] as bool,
      savedEnabled = json['saved_enabled'] as bool;

  final bool configured, sessionPresent, running, channelsEnabled, savedEnabled;
}

final telegramAccountProvider = FutureProvider.autoDispose((ref) async {
  final response = await ref
      .watch(apiClientProvider)
      .get('/telegram-account/status');
  return TelegramAccountStatus.fromJson(response.data as Map<String, dynamic>);
});

class TelegramAccountPage extends ConsumerStatefulWidget {
  const TelegramAccountPage({super.key});

  @override
  ConsumerState<TelegramAccountPage> createState() =>
      _TelegramAccountPageState();
}

class _TelegramAccountPageState extends ConsumerState<TelegramAccountPage> {
  bool _busy = false;

  Future<void> _update(
    TelegramAccountStatus status, {
    bool? channels,
    bool? saved,
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/telegram-account/options',
            data: {
              'channels_enabled': channels ?? status.channelsEnabled,
              'saved_enabled': saved ?? status.savedEnabled,
            },
          );
      if (!mounted) return;
      ref.invalidate(telegramAccountProvider);
      await ref.read(telegramAccountProvider.future);
    } catch (error) {
      if (mounted) {
        Toast.show(context, formatApiErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => TelegramLoginDialog(client: ref.read(apiClientProvider)),
    );
    if (mounted) ref.invalidate(telegramAccountProvider);
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .post('/telegram-account/sync');
      final runId = (response.data as Map<String, dynamic>)['run_id'] as String;
      ref.invalidate(telegramAccountProvider);
      if (mounted) await context.push('/tasks/${Uri.encodeComponent(runId)}');
      if (mounted) ref.invalidate(telegramAccountProvider);
    } catch (error) {
      if (mounted) {
        Toast.show(context, formatApiErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(telegramAccountProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/accounts'),
        title: const Text('Telegram'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy
                ? null
                : () => ref.invalidate(telegramAccountProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
          child: status.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(telegramAccountProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ),
            data: (account) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('个人账号', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(
                  !account.configured
                      ? '尚未配置 Telegram 应用凭据'
                      : account.sessionPresent
                      ? '已保存登录会话'
                      : '尚未连接',
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final buttons = [
                      OutlinedButton.icon(
                        onPressed:
                            _busy || account.running || !account.configured
                            ? null
                            : _login,
                        icon: const Icon(Icons.login_rounded),
                        label: Text(account.sessionPresent ? '重新连接' : '连接账号'),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                account.running ||
                                !account.configured ||
                                !account.sessionPresent ||
                                !(account.channelsEnabled ||
                                    account.savedEnabled)
                            ? null
                            : _sync,
                        icon: const Icon(Icons.sync_rounded),
                        label: Text(account.running ? '正在同步' : '立即同步'),
                      ),
                    ];
                    if (constraints.maxWidth <
                        320 * MediaQuery.textScalerOf(context).scale(1)) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          buttons[0],
                          const SizedBox(height: 8),
                          buttons[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: buttons[0]),
                        const SizedBox(width: 12),
                        Expanded(child: buttons[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('频道动态'),
                  subtitle: const Text('同步已加入且开启通知的频道'),
                  value: account.channelsEnabled,
                  onChanged: _busy
                      ? null
                      : (value) => _update(account, channels: value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('收藏夹'),
                  subtitle: const Text('将 Saved Messages 保存到收藏库'),
                  value: account.savedEnabled,
                  onChanged: _busy
                      ? null
                      : (value) => _update(account, saved: value),
                ),
                const SizedBox(height: 28),
                const PushTab(platform: 'telegram'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

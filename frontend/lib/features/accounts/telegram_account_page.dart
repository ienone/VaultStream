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
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('频道动态'),
                  subtitle: const Text('同步已加入且开启通知的频道'),
                  value: account.channelsEnabled,
                  onChanged: _busy
                      ? null
                      : (value) => _update(account, channels: value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('收藏夹'),
                  subtitle: const Text('将 Saved Messages 保存到收藏库'),
                  value: account.savedEnabled,
                  onChanged: _busy
                      ? null
                      : (value) => _update(account, saved: value),
                ),
                const SizedBox(height: 24),
                if (!account.configured || !account.sessionPresent)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('连接 Telegram 账号后即可同步。'),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed:
                        _busy ||
                            account.running ||
                            !account.configured ||
                            !account.sessionPresent ||
                            !(account.channelsEnabled || account.savedEnabled)
                        ? null
                        : _sync,
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(account.running ? '正在同步' : '立即同步'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

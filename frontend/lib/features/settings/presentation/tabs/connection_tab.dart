import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/local_settings_provider.dart';
import '../../../../core/utils/safe_url_launcher.dart';
import '../../providers/settings_provider.dart';
import '../../providers/platform_auth_controller.dart';
import '../../providers/platform_health_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';

class ConnectionTab extends ConsumerWidget {
  const ConnectionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localSettings = ref.watch(localSettingsProvider);
    final platformHealthAsync = ref.watch(platformHealthProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        const SectionHeader(title: '服务器与通信', icon: Icons.lan_rounded),
        SettingGroup(
          children: [
            ExpandableSettingTile(
              title: '后端 API 地址',
              subtitle: localSettings.baseUrl,
              icon: Icons.cloud_done_rounded,
              expandedContent: _buildBaseUrlEditor(
                context,
                ref,
                localSettings.baseUrl,
              ),
            ),
            ExpandableSettingTile(
              title: 'API 访问密钥',
              subtitle: _maskToken(localSettings.apiToken),
              icon: Icons.key_rounded,
              expandedContent: _buildApiTokenEditor(
                context,
                ref,
                localSettings.apiToken,
              ),
            ),
            SettingTile(
              title: '测试服务器连接',
              subtitle: '验证后端服务可用性',
              icon: Icons.cell_tower_rounded,
              onTap: () => _testConnection(
                context,
                ref,
                localSettings.baseUrl,
                localSettings.apiToken,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const SectionHeader(title: '账号与平台健康', icon: Icons.link_rounded),
        const SizedBox(height: 12),
        _buildPlatformHealthSection(context, ref, platformHealthAsync),
        const SizedBox(height: 32),
        const SectionHeader(title: '高级连接设置', icon: Icons.tune_rounded),
        SettingGroup(
          children: [
            ExpandableSettingTile(
              title: '网络代理配置',
              subtitle: _getProxySubtitle(ref),
              icon: Icons.lan_rounded,
              expandedContent: _buildProxyEditor(context, ref),
            ),
            ExpandableSettingTile(
              title: 'Bilibili 高级配置',
              subtitle: '配置 SESSDATA / JCT / BuVid3',
              icon: Icons.settings_ethernet_rounded,
              expandedContent: _buildBiliAdvancedEditor(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingGroup(
          children: [
            SettingTile(
              title: '退出登录',
              subtitle: '清除本地认证并注销',
              icon: Icons.logout_rounded,
              iconColor: colorScheme.error,
              onTap: () => _confirmLogout(context, ref),
              showArrow: false,
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPlatformHealthSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<PlatformHealthResponse> healthAsync,
  ) {
    return healthAsync.when(
      data: (health) {
        if (health.platforms.isEmpty) {
          return const SizedBox.shrink();
        }
        return SettingGroup(
          children: [
            for (final platform in health.platforms)
              SettingTile(
                title: platform.label,
                subtitle: _platformHealthSubtitle(platform),
                icon: _platformHealthIcon(platform),
                iconColor: _platformHealthColor(context, platform),
                trailing: _PlatformAccountActions(
                  platform: platform,
                  onLogin: () => _startPlatformLogin(context, ref, platform),
                  onCheck: () => _checkPlatform(context, ref, platform),
                  onLogout: () =>
                      _confirmPlatformLogout(context, ref, platform),
                ),
                showArrow: false,
              ),
          ],
        );
      },
      loading: () => const LoadingGroup(),
      error: (error, _) => SettingGroup(
        children: [
          SettingTile(
            title: '平台健康状态',
            subtitle: '加载失败，点击重试',
            icon: Icons.error_outline_rounded,
            iconColor: Theme.of(context).colorScheme.error,
            trailing: IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(platformHealthProvider),
            ),
            showArrow: false,
          ),
        ],
      ),
    );
  }

  String _platformHealthSubtitle(PlatformHealthStatus platform) {
    final parts = <String>[];
    if (platform.hasCookie) {
      parts.add(platform.browserAuthValid == false ? '登录失效' : '已配置登录');
    } else {
      parts.add('未配置登录');
    }
    if (platform.favoritesSupported) {
      if (platform.favoritesEnabled) {
        parts.add(
          platform.favoritesAuthenticated == false ? '同步认证失败' : '收藏同步已启用',
        );
      } else {
        parts.add('收藏同步未启用');
      }
    }
    final lastRun = platform.lastFavoritesRun;
    if (lastRun != null) {
      final status = lastRun['status']?.toString() ?? 'unknown';
      parts.add('最近同步: ${_platformHealthLabel(status)}');
    }
    if (platform.issues.isNotEmpty) {
      parts.add(platform.issues.first);
    }
    return parts.join(' · ');
  }

  String _platformHealthLabel(String status) {
    switch (status) {
      case 'ok':
      case 'success':
        return '正常';
      case 'error':
        return '异常';
      case 'inactive':
        return '未启用';
      case 'running':
        return '运行中';
      default:
        return status;
    }
  }

  IconData _platformHealthIcon(PlatformHealthStatus platform) {
    switch (platform.health) {
      case 'ok':
        return Icons.verified_user_rounded;
      case 'error':
        return Icons.report_gmailerrorred_rounded;
      case 'inactive':
        return Icons.account_circle_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color? _platformHealthColor(
    BuildContext context,
    PlatformHealthStatus platform,
  ) {
    final colors = Theme.of(context).colorScheme;
    switch (platform.health) {
      case 'ok':
        return colors.primary;
      case 'error':
        return colors.error;
      case 'inactive':
        return colors.outline;
      default:
        return null;
    }
  }

  Future<void> _startPlatformLogin(
    BuildContext context,
    WidgetRef ref,
    PlatformHealthStatus platform,
  ) async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlatformLoginDialog(
        platform: platform.platform,
        label: platform.label,
      ),
    );
    if (success == true && context.mounted) {
      ref.read(platformAuthActionsProvider.notifier).refreshHealth();
      showToast(context, '${platform.label} 登录已更新');
    }
  }

  Future<void> _checkPlatform(
    BuildContext context,
    WidgetRef ref,
    PlatformHealthStatus platform,
  ) async {
    try {
      final result = await ref
          .read(platformAuthActionsProvider.notifier)
          .check(platform.platform);
      if (context.mounted) showToast(context, result.message);
    } on PlatformAuthException catch (error) {
      if (context.mounted) showToast(context, error.message);
    }
  }

  Future<void> _confirmPlatformLogout(
    BuildContext context,
    WidgetRef ref,
    PlatformHealthStatus platform,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('退出 ${platform.label}'),
        content: const Text('将清除 VaultStream 保存的该平台登录信息；不会修改平台账号本身。'),
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
          .logout(platform.platform);
      if (context.mounted) showToast(context, result.message);
    } on PlatformAuthException catch (error) {
      if (context.mounted) showToast(context, error.message);
    }
  }

  Widget _buildBaseUrlEditor(
    BuildContext context,
    WidgetRef ref,
    String currentValue,
  ) {
    final controller = TextEditingController(text: currentValue);
    return Column(
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'http://example.com/api/v1',
            prefixIcon: const Icon(Icons.link_rounded),
            filled: true,
            fillColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref
                  .read(localSettingsProvider.notifier)
                  .setBaseUrl(controller.text);
              if (context.mounted) {
                showToast(context, 'API 地址已保存');
              }
            },
            child: const Text('保存配置'),
          ),
        ),
      ],
    );
  }

  Widget _buildApiTokenEditor(
    BuildContext context,
    WidgetRef ref,
    String currentValue,
  ) {
    final controller = TextEditingController(text: currentValue);
    return Column(
      children: [
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'API Token',
            prefixIcon: const Icon(Icons.password_rounded),
            filled: true,
            fillColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref
                  .read(localSettingsProvider.notifier)
                  .setApiToken(controller.text);
              if (context.mounted) {
                showToast(context, '密钥已更新');
              }
            },
            child: const Text('更新密钥'),
          ),
        ),
      ],
    );
  }

  String _maskToken(String token) {
    if (token.isEmpty) return '未配置';
    if (token.length <= 8) return '********';
    return '${token.substring(0, 4)}****${token.substring(token.length - 4)}';
  }

  String _getProxySubtitle(WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.maybeWhen(
      data: (settings) {
        final proxy =
            settings
                    .firstWhere(
                      (s) => s.key == 'http_proxy',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        return proxy.isNotEmpty ? proxy : '未配置';
      },
      orElse: () => '加载中...',
    );
  }

  Widget _buildProxyEditor(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final proxy =
            settings
                    .firstWhere(
                      (s) => s.key == 'http_proxy',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final controller = TextEditingController(text: proxy);

        return Column(
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'HTTP/HTTPS Proxy',
                hintText: 'e.g. http://127.0.0.1:7890',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  await ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'http_proxy',
                        controller.text,
                        category: 'network',
                      );
                  if (context.mounted) showToast(context, '代理已保存');
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildBiliAdvancedEditor(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final sessdata =
            settings
                    .firstWhere(
                      (s) => s.key == 'bilibili_cookie',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final jct =
            settings
                    .firstWhere(
                      (s) => s.key == 'bilibili_bili_jct',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final buvid =
            settings
                    .firstWhere(
                      (s) => s.key == 'bilibili_buvid3',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';

        final sessController = TextEditingController(text: sessdata);
        final jctController = TextEditingController(text: jct);
        final buvidController = TextEditingController(text: buvid);

        return Column(
          children: [
            TextField(
              controller: sessController,
              decoration: InputDecoration(
                labelText: 'SESSDATA (Cookie)',
                helperText: '一般情况下无需配置，仅用于高画质/会员内容',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: jctController,
              decoration: InputDecoration(
                labelText: 'bili_jct (CSRF)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: buvidController,
              decoration: InputDecoration(
                labelText: 'buvid3',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () async {
                  final notifier = ref.read(systemSettingsProvider.notifier);
                  await notifier.updateSetting(
                    'bilibili_cookie',
                    sessController.text,
                    category: 'platform',
                  );
                  await notifier.updateSetting(
                    'bilibili_bili_jct',
                    jctController.text,
                    category: 'platform',
                  );
                  await notifier.updateSetting(
                    'bilibili_buvid3',
                    buvidController.text,
                    category: 'platform',
                  );
                  if (context.mounted) showToast(context, 'B站高级配置已保存');
                },
                child: const Text('保存配置'),
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    WidgetRef ref,
    String baseUrl,
    String apiToken,
  ) async {
    showToast(context, '正在测试连接...');
    try {
      final result = await ref
          .read(localSettingsProvider.notifier)
          .validateConnection(baseUrl, apiToken);
      if (context.mounted) {
        if (result['success'] == true) {
          final authOk = result['auth_ok'] == true;
          showToast(context, authOk ? '✅ 连接并认证成功' : '⚠️ 连接成功，但 API 密钥无效');
        } else {
          showToast(context, '❌ ${result['error']}');
        }
      }
    } catch (e) {
      if (context.mounted) showToast(context, '❌ 错误: $e');
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('注销后将清除本地 API 密钥，需重新配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(localSettingsProvider.notifier).clearAuth();
              if (context.mounted) {
                context.go('/login');
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showToast(context, '已成功退出');
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

class _PlatformAccountActions extends ConsumerWidget {
  const _PlatformAccountActions({
    required this.platform,
    required this.onLogin,
    required this.onCheck,
    required this.onLogout,
  });

  final PlatformHealthStatus platform;
  final VoidCallback onLogin;
  final VoidCallback onCheck;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!platform.browserAuthSupported) {
      return const Chip(label: Text('手动配置'));
    }

    final pending = ref.watch(platformAuthActionsProvider);
    final loginPending = pending.contains('${platform.platform}:login');
    final checkPending = pending.contains('${platform.platform}:check');
    final logoutPending = pending.contains('${platform.platform}:logout');
    final busy = loginPending || checkPending || logoutPending;
    final loginLabel = !platform.hasCookie
        ? '登录'
        : platform.browserAuthValid == false
        ? '重新登录'
        : '更新登录';

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (platform.hasCookie)
          OutlinedButton.icon(
            onPressed: busy ? null : onCheck,
            icon: checkPending
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_outlined, size: 18),
            label: const Text('检测'),
          ),
        if (platform.hasCookie)
          TextButton(
            onPressed: busy ? null : onLogout,
            child: const Text('退出'),
          ),
        FilledButton.tonalIcon(
          onPressed: busy ? null : onLogin,
          icon: loginPending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  platform.browserAuthValid == false
                      ? Icons.refresh_rounded
                      : Icons.qr_code_2_rounded,
                  size: 18,
                ),
          label: Text(loginLabel),
        ),
      ],
    );
  }
}

class _PlatformLoginDialog extends ConsumerStatefulWidget {
  const _PlatformLoginDialog({required this.platform, required this.label});

  final String platform;
  final String label;

  @override
  ConsumerState<_PlatformLoginDialog> createState() =>
      _PlatformLoginDialogState();
}

class _PlatformLoginDialogState extends ConsumerState<_PlatformLoginDialog> {
  PlatformAuthSession? _session;
  String? _error;
  bool _starting = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_start);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
        _session = null;
      });
    }
    try {
      final session = await ref
          .read(platformAuthActionsProvider.notifier)
          .startSession(widget.platform);
      _accept(session);
    } on PlatformAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = error.message;
      });
    }
  }

  void _accept(PlatformAuthSession session) {
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = null;
      _session = session;
    });
    if (session.succeeded) {
      ref.read(platformAuthActionsProvider.notifier).refreshHealth();
    } else if (!session.isTerminal) {
      _pollTimer = Timer(const Duration(seconds: 2), _poll);
    }
  }

  Future<void> _poll() async {
    final sessionId = _session?.sessionId;
    if (sessionId == null || sessionId.isEmpty || !mounted) return;
    try {
      final session = await ref
          .read(platformAuthActionsProvider.notifier)
          .readSession(sessionId);
      _accept(session);
    } on PlatformAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _cancel() async {
    _pollTimer?.cancel();
    final sessionId = _session?.sessionId;
    if (sessionId != null && sessionId.isNotEmpty && !_session!.isTerminal) {
      try {
        await ref
            .read(platformAuthActionsProvider.notifier)
            .cancelSession(sessionId);
      } on PlatformAuthException {
        // 关闭对话框仍应立即生效；服务端会按自身超时回收异常会话。
      }
    }
    if (mounted) Navigator.pop(context, false);
  }

  Uint8List? _decodeQr(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final payload = value.contains(',') ? value.split(',').last : value;
      return base64Decode(payload);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = _session;
    final qrBytes = _decodeQr(session?.qrcodeB64);
    final succeeded = session?.succeeded == true;
    final failed = session?.isTerminal == true && !succeeded;

    return AlertDialog(
      icon: Icon(
        succeeded
            ? Icons.verified_rounded
            : failed || _error != null
            ? Icons.error_outline_rounded
            : Icons.qr_code_2_rounded,
        color: succeeded
            ? scheme.primary
            : failed || _error != null
            ? scheme.error
            : scheme.secondary,
      ),
      title: Text(succeeded ? '${widget.label} 登录成功' : '${widget.label} 扫码登录'),
      content: SizedBox(
        width: 360,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_starting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              else if (qrBytes != null && !succeeded && !failed) ...[
                Container(
                  width: 220,
                  height: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Image.memory(
                    qrBytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!_starting)
                Text(
                  _error ?? session?.message ?? _statusLabel(session?.status),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _error != null || failed
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              if (session?.captchaUrl?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => SafeUrlLauncher.openExternal(
                    context,
                    session!.captchaUrl,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('完成安全验证'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!succeeded) TextButton(onPressed: _cancel, child: const Text('取消')),
        if (failed || _error != null)
          FilledButton.tonal(onPressed: _start, child: const Text('重试')),
        if (succeeded)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('完成'),
          ),
      ],
    );
  }

  String _statusLabel(String? status) => switch (status) {
    'initializing' => '正在创建登录会话…',
    'waiting_scan' => '请使用对应平台 App 扫码',
    'needs_captcha' => '需要完成安全验证',
    'timeout' => '二维码已过期，请重试',
    'failed' => '登录失败，请重试',
    _ => '正在等待平台确认…',
  };
}

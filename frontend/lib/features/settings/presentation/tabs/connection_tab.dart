import '../../../../core/widgets/app_setting_group.dart';
import '../../../../core/layout/app_page_body.dart';

import 'package:go_router/go_router.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/local_settings_provider.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/utils/safe_url_launcher.dart';
import '../../../../core/widgets/adaptive_form_dialog.dart';
import '../../../../core/widgets/metadata_wrap.dart';
import '../../../../core/network/api_client.dart';
import '../../providers/settings_provider.dart';
import '../../providers/platform_auth_controller.dart';
import '../../providers/platform_health_provider.dart';
import '../../models/system_setting.dart';
import '../../utils/setting_value.dart';
import '../widgets/setting_components.dart';
import '../widgets/settings_editor_draft.dart';
import '../../../../theme/design_tokens.dart';

class ConnectionTab extends ConsumerWidget {
  const ConnectionTab({
    super.key,
    this.accountsOnly = false,
    this.onOpenPlatform,
    this.selectedPlatform,
  });

  final String? selectedPlatform;
  final bool accountsOnly;
  final ValueChanged<PlatformHealthStatus>? onOpenPlatform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accountsOnly) {
      final platformHealthAsync = ref.watch(platformHealthProvider);
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          const SectionHeader(title: '消息账号'),
          AppSettingGroup(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: const Icon(Icons.telegram_rounded),
                selected: selectedPlatform == 'telegram',
                title: const Text('Telegram'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go('/accounts/telegram'),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                selected: selectedPlatform == 'qq',
                title: const Text('QQ'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go('/accounts/qq'),
              ),
              ref
                  .watch(systemSettingsProvider)
                  .when(
                    data: (settings) => SettingSwitch(
                      title: const Text('允许机器人转存收藏'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      value: parseBoolSetting(
                        getSettingValue(settings, 'chat_capture_enabled', true),
                        true,
                      ),
                      onChanged: (value) => ref
                          .read(systemSettingsProvider.notifier)
                          .updateSetting(
                            'chat_capture_enabled',
                            value,
                            category: 'bot',
                          ),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => SettingLoadFailure(
                      onRetry: () => ref.invalidate(systemSettingsProvider),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: '内容平台'),
          _buildPlatformHealthSection(context, ref, platformHealthAsync),
          AppSettingGroup(
            children: [
              ref
                  .watch(systemSettingsProvider)
                  .when(
                    data: (settings) => SettingSwitch(
                      shape: const RoundedRectangleBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      title: const Text('自动检查登录状态'),
                      value: parseBoolSetting(
                        getSettingValue(
                          settings,
                          'enable_cookie_keepalive',
                          true,
                        ),
                        true,
                      ),
                      onChanged: (value) => ref
                          .read(systemSettingsProvider.notifier)
                          .updateSetting(
                            'enable_cookie_keepalive',
                            value,
                            category: 'automation',
                          ),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => SettingLoadFailure(
                      onRetry: () => ref.invalidate(systemSettingsProvider),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      );
    }

    final localSettings = ref.watch(localSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return AppPageBody(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          SettingGroup(
            children: [
              ExpandableSettingTile(
                title: '服务器地址',
                subtitle: Text(localSettings.baseUrl),
                expandedContent: _buildBaseUrlEditor(
                  context,
                  ref,
                  localSettings.baseUrl,
                ),
              ),
              ExpandableSettingTile(
                title: 'API 访问密钥',
                subtitle: Text(_maskToken(localSettings.apiToken)),
                expandedContent: _buildApiTokenEditor(
                  context,
                  ref,
                  localSettings.apiToken,
                ),
              ),
              ExpandableSettingTile(
                title: '网络代理',
                subtitle: Text(_getProxySubtitle(ref)),
                expandedContent: _buildProxyEditor(context, ref),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _testConnection(
                  context,
                  ref,
                  localSettings.baseUrl,
                  localSettings.apiToken,
                ),
                icon: const Icon(Icons.cell_tower_rounded),
                label: const Text('测试服务器连接'),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('退出登录'),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: AppSettingGroup(
            children: [
              for (final platform in health.platforms)
                ListTile(
                  selected: selectedPlatform == platform.platform,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  shape: const RoundedRectangleBorder(),
                  title: Text(
                    platform.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: MetadataWrap(items: _platformHealthFacts(platform)),
                  leading: Icon(
                    _platformHealthIcon(platform),
                    color: _platformHealthColor(context, platform),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenPlatform == null
                      ? null
                      : () => onOpenPlatform!(platform),
                ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => SettingGroup(
        children: [
          SettingTile(
            title: '平台健康状态',
            subtitle: '加载失败，点击重试',
            onTap: () => ref.invalidate(platformHealthProvider),
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

  List<String> _platformHealthFacts(PlatformHealthStatus platform) {
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
    if (platform.health == 'error' &&
        platform.browserAuthValid != false &&
        platform.favoritesAuthenticated != false) {
      parts.add('需要处理');
    }
    return parts;
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

  Widget _buildBaseUrlEditor(
    BuildContext context,
    WidgetRef ref,
    String currentValue,
  ) {
    return _ConnectionValueEditor(
      initialValue: currentValue,
      label: '服务器地址',
      hint: 'https://vault.example.com',
      buttonLabel: '保存地址',
      onSave: (value) async {
        try {
          await ref.read(localSettingsProvider.notifier).setBaseUrl(value);
          if (context.mounted) showToast(context, '服务器地址已保存');
        } on FormatException catch (error) {
          if (context.mounted) showToast(context, error.message);
        }
      },
    );
  }

  Widget _buildApiTokenEditor(
    BuildContext context,
    WidgetRef ref,
    String currentValue,
  ) {
    return _ConnectionValueEditor(
      initialValue: currentValue,
      label: 'API 访问密钥',
      obscureText: true,
      buttonLabel: '更新密钥',
      onSave: (value) async {
        await ref.read(localSettingsProvider.notifier).setApiToken(value);
        if (context.mounted) showToast(context, '密钥已更新');
      },
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
        return _ConnectionValueEditor(
          initialValue: proxy,
          label: 'HTTP/HTTPS 代理地址',
          hint: 'http://127.0.0.1:7890',
          buttonLabel: '保存代理',
          onSave: (value) async {
            await ref
                .read(systemSettingsProvider.notifier)
                .updateSetting('http_proxy', value, category: 'network');
            if (context.mounted) showToast(context, '代理已保存');
          },
        );
      },
      loading: () => const LoadingGroup(),
      error: (_, _) => SettingLoadFailure(
        onRetry: () => ref.invalidate(systemSettingsProvider),
      ),
    );
  }

  Widget buildBiliAdvancedEditor(BuildContext context, WidgetRef ref) {
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

        return SettingsEditorDraft(
          initialValues: {'sessdata': sessdata, 'jct': jct, 'buvid': buvid},
          builder: (context, controllers) {
            final sessController = controllers['sessdata']!;
            final jctController = controllers['jct']!;
            final buvidController = controllers['buvid']!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('SESSDATA（Cookie）'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'SESSDATA（Cookie）',
                  child: TextField(
                    controller: sessController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('bili_jct（CSRF）'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'bili_jct（CSRF）',
                  child: TextField(
                    controller: jctController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('buvid3'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'buvid3',
                  child: TextField(
                    controller: buvidController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: SettingSaveButton(
                    onPressed: () async {
                      final notifier = ref.read(
                        systemSettingsProvider.notifier,
                      );
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
        );
      },
      loading: () => const LoadingGroup(),
      error: (_, _) => SettingLoadFailure(
        onRetry: () => ref.invalidate(systemSettingsProvider),
      ),
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
          showToast(context, authOk ? '连接并认证成功' : '连接成功，但 API 密钥无效');
        } else {
          showToast(context, result['error'] as String);
        }
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          formatApiErrorMessage(e, fallbackMessage: '连接测试失败，请重试'),
        );
      }
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
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
              Navigator.pop(ctx);
              await ref.read(localSettingsProvider.notifier).clearAuth();
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

class PlatformLoginDialog extends ConsumerStatefulWidget {
  const PlatformLoginDialog({
    super.key,
    required this.platform,
    required this.label,
  });

  final String platform;
  final String label;

  @override
  ConsumerState<PlatformLoginDialog> createState() =>
      _PlatformLoginDialogState();
}

class _PlatformLoginDialogState extends ConsumerState<PlatformLoginDialog> {
  PlatformAuthSession? _session;
  String? _error;
  bool _starting = true;
  bool _polling = false;
  Timer? _pollTimer;
  late final PlatformAuthActions _actions;

  @override
  void initState() {
    super.initState();
    _actions = ref.read(platformAuthActionsProvider.notifier);
    Future<void>.microtask(_start);
  }

  // Closing must also release the server session when back/Escape dismisses
  // the route, or when session creation finishes after the dialog was closed.
  Future<void> _release(PlatformAuthSession? session) async {
    if (session == null || session.isTerminal) return;
    try {
      await _actions.cancelSession(session.sessionId);
    } on PlatformAuthException {
      // The server timeout remains responsible if cancellation cannot reach it.
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    unawaited(_release(_session));
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) return;
    _pollTimer?.cancel();
    final previous = _session;
    setState(() {
      _starting = true;
      _error = null;
      _session = null;
    });
    await _release(previous);
    if (!mounted) return;
    try {
      final session = await _actions.startSession(widget.platform);
      if (!mounted) {
        await _release(session);
        return;
      }
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
      _actions.refreshHealth();
    } else if (!session.isTerminal) {
      _pollTimer = Timer(const Duration(seconds: 2), _poll);
    }
  }

  Future<void> _poll() async {
    final sessionId = _session?.sessionId;
    if (sessionId == null || !mounted || _polling) return;
    _polling = true;
    setState(() => _error = null);
    try {
      _accept(await _actions.readSession(sessionId));
    } on PlatformAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _polling = false;
    }
  }

  void _cancel() => Navigator.pop(context, false);

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
    final metrics = WindowMetrics.of(context);
    final short = metrics.isShortLandscape;
    final qrSize = short ? (metrics.height - 180).clamp(112.0, 220.0) : 220.0;
    final hasQr = qrBytes != null && !succeeded && !failed;
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _error ?? session?.message ?? _statusLabel(session?.status),
          textAlign: !hasQr || short ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _error != null || failed
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
        if (session?.captchaUrl?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () =>
                SafeUrlLauncher.openExternal(context, session!.captchaUrl),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('完成安全验证'),
          ),
        ],
      ],
    );

    return AdaptiveFormDialog(
      title: succeeded ? '${widget.label} 登录成功' : '${widget.label} 扫码登录',
      maxWidth: short ? 560 : 408,
      contentBuilder: (context, contentWidth, shortHeight) {
        final qr = !hasQr
            ? null
            : Container(
                width: qrSize.clamp(0.0, contentWidth),
                height: qrSize.clamp(0.0, contentWidth),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppShape.paneBorder,
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
              );
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_starting)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (shortHeight && qr != null && contentWidth >= qrSize + 180)
              Row(
                children: [
                  qr,
                  const SizedBox(width: 20),
                  Expanded(child: status),
                ],
              )
            else ...[
              if (qr != null) ...[qr, const SizedBox(height: 16)],
              status,
            ],
          ],
        );
        return MediaQuery.disableAnimationsOf(context)
            ? content
            : AnimatedSize(
                duration: AppMotion.contentSwap,
                curve: AppMotion.standardCurve,
                child: content,
              );
      },
      actions: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: [
          if (!succeeded)
            TextButton(onPressed: _cancel, child: const Text('取消')),
          if (failed || _error != null)
            FilledButton.tonal(
              onPressed: _starting || _polling
                  ? null
                  : session != null && !session.isTerminal
                  ? _poll
                  : _start,
              child: const Text('重试'),
            ),
          if (succeeded)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成'),
            ),
        ],
      ),
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

class _ConnectionValueEditor extends StatelessWidget {
  const _ConnectionValueEditor({
    required this.initialValue,
    required this.label,
    required this.buttonLabel,
    required this.onSave,
    this.hint,
    this.obscureText = false,
  });

  final String initialValue;
  final String label;
  final String buttonLabel;
  final String? hint;
  final bool obscureText;
  final Future<void> Function(String value) onSave;

  @override
  Widget build(BuildContext context) => SettingsEditorDraft(
    initialValues: {'value': initialValue},
    builder: (context, controllers) {
      final controller = controllers['value']!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: label,
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: obscureText
                  ? TextInputType.text
                  : TextInputType.url,
              decoration: InputDecoration(hintText: hint),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => onSave(controller.text),
              child: Text(buttonLabel),
            ),
          ),
        ],
      );
    },
  );
}

/// Explicit credential entry; never reads a browser profile or echoes saved secrets.
class XSessionCookieDialog extends ConsumerStatefulWidget {
  const XSessionCookieDialog({super.key});
  @override
  ConsumerState<XSessionCookieDialog> createState() =>
      _XSessionCookieDialogState();
}

class _XSessionCookieDialogState extends ConsumerState<XSessionCookieDialog> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    final names = value
        .split(';')
        .map((part) => part.split('=').first.trim())
        .toSet();
    if (!names.containsAll({'auth_token', 'ct0'})) {
      setState(() => _error = '需要同时包含 auth_token 和 ct0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(systemSettingsProvider.notifier)
          .updateSetting('twitter_cookie', value, category: 'platform');
      _controller.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请检查服务器连接后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存 X 网页登录'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: '登录 Cookie',
                hintText: 'auth_token=…; ct0=…',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '正在保存' : '保存'),
      ),
    ],
  );
}

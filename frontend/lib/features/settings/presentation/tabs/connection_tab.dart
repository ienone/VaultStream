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
import '../../../accounts/account_detail_page.dart';
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
    this.selectedPlatform,
    this.onAccountSelected,
  });

  final ValueChanged<String>? onAccountSelected;
  final String? selectedPlatform;
  final bool accountsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accountsOnly) {
      final platformHealthAsync = ref.watch(platformHealthProvider);
      return ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 24),
        children: [
          const SectionHeader(title: '内容平台'),
          _buildPlatformHealthSection(context, ref, platformHealthAsync),
          const SizedBox(height: 16),
          const SectionHeader(title: '聊天账号'),
          for (final entry in {'telegram': 'Telegram', 'qq': 'QQ'}.entries)
            ListTile(
              leading: Icon(
                entry.key == 'telegram'
                    ? Icons.telegram_rounded
                    : Icons.chat_bubble_outline_rounded,
              ),
              selected: selectedPlatform == entry.key,
              title: Text(entry.value),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onAccountSelected != null
                  ? onAccountSelected!(entry.key)
                  : context.go('/accounts/${entry.key}'),
            ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('账号设置'),
            children: [
              ref
                  .watch(systemSettingsProvider)
                  .when(
                    data: (settings) => Column(
                      children: [
                        for (final option in {
                          'chat_capture_enabled': '允许机器人保存到收藏库',
                          'enable_cookie_keepalive': '自动检查登录状态',
                        }.entries)
                          SettingSwitch(
                            title: Text(option.value),
                            value: parseBoolSetting(
                              getSettingValue(settings, option.key, true),
                              true,
                            ),
                            onChanged: (value) => ref
                                .read(systemSettingsProvider.notifier)
                                .updateSetting(
                                  option.key,
                                  value,
                                  category: option.key == 'chat_capture_enabled'
                                      ? 'bot'
                                      : 'automation',
                                ),
                          ),
                      ],
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
              Padding(
                padding: const EdgeInsets.all(20),
                child: _buildBaseUrlEditor(context, ref, localSettings.baseUrl),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: _buildApiTokenEditor(
                  context,
                  ref,
                  localSettings.apiToken,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: _buildProxyEditor(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.network_check_rounded),
                title: const Text('测试连接'),
                onTap: () => _testConnection(
                  context,
                  ref,
                  localSettings.baseUrl,
                  localSettings.apiToken,
                ),
              ),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: colorScheme.error),
                title: Text('退出登录', style: TextStyle(color: colorScheme.error)),
                onTap: () => _confirmLogout(context, ref),
              ),
            ],
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
        return _PlatformAccountList(
          platforms: health.platforms,
          selectedPlatform: selectedPlatform,
          onSelected: onAccountSelected,
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
      label: '访问密钥',
      obscureText: true,
      buttonLabel: '更新密钥',
      onSave: (value) async {
        await ref.read(localSettingsProvider.notifier).setApiToken(value);
        if (context.mounted) showToast(context, '密钥已更新');
      },
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

  Widget buildBiliAdvancedEditor(BuildContext context, WidgetRef ref) =>
      SettingsEditorDraft(
        initialValues: const {'cookie': ''},
        builder: (context, controllers) {
          final field = controllers['cookie']!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: field,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '哔哩哔哩 Cookie',
                  hintText: 'SESSDATA=…',
                ),
              ),
              SettingSaveButton(
                onPressed: () async {
                  final cookie = field.text.trim();
                  if (!cookie
                      .split(';')
                      .any(
                        (part) => RegExp(r'^SESSDATA=.+').hasMatch(part.trim()),
                      )) {
                    showToast(context, 'Cookie 需要包含 SESSDATA');
                    return;
                  }
                  await ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'bilibili_cookie',
                        cookie,
                        category: 'platform',
                      );
                  if (context.mounted) {
                    field.clear();
                    ref.invalidate(platformHealthProvider);
                    showToast(context, '已保存哔哩哔哩登录');
                  }
                },
                child: const Text('保存登录'),
              ),
            ],
          );
        },
      );

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
          showToast(context, authOk ? '连接成功' : '访问密钥无效');
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
        content: const Text('退出后需重新输入访问密钥。'),
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

class _PlatformAccountList extends StatefulWidget {
  const _PlatformAccountList({
    required this.platforms,
    required this.selectedPlatform,
    this.onSelected,
  });

  final List<PlatformHealthStatus> platforms;
  final String? selectedPlatform;
  final ValueChanged<String>? onSelected;

  @override
  State<_PlatformAccountList> createState() => _PlatformAccountListState();
}

class _PlatformAccountListState extends State<_PlatformAccountList> {
  final _platformKeys = <String, GlobalKey>{};
  String? _revealedPlatform;

  @override
  void didUpdateWidget(_PlatformAccountList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPlatform != widget.selectedPlatform) {
      _revealedPlatform = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final platform in widget.platforms) {
      _platformKeys.putIfAbsent(platform.platform, GlobalKey.new);
    }
    final target = widget.selectedPlatform;
    final key = _platformKeys[target];
    if (key != null && _revealedPlatform != target) {
      _revealedPlatform = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.selectedPlatform != target) return;
        final targetContext = key.currentContext;
        if (targetContext != null) Scrollable.ensureVisible(targetContext);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final platform in widget.platforms)
          if (widget.onSelected != null)
            ListTile(
              key: _platformKeys[platform.platform],
              title: Text(platform.label),
              selected: platform.platform == widget.selectedPlatform,
              onTap: () => widget.onSelected!(platform.platform),
            )
          else
            AccountPlatformPanel(
              key: _platformKeys[platform.platform],
              account: platform,
            ),
      ],
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
          TextField(
            controller: controller,
            obscureText: obscureText,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: obscureText ? TextInputType.text : TextInputType.url,
            decoration: InputDecoration(labelText: label, hintText: hint),
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

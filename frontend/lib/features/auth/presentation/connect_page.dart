import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/local_settings_provider.dart';
import '../../../core/utils/toast.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../theme/design_tokens.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(localSettingsProvider);
    _urlController.text = settings.baseUrl;
    _tokenController.text = settings.apiToken;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    final result = await ref
        .read(localSettingsProvider.notifier)
        .validateConnection(url, token);

    if (!mounted) return;

    if (result['success'] == true) {
      if (result['auth_ok'] == true) {
        // 仅在鉴权成功后才持久化凭据，路由守卫依赖此状态跳转
        await ref.read(localSettingsProvider.notifier).setBaseUrl(url);
        await ref.read(localSettingsProvider.notifier).setApiToken(token);
        if (mounted) {
          Toast.show(context, '连接成功');
          // localSettingsProvider 状态更新后路由会自动跳转
        }
      } else {
        if (mounted) {
          setState(() {
            _error = '服务器连接成功，但 API 密钥错误。请检查控制台打印的密钥。';
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        _error = result['error'];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactHeight = ResponsiveLayout.heightClassFor(
              constraints.maxHeight,
            ).isCompact;
            return Center(
              child: SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: AppPane.formMaxWidth,
                  ),
                  padding: EdgeInsets.all(
                    compactHeight ? AppSpacing.md : AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!compactHeight) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(
                            Icons.lan_outlined,
                            size: 40,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        '连接到 VaultStream',
                        style: compactHeight
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '填写服务器地址和访问密钥',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        key: const ValueKey('connection-url'),
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'https://vault.example.com/api/v1',
                          prefixIcon: Icon(Icons.link),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        key: const ValueKey('connection-token'),
                        controller: _tokenController,
                        decoration: const InputDecoration(
                          labelText: 'API 密钥',
                          hintText: 'VS_...',
                          prefixIcon: Icon(Icons.key),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleConnect(),
                        enabled: !_isLoading,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: AppShape.cardMediaBorder,
                            ),
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _handleConnect,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_isLoading ? '连接中…' : '连接服务器'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

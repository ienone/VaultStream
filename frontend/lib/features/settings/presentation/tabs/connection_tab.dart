import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/local_settings_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/system_setting.dart';
import '../widgets/setting_components.dart';
import '../../../auth/presentation/widgets/interactive_login_dialog.dart';
import '../../../../core/network/api_client.dart';

class ConnectionTab extends ConsumerWidget {
  const ConnectionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localSettings = ref.watch(localSettingsProvider);
    final settingsAsync = ref.watch(systemSettingsProvider);
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
        const SectionHeader(title: '链接与账号', icon: Icons.link_rounded),
        _buildPlatformSettingsSection(context, ref, settingsAsync),
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

  Widget _buildPlatformSettingsSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) => _buildPlatformSettings(context, ref, settings),
      loading: () => const LoadingGroup(),
      error: (err, _) => SettingGroup(
        children: [
          SettingTile(
            title: '配置同步失败',
            subtitle: '点击重试获取服务端配置',
            icon: Icons.sync_problem_rounded,
            iconColor: Theme.of(context).colorScheme.error,
            onTap: () => ref.invalidate(systemSettingsProvider),
          ),
        ],
      ),
    );
  }

  /// 检测平台 Cookie 有效性
  Future<void> _checkPlatformStatus(
    BuildContext context,
    WidgetRef ref,
    String platformId,
  ) async {
    try {
      showToast(context, '正在检测状态，请稍候...');
      final dio = ref.read(apiClientProvider);
      final res = await dio.post('/browser-auth/$platformId/check');
      final isValid = res.data['is_valid'] == true;
      if (context.mounted) {
        showToast(context, isValid ? 'Cookie 有效，正常在线' : 'Cookie 已失效，请重新连接');
      }
    } catch (e) {
      if (context.mounted) showToast(context, '状态检测失败: $e');
    }
  }

  /// 解绑平台（删除 Cookie）
  Future<void> _logoutPlatform(
    BuildContext context,
    WidgetRef ref,
    String platformId,
  ) async {
    try {
      final dio = ref.read(apiClientProvider);
      await dio.delete('/browser-auth/$platformId');
      ref.invalidate(systemSettingsProvider);
      if (context.mounted) showToast(context, '已退出登录并清除 Cookie');
    } catch (e) {
      if (context.mounted) showToast(context, '退出失败: $e');
    }
  }

  /// 弹出扫码登录对话框
  Future<void> _showLoginDialog(
    BuildContext context,
    WidgetRef ref,
    String platformId,
    String platformLabel,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => InteractiveLoginDialog(
        platform: platformId,
        platformLabel: platformLabel,
      ),
    );

    if (result == true) {
      ref.invalidate(systemSettingsProvider);
      if (context.mounted) showToast(context, '$platformLabel 连接成功！');
    }
  }

  Widget _buildPlatformSettings(
    BuildContext context,
    WidgetRef ref,
    List<SystemSetting> settings,
  ) {
    final platforms = [
      {'id': 'weibo', 'name': '微博', 'icon': Icons.share_rounded},
      {'id': 'xiaohongshu', 'name': '小红书', 'icon': Icons.explore_rounded},
      {'id': 'zhihu', 'name': '知乎', 'icon': Icons.question_answer_rounded},
    ];

    return SettingGroup(
      children: platforms.map((p) {
        final platformId = p['id'] as String;
        final platformLabel = p['name'] as String;
        final icon = p['icon'] as IconData;
        final setting = settings
            .where((s) => s.key == '${platformId}_cookie')
            .firstOrNull;
        final isConfigured =
            setting != null && setting.value.toString().isNotEmpty;

        return SettingTile(
          title: platformLabel,
          subtitle: isConfigured ? 'Cookie 已配置 ✅' : '未连接',
          icon: icon,
          onTap: null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isConfigured)
                TextButton(
                  onPressed: () =>
                      _checkPlatformStatus(context, ref, platformId),
                  child: const Text('检测状态'),
                ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () =>
                    _showLoginDialog(context, ref, platformId, platformLabel),
                child: Text(isConfigured ? '重新连接' : '扫码连接'),
              ),
              if (isConfigured)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  tooltip: '解绑并注销',
                  onPressed: () => _logoutPlatform(context, ref, platformId),
                ),
            ],
          ),
        );
      }).toList(),
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

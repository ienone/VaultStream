import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/local_settings_provider.dart';
import '../../providers/settings_provider.dart';
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
                trailing: Text(
                  _platformHealthLabel(platform.health),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _platformHealthColor(context, platform),
                    fontWeight: FontWeight.w700,
                  ),
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

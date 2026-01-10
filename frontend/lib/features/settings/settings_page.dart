// ignore_for_file: deprecated_member_use
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'models/system_setting.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final settingsAsync = ref.watch(systemSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置中心'),
        backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _buildSectionHeader(context, '外观与偏好'),
            _buildThemeSettings(context, ref, themeMode),
            const Divider(height: 32),
            _buildSectionHeader(context, '平台集成 (Cookies)'),
            _buildPlatformSettings(context, settings),
            const Divider(height: 32),
            _buildSectionHeader(context, '系统与存储'),
            _buildStorageSettings(context),
            const SizedBox(height: 40),
            _buildAppInfo(context),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('加载设置失败: $err')),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  Widget _buildThemeSettings(BuildContext context, WidgetRef ref, ThemeMode themeMode) {
    return Column(
      children: [
        _buildSettingTile(
          context,
          title: '主题模式',
          subtitle: _getThemeModeName(themeMode),
          icon: Icons.palette_outlined,
          onTap: () => _showThemePicker(context, ref, themeMode),
        ),
      ],
    );
  }

  String _getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system: return '跟随系统';
      case ThemeMode.light: return '浅色模式';
      case ThemeMode.dark: return '深色模式';
    }
  }

  void _showThemePicker(BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('跟随系统'),
              leading: const Icon(Icons.brightness_auto),
              trailing: currentMode == ThemeMode.system ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).set(ThemeMode.system);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('浅色模式'),
              leading: const Icon(Icons.light_mode),
              trailing: currentMode == ThemeMode.light ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).set(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('深色模式'),
              leading: const Icon(Icons.dark_mode),
              trailing: currentMode == ThemeMode.dark ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSettings(BuildContext context, List<SystemSetting> settings) {
    final platforms = [
      {'key': 'weibo_cookie', 'name': '微博', 'icon': Icons.wechat}, // Placeholder icon
      {'key': 'bilibili_cookie', 'name': 'Bilibili', 'icon': Icons.video_library},
      {'key': 'x_cookie', 'name': 'X (Twitter)', 'icon': Icons.close},
    ];

    return Column(
      children: platforms.map((p) {
        final setting = settings.where((s) => s.key == p['key']).firstOrNull;
        final isConfigured = setting != null && setting.value.toString().isNotEmpty;

        return _buildSettingTile(
          context,
          title: p['name'] as String,
          subtitle: isConfigured ? '已配置' : '未配置',
          icon: p['icon'] as IconData,
          trailing: Icon(
            isConfigured ? Icons.check_circle : Icons.warning_amber_rounded,
            color: isConfigured ? Colors.green : Colors.orange,
            size: 20,
          ),
          onTap: () => _showCookieEditor(context, p['key'] as String, p['name'] as String, setting?.value?.toString() ?? ''),
        );
      }).toList(),
    );
  }

  void _showCookieEditor(BuildContext context, String key, String name, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('配置 $name Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请粘贴对应平台的 Cookie 字符串，这通常包含登录信息。', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste cookie here...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              
              await ref.read(systemSettingsProvider.notifier).updateSetting(
                key, 
                controller.text,
                category: 'platform',
                description: '$name 登录凭证',
              );
              
              if (mounted) {
                navigator.pop();
                messenger.showSnackBar(SnackBar(content: Text('$name 配置已更新')));
              }
            }, 
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSettings(BuildContext context) {
    return Column(
      children: [
        _buildSettingTile(
          context,
          title: '清理缓存',
          subtitle: '删除本地临时文件和图片缓存',
          icon: Icons.cleaning_services_outlined,
          onTap: () {
            // TODO: Implement cache cleanup
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清理 (模拟)')));
          },
        ),
        _buildSettingTile(
          context,
          title: '网络代理',
          subtitle: '配置 HTTP 代理服务器',
          icon: Icons.network_ping,
          onTap: () {
             _showCookieEditor(context, 'http_proxy', 'HTTP 代理', '');
          },
        ),
      ],
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildAppInfo(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Text(
            'VaultStream',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          Text(
            'v0.1.0 (Alpha)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
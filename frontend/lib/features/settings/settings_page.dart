import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/widgets/frosted_app_bar.dart';
import '../bot/bot_management_page.dart';
import 'providers/settings_provider.dart';
import '../../core/providers/local_settings_provider.dart';
import 'models/system_setting.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final settingsAsync = ref.watch(systemSettingsProvider);
    final localSettings = ref.watch(localSettingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: const FrostedAppBar(title: Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          _buildHeroTitle(theme),
          const SizedBox(height: 32),

          _buildSectionHeader(context, 'AI 发现与分析'),
          _buildAiSettings(context, settingsAsync),
          const SizedBox(height: 32),

          _buildSectionHeader(context, '服务器与通信'),
          _buildGroup([
            _buildExpandableSettingTile(
              context,
              index: 0,
              title: '后端 API 地址',
              subtitle: localSettings.baseUrl,
              icon: Icons.cloud_done_rounded,
              expandedContent: _buildBaseUrlEditor(localSettings.baseUrl),
            ),
            _buildExpandableSettingTile(
              context,
              index: 1,
              title: 'API 访问密钥',
              subtitle: '管理您的身份认证凭证',
              icon: Icons.key_rounded,
              expandedContent: _buildApiTokenEditor(localSettings.apiToken),
            ),
            _buildSettingTile(
              context,
              title: '测试服务器连接',
              subtitle: '验证后端服务可用性',
              icon: Icons.cell_tower_rounded,
              onTap: () => _testConnection(context),
            ),
            _buildSettingTile(
              context,
              title: 'Bot 管理',
              subtitle: '配置 Telegram / QQ Bot，并同步群组',
              icon: Icons.smart_toy_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BotManagementPage()),
                );
              },
            ),
          ]),

          const SizedBox(height: 32),
          _buildSectionHeader(context, '外观与偏好'),
          _buildGroup([
            _buildSettingTile(
              context,
              title: '主题模式',
              subtitle: _getThemeModeName(themeMode),
              icon: Icons.palette_rounded,
              onTap: () => _showThemePicker(context, ref, themeMode),
            ),
            _buildSettingTile(
              context,
              title: '管理通知偏好设置',
              subtitle: '配置推送通知与提醒',
              icon: Icons.notifications_active_rounded,
              onTap: () => _showToast(context, '通知设置 (Beta)'),
            ),
          ]),

          const SizedBox(height: 32),
          _buildSectionHeader(context, '平台集成 (Cookies)'),
          _buildPlatformSettingsSection(context, settingsAsync),

          const SizedBox(height: 32),
          _buildSectionHeader(context, '备份与同步'),
          _buildGroup([
            _buildSettingTile(
              context,
              title: '管理备份设置',
              subtitle: '导出/导入您的本地配置',
              icon: Icons.cloud_upload_rounded,
              onTap: () => _showToast(context, '备份功能即将上线'),
            ),
            _buildExpandableSettingTile(
              context,
              index: 2,
              title: '网络代理配置',
              subtitle: '配置 HTTP/HTTPS 代理服务器',
              icon: Icons.lan_rounded,
              expandedContent: _buildProxyEditor(),
            ),
          ]),

          const SizedBox(height: 32),
          _buildSectionHeader(context, '关于 VaultStream'),
          _buildGroup([
            _buildSettingTile(
              context,
              title: '清理缓存',
              subtitle: '释放存储空间并清理媒体缓存',
              icon: Icons.delete_sweep_rounded,
              onTap: () => _showToast(context, '缓存已清理'),
            ),
            _buildSettingTile(
              context,
              title: '开源许可',
              subtitle: '查看第三方库授权信息',
              icon: Icons.info_outline_rounded,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'VaultStream',
                applicationVersion: 'v0.1.0-alpha',
              ),
            ),
            _buildSettingTile(
              context,
              title: '退出登录',
              subtitle: '清除本地认证并注销',
              icon: Icons.logout_rounded,
              iconColor: colorScheme.error,
              onTap: () => _confirmLogout(context),
              showArrow: false,
            ),
          ]),

          const SizedBox(height: 64),
          _buildAppInfo(context),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildAiSettings(
    BuildContext context,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) {
        final enableAi =
            settings
                    .firstWhere(
                      (s) => s.key == 'enable_ai_discovery',
                      orElse: () => const SystemSetting(key: '', value: false),
                    )
                    .value
                as bool? ??
            false;
        final prompt =
            settings
                    .firstWhere(
                      (s) => s.key == 'universal_adapter_prompt',
                      orElse: () => const SystemSetting(key: '', value: ''),
                    )
                    .value
                as String? ??
            '';
        final topics = settings
            .firstWhere(
              (s) => s.key == 'discovery_topics',
              orElse: () => const SystemSetting(key: '', value: []),
            )
            .value;

        // Handle topics list
        List<String> topicList = [];
        if (topics is List) {
          topicList = topics.map((e) => e.toString()).toList();
        }

        return _buildGroup([
          _buildSettingTile(
            context,
            title: '启用 AI 自动发现',
            subtitle: '根据订阅主题自动抓取相关内容',
            icon: Icons.auto_awesome_rounded,
            trailing: Switch(
              value: enableAi,
              onChanged: (val) => ref
                  .read(systemSettingsProvider.notifier)
                  .updateSetting('enable_ai_discovery', val, category: 'ai'),
            ),
            onTap: () => ref
                .read(systemSettingsProvider.notifier)
                .updateSetting(
                  'enable_ai_discovery',
                  !enableAi,
                  category: 'ai',
                ),
          ),
          _buildExpandableSettingTile(
            context,
            index: 100,
            title: '订阅主题管理',
            subtitle: '${topicList.length} 个关注主题',
            icon: Icons.topic_rounded,
            expandedContent: _buildTopicsEditor(topicList),
          ),
          _buildExpandableSettingTile(
            context,
            index: 101,
            title: '通用解析 Prompt',
            subtitle: '自定义 LLM 解析指令',
            icon: Icons.psychology_rounded,
            expandedContent: _buildPromptEditor(prompt),
          ),
        ]);
      },
      loading: () => const _LoadingGroup(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildTopicsEditor(List<String> currentTopics) {
    final controller = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: currentTopics
              .map(
                (t) => Chip(
                  label: Text(t),
                  onDeleted: () {
                    final newTopics = List<String>.from(currentTopics)
                      ..remove(t);
                    ref
                        .read(systemSettingsProvider.notifier)
                        .updateSetting(
                          'discovery_topics',
                          newTopics,
                          category: 'ai',
                        );
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '添加新主题...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty &&
                      !currentTopics.contains(val.trim())) {
                    final newTopics = List<String>.from(currentTopics)
                      ..add(val.trim());
                    ref
                        .read(systemSettingsProvider.notifier)
                        .updateSetting(
                          'discovery_topics',
                          newTopics,
                          category: 'ai',
                        );
                    controller.clear();
                  }
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_rounded),
              onPressed: () {
                if (controller.text.trim().isNotEmpty &&
                    !currentTopics.contains(controller.text.trim())) {
                  final newTopics = List<String>.from(currentTopics)
                    ..add(controller.text.trim());
                  ref
                      .read(systemSettingsProvider.notifier)
                      .updateSetting(
                        'discovery_topics',
                        newTopics,
                        category: 'ai',
                      );
                  controller.clear();
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptEditor(String currentPrompt) {
    final controller = TextEditingController(text: currentPrompt);
    return Column(
      children: [
        TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Enter LLM Prompt...',
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
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(
                    'universal_adapter_prompt',
                    controller.text,
                    category: 'ai',
                  );
              if (mounted) {
                _showToast(context, 'Prompt 已更新');
                setState(() => _expandedIndex = null);
              }
            },
            child: const Text('保存配置'),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroTitle(ThemeData theme) {
    return Text(
      '设置',
      style: theme.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -1.5,
        color: theme.colorScheme.onSurface,
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0);
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.outline,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children.asMap().entries.map((entry) {
          final isLast = entry.key == children.length - 1;
          return Column(
            children: [
              entry.value,
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 64,
                  endIndent: 20,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
            ],
          );
        }).toList(),
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          20,
        ), // Added radius for better ripple clipping
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (iconColor ?? colorScheme.primary).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null && showArrow)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.outline.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableSettingTile(
    BuildContext context, {
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget expandedContent,
    Widget? trailing,
  }) {
    final isExpanded = _expandedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildSettingTile(
          context,
          title: title,
          subtitle: subtitle,
          icon: icon,
          showArrow: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?trailing,
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0,
                duration: 300.ms,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          onTap: () =>
              setState(() => _expandedIndex = isExpanded ? null : index),
        ),
        AnimatedSize(
          duration: 300.ms,
          curve: Curves.easeOutQuart,
          child: isExpanded
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(64, 0, 20, 24),
                  child: expandedContent,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildBaseUrlEditor(String currentValue) {
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
              if (mounted) {
                _showToast(context, 'API 地址已保存');
                setState(() => _expandedIndex = null);
              }
            },
            child: const Text('保存配置'),
          ),
        ),
      ],
    );
  }

  Widget _buildApiTokenEditor(String currentValue) {
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
              if (mounted) {
                _showToast(context, '密钥已更新');
                setState(() => _expandedIndex = null);
              }
            },
            child: const Text('更新密钥'),
          ),
        ),
      ],
    );
  }

  Widget _buildProxyEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '设置 HTTP/HTTPS 代理以访问受限平台',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: '127.0.0.1:7890',
            prefixIcon: const Icon(Icons.vignette_rounded),
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
            onPressed: () => _showToast(context, '代理设置即将支持'),
            child: const Text('更新代理'),
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformSettingsSection(
    BuildContext context,
    AsyncValue<List<SystemSetting>> settingsAsync,
  ) {
    return settingsAsync.when(
      data: (settings) => _buildPlatformSettings(context, settings),
      loading: () => const _LoadingGroup(),
      error: (err, _) => _buildGroup([
        _buildSettingTile(
          context,
          title: '配置同步失败',
          subtitle: '点击重试获取服务端配置',
          icon: Icons.sync_problem_rounded,
          iconColor: Theme.of(context).colorScheme.error,
          onTap: () => ref.invalidate(systemSettingsProvider),
        ),
      ]),
    );
  }

  Widget _buildPlatformSettings(
    BuildContext context,
    List<SystemSetting> settings,
  ) {
    final platforms = [
      {
        'key': 'bilibili_cookie',
        'name': 'Bilibili 凭证',
        'icon': Icons.video_collection_rounded,
      },
      {'key': 'weibo_cookie', 'name': '微博 凭证', 'icon': Icons.share_rounded},
      {
        'key': 'x_cookie',
        'name': 'X (Twitter) 凭证',
        'icon': Icons.close_rounded,
      },
      {
        'key': 'xiaohongshu_cookie',
        'name': '小红书 凭证',
        'icon': Icons.explore_rounded,
      },
    ];

    return _buildGroup(
      platforms.asMap().entries.map((entry) {
        final p = entry.value;
        final setting = settings.where((s) => s.key == p['key']).firstOrNull;
        final isConfigured =
            setting != null && setting.value.toString().isNotEmpty;

        return _buildExpandableSettingTile(
          context,
          index: 10 + entry.key, // Unique index range for cookies
          title: p['name'] as String,
          subtitle: isConfigured ? '已完成登录授权' : '尚未配置访问凭证',
          icon: p['icon'] as IconData,
          expandedContent: _buildInlineCookieEditor(
            p['key'] as String,
            setting?.value?.toString() ?? '',
          ),
          trailing: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConfigured ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isConfigured ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInlineCookieEditor(String key, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '粘贴对应平台的 Cookie 字符串。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Paste here...',
            fillColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            filled: true,
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
                  .read(systemSettingsProvider.notifier)
                  .updateSetting(key, controller.text, category: 'platform');
              if (mounted) {
                _showToast(context, '凭证已保存');
                setState(() => _expandedIndex = null);
              }
            },
            child: const Text('保存配置'),
          ),
        ),
      ],
    );
  }

  String _getThemeModeName(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '深色模式',
  };

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPickerOption(
              context,
              '跟随系统',
              Icons.brightness_auto_rounded,
              currentMode == ThemeMode.system,
              () => _setTheme(ref, ThemeMode.system),
            ),
            _buildPickerOption(
              context,
              '浅色模式',
              Icons.light_mode_rounded,
              currentMode == ThemeMode.light,
              () => _setTheme(ref, ThemeMode.light),
            ),
            _buildPickerOption(
              context,
              '深色模式',
              Icons.dark_mode_rounded,
              currentMode == ThemeMode.dark,
              () => _setTheme(ref, ThemeMode.dark),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerOption(
    BuildContext context,
    String title,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : null),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: onTap,
    );
  }

  void _setTheme(WidgetRef ref, ThemeMode mode) {
    ref.read(themeModeProvider.notifier).set(mode);
    Navigator.pop(context);
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
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
              if (ctx.mounted) {
                Navigator.pop(ctx);
                _showToast(context, '已成功退出');
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

  Future<void> _testConnection(BuildContext context) async {
    _showToast(context, '正在测试连接...');
    try {
      final settings = ref.read(localSettingsProvider);
      final success = await ref
          .read(localSettingsProvider.notifier)
          .testConnection(settings.baseUrl, settings.apiToken);
      if (context.mounted) _showToast(context, success ? '✅ 连接成功' : '❌ 连接失败');
    } catch (e) {
      if (context.mounted) _showToast(context, '❌ 错误: $e');
    }
  }

  Widget _buildAppInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.vape_free_rounded,
            size: 48,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'VaultStream',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Version 0.1.0 (Alpha)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _LoadingGroup extends StatelessWidget {
  const _LoadingGroup();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(child: CircularProgressIndicator()),
    ).animate(onPlay: (c) => c.repeat()).shimmer();
  }
}

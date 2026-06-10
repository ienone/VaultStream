import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import 'presentation/tabs/connection_tab.dart';
import 'presentation/tabs/automation_tab.dart';
import 'presentation/tabs/push_tab.dart';
import 'presentation/tabs/system_tab.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late int _selectedIndex;
  late bool _showMobileDetail;

  static const List<_SettingsSection> _sections = [
    _SettingsSection(
      key: 'accounts',
      title: '账号与平台',
      subtitle: '服务器连接、平台登录、认证摘要',
      icon: Icons.manage_accounts_rounded,
      child: ConnectionTab(),
    ),
    _SettingsSection(
      key: 'automation',
      title: 'AI 与发现',
      subtitle: '发现源、AI 模型、收藏同步策略',
      icon: Icons.auto_awesome_rounded,
      child: AutomationTab(),
    ),
    _SettingsSection(
      key: 'push',
      title: '推送与通知',
      subtitle: 'Bot 凭证、目标、权限和频道',
      icon: Icons.outbox_rounded,
      child: PushTab(),
    ),
    _SettingsSection(
      key: 'system',
      title: '外观与系统',
      subtitle: '主题、媒体归档、存储和许可',
      icon: Icons.tune_rounded,
      child: SystemTab(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = _sectionIndex(widget.initialTab);
    _showMobileDetail = widget.initialTab != null;
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _selectedIndex = _sectionIndex(widget.initialTab);
        _showMobileDetail = widget.initialTab != null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final selected = _sections[_selectedIndex];

    return Scaffold(
      appBar: FrostedAppBar(
        title: Text(isMobile && _showMobileDetail ? selected.title : '设置'),
        leading: isMobile && _showMobileDetail
            ? IconButton(
                tooltip: '返回设置列表',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  setState(() => _showMobileDetail = false);
                  context.go('/settings');
                },
              )
            : null,
        actions: kDebugMode
            ? [
                IconButton(
                  icon: const Icon(Icons.rocket_launch),
                  tooltip: 'Debug: 进入引导页 (Onboarding)',
                  onPressed: () => context.push('/onboarding'),
                ),
              ]
            : null,
      ),
      body: isMobile ? _buildMobileBody(context) : _buildDesktopBody(context),
    );
  }

  Widget _buildDesktopBody(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = _sections[_selectedIndex];

    return Row(
      children: [
        Container(
          width: 292,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Text(
                  '设置分区',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '低频配置集中在这里；日常任务和异常处理会进入通知中心或自动化下钻。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < _sections.length; i++)
                  _SettingsSectionTile(
                    section: _sections[i],
                    selected: i == _selectedIndex,
                    onTap: () => _selectSection(context, i),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: colorScheme.surfaceContainerLowest,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingsContentHeader(section: selected),
                      const SizedBox(height: 16),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.38,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: selected.child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    if (_showMobileDetail) {
      return _sections[_selectedIndex].child;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          '选择设置分区',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '移动端先进入分区列表，再打开对应详情，避免在一个页面里堆叠过多表单。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < _sections.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SettingsSectionTile(
              section: _sections[i],
              selected: false,
              onTap: () {
                _selectSection(context, i);
                setState(() => _showMobileDetail = true);
              },
            ),
          ),
      ],
    );
  }

  void _selectSection(BuildContext context, int index) {
    setState(() => _selectedIndex = index);
    context.go('/settings?tab=${_sections[index].key}');
  }

  int _sectionIndex(String? tab) {
    return switch (tab) {
      'connection' || 'account' || 'accounts' || 'platforms' => 0,
      'automation' || 'ai' || 'discovery' || 'sources' => 1,
      'push' || 'bot' || 'notifications' => 2,
      'system' || 'appearance' => 3,
      _ => 0,
    };
  }
}

class _SettingsSection {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SettingsSection({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
}

class _SettingsSectionTile extends StatelessWidget {
  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsSectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;

    return Card(
      elevation: 0,
      color: selected
          ? colorScheme.secondaryContainer
          : colorScheme.surface.withValues(alpha: 0.78),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? colorScheme.secondary.withValues(alpha: 0.24)
              : colorScheme.outlineVariant.withValues(alpha: 0.34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.onSecondaryContainer.withValues(alpha: 0.1)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(section.icon, color: foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      section.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colorScheme.onSecondaryContainer.withValues(
                                alpha: 0.76,
                              )
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? colorScheme.primary : colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContentHeader extends StatelessWidget {
  final _SettingsSection section;

  const _SettingsContentHeader({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(section.icon, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                section.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../routing/navigation_scope.dart';
import '../../theme/design_tokens.dart';
import 'presentation/tabs/automation_tab.dart';
import 'presentation/tabs/connection_tab.dart';
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
  final _contentKey = GlobalKey();
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _detailPageKey = ValueKey('settings-detail-page');

  static const List<_SettingsSection> _sections = [
    _SettingsSection(
      key: 'connection',
      title: '连接与访问',
      subtitle: '服务器地址、访问密钥和网络代理',
      icon: Icons.lan_rounded,
      child: ConnectionTab(),
    ),
    _SettingsSection(
      key: 'automation',
      title: 'AI 模型',
      subtitle: '文本、视觉、摘要与语义模型',
      icon: Icons.auto_awesome_rounded,
      child: AutomationTab(),
    ),
    _SettingsSection(
      key: 'sources',
      title: '信息来源',
      subtitle: '发现来源、兴趣与保留策略',
      icon: Icons.rss_feed_rounded,
      child: AutomationTab(sourcesOnly: true),
    ),
    _SettingsSection(
      key: 'push',
      title: '推送与通知',
      subtitle: 'Bot 凭证、权限与周期摘要',
      icon: Icons.outbox_rounded,
      child: PushTab(),
    ),
    _SettingsSection(
      key: 'targets',
      title: '推送目标',
      subtitle: '群组与频道',
      icon: Icons.groups_outlined,
      child: PushTab(targetsOnly: true),
    ),
    _SettingsSection(
      key: 'storage',
      title: '媒体与存储',
      subtitle: '媒体归档、质量与存储限制',
      icon: Icons.storage_outlined,
      child: SystemTab(storageOnly: true),
    ),
    _SettingsSection(
      key: 'system',
      title: '外观与系统',
      subtitle: '主题与开源许可',
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final singlePane = !metrics.supportsSupportingPane;
        // Remember the detail actually shown by this layout, including when
        // a browser history entry clears the selected section query.
        if (!singlePane) _showMobileDetail = true;
        final selected = _sections[_selectedIndex];

        return NavigatorPopHandler<void>(
          enabled: singlePane,
          onPopWithResult: (_) {
            if (singlePane && _showMobileDetail) {
              _navigatorKey.currentState!.maybePop();
            }
          },
          child: NotificationListener<NavigationNotification>(
            // The wide section is part of one settings workspace. Only the
            // compact list-detail stack participates in nested system back.
            onNotification: (_) => !singlePane,
            child: AppNavigationScope(
              child: Navigator(
                key: _navigatorKey,
                pages: [
                  MaterialPage<void>(
                    key: const ValueKey('settings-list-page'),
                    child: Scaffold(
                      appBar: AppBar(
                        toolbarHeight: metrics.heightClass.isCompact
                            ? 48
                            : null,
                        title: const Text('设置'),
                        leading: _exitButton(context),
                      ),
                      body: SafeArea(
                        top: false,
                        child: _buildSectionList(context),
                      ),
                    ),
                  ),
                  if (_showMobileDetail)
                    MaterialPage<void>(
                      key: _detailPageKey,
                      canPop: singlePane,
                      child: singlePane
                          ? Scaffold(
                              appBar: AppBar(
                                toolbarHeight: metrics.heightClass.isCompact
                                    ? 48
                                    : null,
                                title: Text(selected.title),
                                leading: BackButton(
                                  onPressed: () =>
                                      _navigatorKey.currentState!.maybePop(),
                                ),
                              ),
                              body: SafeArea(
                                top: false,
                                child: _sectionContent(),
                              ),
                            )
                          : _buildDesktopBody(context),
                    ),
                ],
                onDidRemovePage: (page) {
                  if (page.key == _detailPageKey && _showMobileDetail) {
                    _backToSections(context);
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _exitButton(BuildContext context) => BackButton(
    onPressed: () {
      if (GoRouter.maybeOf(context)?.canPop() ?? false) {
        context.pop();
      } else {
        context.go('/home');
      }
    },
  );

  void _backToSections(BuildContext context) {
    setState(() => _showMobileDetail = false);
    context.replace('/settings');
  }

  Widget _buildDesktopBody(BuildContext context) {
    final selected = _sections[_selectedIndex];
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            key: const ValueKey('settings-section-pane'),
            width: AppPane.supportingWidth,
            child: Column(
              children: [
                AppBar(title: const Text('设置'), leading: _exitButton(context)),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                    children: [
                      for (var i = 0; i < _sections.length; i++)
                        _SettingsSectionTile(
                          section: _sections[i],
                          selected: i == _selectedIndex,
                          compact: true,
                          onTap: () => _selectSection(context, i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppShape.sheet),
              ),
              child: Material(
                color: surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppBar(
                      automaticallyImplyLeading: false,
                      backgroundColor: surface,
                      centerTitle: true,
                      titleSpacing: 0,
                      title: SizedBox(
                        width: AppPane.readableMaxWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(selected.title),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppPane.readableMaxWidth,
                          ),
                          child: _sectionContent(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionContent() =>
      KeyedSubtree(key: _contentKey, child: _sections[_selectedIndex].child);

  Widget _buildSectionList(BuildContext context) {
    return ListView(
      key: const PageStorageKey('settings-section-list'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        for (var i = 0; i < _sections.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
    context.replace('/settings?tab=${_sections[index].key}');
  }

  int _sectionIndex(String? tab) {
    final index = _sections.indexWhere((section) => section.key == tab);
    return index < 0 ? 0 : index;
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
  final bool compact;

  const _SettingsSectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    titleAlignment: compact
        ? ListTileTitleAlignment.center
        : ListTileTitleAlignment.titleHeight,
    leading: Icon(section.icon),
    title: Text(section.title),
    subtitle: compact ? null : Text(section.subtitle),
    trailing: compact ? null : const Icon(Icons.chevron_right_rounded),
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
    onTap: onTap,
  );
}

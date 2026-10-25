import '../../routing/overlay_back_observer.dart';
import '../../theme/design_tokens.dart';
import '../../core/layout/app_page_body.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/layout/app_list_detail_workspace.dart';
import '../../routing/navigation_scope.dart';
import '../../layout/root_page_actions.dart';
import '../../core/widgets/app_setting_group.dart';
import 'presentation/tabs/automation_tab.dart';
import '../automation/widgets/processing_automation_panel.dart';
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
  final _backObserver = OverlayBackObserver();
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
      key: 'processing',
      title: '内容处理',
      subtitle: '解析、摘要、索引与自动整理',
      icon: Icons.tune_rounded,
      child: ProcessingAutomationPanel(),
    ),
    _SettingsSection(
      key: 'automation',
      title: 'AI 模型',
      subtitle: '文本、视觉、摘要与语义模型',
      icon: Icons.auto_awesome_rounded,
      child: AutomationTab(),
    ),
    _SettingsSection(
      key: 'discovery',
      title: '筛选与保留',
      subtitle: '兴趣偏好、自动筛选和内容保留',
      icon: Icons.filter_alt_outlined,
      child: AutomationTab(view: AutomationView.policy),
    ),
    _SettingsSection(
      key: 'push',
      title: '通知',
      subtitle: '应用内摘要与消息',
      icon: Icons.outbox_rounded,
      child: PushTab(),
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
  void dispose() {
    _backObserver.dispose();
    super.dispose();
  }

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
        final singlePane = !AppListDetailWorkspace.supportsSplit(
          context,
          availableSize: constraints.biggest,
        );
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
                observers: [_backObserver],
                pages: [
                  MaterialPage<void>(
                    key: const ValueKey('settings-list-page'),
                    child: Scaffold(
                      appBar: AppBar(
                        toolbarHeight: metrics.toolbarHeight,
                        title: const Text('设置'),
                        automaticallyImplyLeading: false,
                        leading: _exitButton(context),
                      ),
                      body: SafeArea(
                        top: false,
                        child: AppPageBody(
                          maxWidth: AppPane.readableMaxWidth,
                          child: _buildSectionList(context),
                        ),
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
                                toolbarHeight: metrics.toolbarHeight,
                                title: Text(selected.title),
                                leading: BackButton(
                                  onPressed: () =>
                                      _navigatorKey.currentState!.maybePop(),
                                ),
                              ),
                              body: SafeArea(
                                top: false,
                                child: AppPageBody(
                                  maxWidth: AppPane.readableMaxWidth,
                                  child: _sectionContent(),
                                ),
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

  Widget? _exitButton(BuildContext context) => buildRootPageLeading(context);

  void _backToSections(BuildContext context) {
    setState(() => _showMobileDetail = false);
    context.replace('/settings');
  }

  Widget _buildDesktopBody(BuildContext context) {
    final selected = _sections[_selectedIndex];
    return AppListDetailWorkspace(
      selectedId: selected.key,
      list: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        appBar: AppBar(
          title: const Text('设置'),
          automaticallyImplyLeading: false,
          leading: _exitButton(context),
        ),
        body: Theme(
          data: Theme.of(context).copyWith(
            drawerTheme: const DrawerThemeData(width: double.infinity),
            navigationDrawerTheme: Theme.of(context).navigationDrawerTheme
                .copyWith(indicatorSize: const Size(double.infinity, 56)),
          ),
          child: NavigationDrawer(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            selectedIndex: _navigationOrder.indexOf(_selectedIndex),
            onDestinationSelected: (index) =>
                _selectSection(context, _navigationOrder[index]),
            children: [
              for (final group in _groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 24, 8),
                  child: Text(
                    group.$1,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final i in group.$2)
                  NavigationDrawerDestination(
                    icon: Icon(_sections[i].icon),
                    label: Text(_sections[i].title),
                  ),
              ],
            ],
          ),
        ),
      ),
      detailBuilder: (_, _, _) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(selected.title),
        ),
        body: AppPageBody(
          maxWidth: AppPane.readableMaxWidth,
          child: _sectionContent(),
        ),
      ),
    );
  }

  Widget _sectionContent() =>
      KeyedSubtree(key: _contentKey, child: _sections[_selectedIndex].child);

  static const _groups = [
    ('应用', [6, 4]),
    ('内容', [1, 2, 3, 5]),
    ('连接', [0]),
  ];
  static final _navigationOrder = _groups.expand((group) => group.$2).toList();
  Widget _buildSectionList(BuildContext context) => ListView(
    key: const PageStorageKey('settings-section-list'),
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    children: [
      for (final group in _groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          child: Text(group.$1, style: Theme.of(context).textTheme.titleSmall),
        ),
        AppSettingGroup(
          children: [
            for (final i in group.$2)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Icon(_sections[i].icon),
                title: Text(_sections[i].title),
                subtitle: Text(_sections[i].subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  _selectSection(context, i);
                  setState(() => _showMobileDetail = true);
                },
              ),
          ],
        ),
      ],
    ],
  );

  void _selectSection(BuildContext context, int index) {
    setState(() => _selectedIndex = index);
    context.replace('/settings?tab=${_sections[index].key}');
  }

  int _sectionIndex(String? tab) {
    final index = _sections.indexWhere((section) => section.key == tab);
    return index < 0 ? 6 : index;
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/frosted_app_bar.dart';

import 'presentation/tabs/connection_tab.dart';
import 'presentation/tabs/automation_tab.dart';
import 'presentation/tabs/push_tab.dart';
import 'presentation/tabs/system_tab.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;

  final List<String> _tabTitles = [
    '连接与账号',
    'AI 发现',
    '推送与通知',
    '外观与系统',
  ];

  final List<IconData> _tabIcons = [
    Icons.cloud_sync_rounded,
    Icons.auto_awesome_rounded,
    Icons.notifications_active_rounded,
    Icons.settings_suggest_rounded,
  ];

  final List<Widget> _tabs = const [
    ConnectionTab(),
    AutomationTab(),
    PushTab(),
    SystemTab(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 800;

        if (isWideScreen) {
          return Scaffold(
            appBar: const FrostedAppBar(title: Text('设置')),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                      _tabController.index = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(_tabTitles.length, (index) {
                    return NavigationRailDestination(
                      icon: Icon(_tabIcons[index]),
                      label: Text(_tabTitles[index]),
                    );
                  }),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: _tabs,
                  ),
                ),
              ],
            ),
          );
        }

        // Narrow screen layout
        return Scaffold(
          appBar: FrostedAppBar(
            title: const Text('设置'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: List.generate(_tabTitles.length, (index) {
                return Tab(
                  text: _tabTitles[index],
                  icon: Icon(_tabIcons[index]),
                );
              }),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: _tabs,
          ),
        );
      },
    );
  }
}

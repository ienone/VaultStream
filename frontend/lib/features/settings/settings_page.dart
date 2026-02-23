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

  final List<String> _tabTitles = [
    '连接与账号',
    'AI 发现',
    '推送与通知',
    '外观与系统',
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: FrostedAppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
          labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          unselectedLabelStyle: theme.textTheme.labelLarge,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: List.generate(_tabTitles.length, (index) {
            return Tab(text: _tabTitles[index]);
          }),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs,
      ),
    );
  }
}

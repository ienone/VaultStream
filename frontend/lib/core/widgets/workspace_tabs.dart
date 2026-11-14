import 'package:material_ui/material_ui.dart';

import '../../layout/root_page_actions.dart';

/// 页签与同一工作区的详情顶栏保持相同高度。
class WorkspaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WorkspaceAppBar({
    super.key,
    required this.tabs,
    required this.toolbarHeight,
    this.actions = const [],
  });
  final Widget tabs;
  final double toolbarHeight;
  final List<Widget> actions;
  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leading: buildRootPageLeading(context),
    toolbarHeight: toolbarHeight,
    titleSpacing: 12,
    centerTitle: true,
    title: tabs,
    actions: actions,
  );
}

class WorkspaceTabs extends StatelessWidget {
  const WorkspaceTabs({
    super.key,
    required this.controller,
    required this.labels,
    required this.onTap,
  });
  final TabController controller;
  final List<String> labels;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => TabBar.secondary(
    controller: controller,
    isScrollable: true,
    tabAlignment: TabAlignment.center,
    dividerColor: Colors.transparent,
    indicatorSize: TabBarIndicatorSize.label,
    labelStyle: Theme.of(context).textTheme.titleSmall,
    unselectedLabelStyle: Theme.of(context).textTheme.titleSmall,
    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
    tabs: [for (final label in labels) Tab(text: label)],
    onTap: onTap,
  );
}

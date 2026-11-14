import 'package:material_ui/material_ui.dart';

import '../../layout/root_page_actions.dart';

/// Workspace tabs replace the redundant title row on compact screens.
class WorkspaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WorkspaceAppBar({
    super.key,
    required this.tabs,
    this.actions = const [],
  });
  final Widget tabs;
  final List<Widget> actions;
  @override
  Size get preferredSize => const Size.fromHeight(52);
  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leading: buildRootPageLeading(context),
    toolbarHeight: 52,
    titleSpacing: 8,
    title: Align(alignment: AlignmentDirectional.centerStart, child: tabs),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final textStyle = Theme.of(context).textTheme.titleSmall;
      var widest = 0.0;
      for (final label in labels) {
        final text = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (text.width > widest) widest = text.width;
        text.dispose();
      }
      final scrollable = (widest + 32) * labels.length > box.maxWidth;
      return TabBar.secondary(
        controller: controller,
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        tabs: [for (final label in labels) Tab(text: label)],
        onTap: onTap,
      );
    },
  );
}

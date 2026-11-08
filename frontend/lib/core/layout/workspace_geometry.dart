import 'package:material_ui/material_ui.dart';

/// 网格与单列共用工作区的实际分栏进度，不为每张卡片启动动画。
class WorkspaceGeometry extends InheritedWidget {
  const WorkspaceGeometry({
    super.key,
    required this.overviewWidth,
    required this.listWidth,
    required this.progress,
    required super.child,
  });
  final double overviewWidth;
  final double listWidth;
  final double progress;
  static WorkspaceGeometry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceGeometry>();
  static WorkspaceGeometry of(BuildContext context) => maybeOf(context)!;
  @override
  bool updateShouldNotify(WorkspaceGeometry oldWidget) =>
      overviewWidth != oldWidget.overviewWidth ||
      listWidth != oldWidget.listWidth ||
      progress != oldWidget.progress;
}

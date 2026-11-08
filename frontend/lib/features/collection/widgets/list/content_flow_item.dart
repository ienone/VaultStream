import 'package:material_ui/material_ui.dart';

/// 收藏与动态共用连续列表；条目身份与纵向位置不随阅读分栏变化。
class ContentFlowItem extends StatelessWidget {
  const ContentFlowItem({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 880),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

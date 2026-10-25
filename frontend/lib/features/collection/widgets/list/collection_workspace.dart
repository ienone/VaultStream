import 'package:material_ui/material_ui.dart';

import '../../../../core/layout/app_list_detail_workspace.dart';
import '../../content_detail_page.dart';
import '../../models/content.dart';

/// 内容工作区只负责把选中内容交给共享布局和阅读器。
class CollectionWorkspace extends StatelessWidget {
  const CollectionWorkspace({
    super.key,
    required this.list,
    required this.selectedId,
    required this.onClose,
    this.preview,
  });
  final Widget list;
  final int? selectedId;
  final ShareCard? preview;
  final VoidCallback onClose;

  static bool supportsSplit(BuildContext context) =>
      AppListDetailWorkspace.supportsSplit(context);

  @override
  Widget build(BuildContext context) => AppListDetailWorkspace(
    list: list,
    selectedId: selectedId,
    onClose: onClose,
    detailBuilder: (deferBody, focused, toggleFocus) => ContentDetailPage(
      contentId: selectedId!,
      preview: preview,
      deferBody: deferBody,
      onClose: onClose,
      focused: focused,
      onToggleFocus: toggleFocus,
    ),
  );
}

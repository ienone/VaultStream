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
    this.emptyDetail,
    this.preview,
    this.defaultSelection = false,
  });
  final Widget list;
  final Widget? emptyDetail;
  final bool defaultSelection;
  final int? selectedId;
  final ShareCard? preview;
  final VoidCallback onClose;

  static bool supportsSplit(BuildContext context, {Size? availableSize}) =>
      AppListDetailWorkspace.supportsSplit(
        context,
        availableSize: availableSize,
      );

  @override
  Widget build(BuildContext context) => AppListDetailWorkspace(
    list: list,
    emptyDetail: emptyDetail,
    selectedId: selectedId,
    onClose: defaultSelection ? null : onClose,
    detailBuilder: (deferBody, focused, toggleFocus) => ContentDetailPage(
      contentId: selectedId!,
      preview: preview,
      deferBody: deferBody,
      onClose: onClose,
      showBackButton: !defaultSelection,
      focused: focused,
      onToggleFocus: toggleFocus,
    ),
  );
}

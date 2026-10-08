import '../../../automation/widgets/push_content_dialog.dart';
import 'package:flutter/material.dart';

import '../../models/content.dart';
import 'collection_card_preview.dart';

/// 网格中的可交互卡片。
///
/// hover 只改变 tonal surface（见 [CollectionCardPreview]），
/// 不做整体缩放，也没有周期性 shimmer。点击后立即取消 hover 状态，
/// 避免离场时残留放大或高亮。
class ContentCard extends StatefulWidget {
  const ContentCard({
    super.key,
    required this.content,
    this.onTap,
    this.onLongPress,
    this.onSelectionStart,
    this.onSelectionMove,
    this.onSelectionEnd,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isList = false,
    this.isActive = false,
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureLongPressStartCallback? onSelectionStart;
  final GestureLongPressMoveUpdateCallback? onSelectionMove;
  final GestureLongPressEndCallback? onSelectionEnd;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isList;
  final bool isActive;

  @override
  State<ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<ContentCard> {
  bool _isHovered = false;

  void _handleTap() {
    widget.onTap?.call();
    setState(() => _isHovered = false);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: widget.isSelectionMode ? widget.isSelected : widget.isActive,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onLongPress: widget.onSelectionStart == null
              ? widget.onLongPress
              : null,
          onLongPressStart: widget.onSelectionStart,
          onLongPressMoveUpdate: widget.onSelectionMove,
          onLongPressEnd: widget.onSelectionEnd,
          child: Stack(
            children: [
              CollectionCardPreview(
                content: widget.content,
                onTap: widget.onTap == null ? null : _handleTap,
                isHovered: !widget.isSelectionMode && _isHovered,
                transparentSurface: widget.isSelectionMode,
                isList: widget.isList,
                isEmphasized: widget.isSelectionMode ? false : widget.isActive,
                trailingSpace: 40,
              ),
              if (!widget.isSelectionMode)
                Positioned(
                  top: 0,
                  right: 0,
                  child: PopupMenuButton<String>(
                    tooltip: '内容操作',
                    onSelected: (value) {
                      if (value == 'push') {
                        showPushContentDialog(context, [widget.content.id]);
                      }
                      if (value == 'select') widget.onLongPress?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'push', child: Text('推送…')),
                      if (widget.onLongPress != null)
                        const PopupMenuItem(value: 'select', child: Text('选择')),
                    ],
                  ),
                ),
              if (widget.isSelectionMode && widget.isSelected)
                const Positioned(
                  top: 8,
                  right: 12,
                  child: ExcludeSemantics(
                    child: Icon(Icons.check_rounded, size: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

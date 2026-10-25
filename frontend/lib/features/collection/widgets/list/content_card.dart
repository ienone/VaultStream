import '../../../../core/utils/toast.dart';
import '../dialogs/delete_content_dialog.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/swipe_action_reveal.dart';
import '../../providers/content_actions_controller.dart';
import '../../../automation/widgets/push_content_dialog.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../models/content.dart';
import 'collection_card_preview.dart';

/// 网格中的可交互卡片。
///
/// hover 只改变 tonal surface（见 [CollectionCardPreview]），
/// 不做整体缩放，也没有周期性 shimmer。点击后立即取消 hover 状态，
/// 避免离场时残留放大或高亮。
class ContentCard extends ConsumerStatefulWidget {
  const ContentCard({
    super.key,
    required this.content,
    this.onTap,
    this.onDeleted,
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
  final VoidCallback? onDeleted;
  final VoidCallback? onLongPress;
  final GestureLongPressStartCallback? onSelectionStart;
  final GestureLongPressMoveUpdateCallback? onSelectionMove;
  final GestureLongPressEndCallback? onSelectionEnd;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isList;
  final bool isActive;

  @override
  ConsumerState<ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends ConsumerState<ContentCard> {
  bool _isHovered = false;

  Future<void> _delete() async {
    final confirmed = await confirmContentDeletion(context);
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(contentActionsProvider.notifier)
        .deleteContent(widget.content.id);
    if (result.ok) widget.onDeleted?.call();
    if (mounted) {
      Toast.show(context, result.message, isError: !result.ok);
    }
  }

  void _handleTap() {
    widget.onTap?.call();
    setState(() => _isHovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SwipeActionReveal(
      actions: widget.isSelectionMode
          ? []
          : [
              SwipeAction(
                label: '推送',
                icon: Icons.send_rounded,
                background: colors.tertiaryContainer,
                foreground: colors.onTertiaryContainer,
                onPressed: () =>
                    showPushContentDialog(context, [widget.content.id]),
              ),
              if (widget.onLongPress != null)
                SwipeAction(
                  label: '选择',
                  icon: Icons.check_circle_outline_rounded,
                  background: colors.secondaryContainer,
                  foreground: colors.onSecondaryContainer,
                  onPressed: widget.onLongPress!,
                ),
              SwipeAction(
                label: '删除',
                icon: Icons.delete_outline_rounded,
                background: colors.errorContainer,
                foreground: colors.onErrorContainer,
                onPressed: _delete,
              ),
            ],
      resetKey: (widget.content.id, widget.isSelectionMode, widget.isActive),
      builder: (context, showActions) => Semantics(
        selected: widget.isSelectionMode ? widget.isSelected : widget.isActive,
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (!widget.isSelectionMode &&
                event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                    (event.logicalKey == LogicalKeyboardKey.f10 &&
                        HardwareKeyboard.instance.isShiftPressed))) {
              showActions();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onSecondaryTap: widget.isSelectionMode ? null : showActions,
              onLongPress: widget.onSelectionStart == null
                  ? widget.onLongPress
                  : null,
              onLongPressStart: widget.onSelectionStart,
              onLongPressMoveUpdate: widget.onSelectionMove,
              onLongPressEnd: widget.onSelectionEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CollectionCardPreview(
                    content: widget.content,
                    onTap: widget.onTap == null ? null : _handleTap,
                    isHovered: !widget.isSelectionMode && _isHovered,
                    transparentSurface: widget.isSelectionMode,
                    isList: widget.isList,
                    isEmphasized: widget.isSelectionMode
                        ? false
                        : widget.isActive,
                    trailingSpace: widget.isSelectionMode ? 28 : 0,
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
        ),
      ),
    );
  }
}

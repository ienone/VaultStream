import 'package:flutter/material.dart';

import '../../../../theme/design_tokens.dart';
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
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isList = false,
    this.isActive = false,
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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
    setState(() => _isHovered = false);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      selected: widget.isSelectionMode ? widget.isSelected : widget.isActive,
      child: Container(
        foregroundDecoration: BoxDecoration(
          color: widget.isActive ? scheme.primary.withValues(alpha: .06) : null,
          borderRadius: AppShape.cardBorder,
          border: widget.isActive
              ? Border.all(color: scheme.primary, width: 2)
              : null,
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onLongPress: widget.onLongPress,
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    right: widget.isSelectionMode ? 40 : 0,
                  ),
                  child: CollectionCardPreview(
                    content: widget.content,
                    onTap: widget.onTap == null ? null : _handleTap,
                    isHovered: _isHovered,
                    isList: widget.isList,
                  ),
                ),
                if (widget.isSelectionMode)
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? scheme.primary
                            : scheme.surface.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: widget.isSelected
                          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                          : const SizedBox(width: 16, height: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

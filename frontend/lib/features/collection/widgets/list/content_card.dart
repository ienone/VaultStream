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

    final selected = widget.isSelectionMode
        ? widget.isSelected
        : widget.isActive;
    return Semantics(
      selected: selected,
      checked: widget.isSelectionMode ? widget.isSelected : null,
      child: ClipRRect(
        borderRadius: AppShape.cardBorder,
        child: Stack(
          children: [
            Container(
              foregroundDecoration: BoxDecoration(
                color: selected ? scheme.primary.withValues(alpha: .08) : null,
                borderRadius: AppShape.cardBorder,
                border: selected
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  right: widget.isSelectionMode ? 48 : 0,
                ),
                child: CollectionCardPreview(
                  content: widget.content,
                  isHovered: _isHovered,
                  isList: widget.isList,
                ),
              ),
            ),
            if (widget.isSelectionMode)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? scheme.primary
                            : scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: widget.isSelected
                          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                          : const SizedBox(width: 16, height: 16),
                    ),
                  ),
                ),
              ),
            // Paint ink above the preview, including opaque covers and badges.
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: AppShape.cardBorder,
                  onTap: widget.onTap == null ? null : _handleTap,
                  onLongPress: widget.onLongPress,
                  onHover: (hovered) => setState(() => _isHovered = hovered),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

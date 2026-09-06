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
  });

  final ShareCard content;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isList;

  @override
  State<ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<ContentCard> {
  bool _isHovered = false;
  bool _isNavigating = false;

  void _handleTap() {
    if (_isNavigating) return;
    setState(() {
      _isNavigating = true;
      _isHovered = false;
    });
    widget.onTap?.call();

    Future<void>.delayed(AppMotion.containerTransform, () {
      if (!mounted) return;
      setState(() => _isNavigating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveHover = _isHovered && !_isNavigating;

    return MouseRegion(
      onEnter: (_) {
        if (!_isNavigating) setState(() => _isHovered = true);
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: widget.isSelectionMode ? 40 : 0),
              child: CollectionCardPreview(
                content: widget.content,
                onTap: widget.onTap == null ? null : _handleTap,
                isHovered: effectiveHover,
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
    );
  }
}

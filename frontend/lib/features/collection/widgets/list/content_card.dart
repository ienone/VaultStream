import 'package:flutter/material.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../models/content.dart';
import 'collection_card_preview.dart';

class ContentCard extends StatefulWidget {
  final ShareCard content;
  final VoidCallback? onTap;
  final int index;

  const ContentCard({
    super.key,
    required this.content,
    this.onTap,
    this.index = 0,
  });

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

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _isNavigating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = ResponsiveLayout.getCardWidth(context);
    final isTinyCard = cardWidth < 220;
    final isLandscapeCover = widget.content.isLandscapeCover;
    final imageAspectRatio = isLandscapeCover ? 1.77 : 0.85;
    final cardAspectRatio = isLandscapeCover
        ? (isTinyCard ? 0.82 : 0.92)
        : (isTinyCard ? 0.48 : 0.54);
    final effectiveHover = _isHovered && !_isNavigating;

    return MouseRegion(
      onEnter: (_) {
        if (!_isNavigating) setState(() => _isHovered = true);
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: effectiveHover ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: AspectRatio(
          aspectRatio: cardAspectRatio,
          child: CollectionCardPreview(
            content: widget.content,
            onTap: widget.onTap == null ? null : _handleTap,
            isHovered: effectiveHover,
            isTinyCardOverride: isTinyCard,
            imageAspectRatioOverride: imageAspectRatio,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../theme/design_tokens.dart';

/// 收藏库加载骨架。
///
/// 与浏览网格或阅读侧列使用相同列数。
/// 骨架只用于真实等待，不与内容同时显示。
class CollectionSkeleton extends StatelessWidget {
  const CollectionSkeleton({super.key, this.columns = 1});

  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final gutter = columns == 1 ? AppSpacing.xs : AppSpacing.sm;
        final horizontalPadding = columns == 1 ? AppSpacing.sm : AppSpacing.md;
        final itemHeight = 132.0 * textScale;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppSpacing.xs,
            horizontalPadding,
            AppSpacing.md,
          ),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gutter,
            crossAxisSpacing: gutter,
            mainAxisExtent: itemHeight,
          ),
          itemCount: columns * 3,
          itemBuilder: (context, index) => const _SkeletonCard(),
        );
      },
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.skeletonPulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: AppShape.cardBorder,
      ),
    );

    // 减少动效开启时保持静态，不依赖闪烁传达"正在加载"。
    if (MediaQuery.disableAnimationsOf(context)) return card;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.75).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.ambientCurve),
      ),
      child: card,
    );
  }
}

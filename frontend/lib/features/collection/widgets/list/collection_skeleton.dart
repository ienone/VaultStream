import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../../core/layout/responsive_layout.dart';

class CollectionSkeleton extends StatelessWidget {
  const CollectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 15;
    return MasonryGridView.count(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 100),
      crossAxisCount: ResponsiveLayout.getColumnCount(context),
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      itemCount: 8,
      itemBuilder: (context, index) => _SkeletonItem(index: index),
    );
  }
}

class _SkeletonItem extends StatefulWidget {
  final int index;
  const _SkeletonItem({required this.index});

  @override
  State<_SkeletonItem> createState() => _SkeletonItemState();
}

class _SkeletonItemState extends State<_SkeletonItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = 180.0 + (widget.index % 3) * 40;
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 0.6).animate(_controller),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

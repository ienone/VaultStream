import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../models/content.dart';
import 'content_card.dart';

class CollectionGrid extends StatelessWidget {
  final List<ShareCard> items;
  final ScrollController scrollController;
  final bool hasMore;
  final bool isLoadingMore;
  final RefreshCallback onRefresh;

  const CollectionGrid({
    super.key,
    required this.items,
    required this.scrollController,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 15;
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: topPadding + 45,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(24, topPadding, 24, 20),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: ResponsiveLayout.getColumnCount(context),
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              itemBuilder: (context, index) {
                final item = items[index];
                return ContentCard(
                  content: item,
                  onTap: () {
                    final colorParam = item.coverColor != null
                        ? '?color=${Uri.encodeComponent(item.coverColor!)}'
                        : '';
                    context.push('/collection/${item.id}$colorParam');
                  },
                );
              },
              childCount: items.length,
            ),
          ),
          if (hasMore || isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 120, top: 20),
                child: Center(
                  child: isLoadingMore
                      ? const CircularProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

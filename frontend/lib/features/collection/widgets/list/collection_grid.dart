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
  final bool isSelectionMode;
  final Set<int> selectedIds;
  final ValueChanged<int>? onToggleSelection;
  final ValueChanged<int>? onLongPress;

  const CollectionGrid({
    super.key,
    required this.items,
    required this.scrollController,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onRefresh,
    this.isSelectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelection,
    this.onLongPress,
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
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 20),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: ResponsiveLayout.getColumnCount(context),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = selectedIds.contains(item.id);
                return GestureDetector(
                  onLongPress: onLongPress != null
                      ? () => onLongPress!(item.id)
                      : null,
                  child: Stack(
                    children: [
                      ContentCard(
                        content: item,
                        index: index,
                        onTap: isSelectionMode
                            ? () => onToggleSelection?.call(item.id)
                            : () {
                                final colorParam = item.coverColor != null
                                    ? '?color=${Uri.encodeComponent(item.coverColor!)}'
                                    : '';
                                context.push('/collection/${item.id}$colorParam');
                              },
                      ),
                      if (isSelectionMode)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: isSelected
                                  ? Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    )
                                  : const SizedBox(width: 16, height: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
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

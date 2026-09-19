import 'package:flutter/material.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import 'content_card.dart';

/// 浏览时按行组织卡片，阅读时显示单列；共用数据、分页和选择动作。
class CollectionList extends StatelessWidget {
  const CollectionList({
    super.key,
    required this.items,
    required this.scrollController,
    required this.isLoadingMore,
    required this.onRefresh,
    required this.onOpenContent,
    required this.emptyState,
    this.columns = 1,
    this.activeId,
    this.isSelectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelection,
    this.onLongPress,
    this.onLoadMore,
  });

  final List<ShareCard> items;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final RefreshCallback onRefresh;
  final ValueChanged<ShareCard> onOpenContent;
  final int columns;
  final int? activeId;
  final bool isSelectionMode;
  final Set<int> selectedIds;
  final ValueChanged<int>? onToggleSelection;
  final ValueChanged<int>? onLongPress;
  final VoidCallback? onLoadMore;
  final Widget emptyState;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: CustomScrollView(
      key: PageStorageKey(
        activeId == null ? 'collection-overview' : 'collection-list',
      ),
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (items.isEmpty && !isLoadingMore)
          SliverFillRemaining(hasScrollBody: false, child: emptyState)
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              columns == 1 ? AppSpacing.sm : AppSpacing.md,
              AppSpacing.xs,
              columns == 1 ? AppSpacing.sm : AppSpacing.md,
              isSelectionMode ? 96 : AppSpacing.md,
            ),
            sliver: SliverList.separated(
              itemCount: (items.length / columns).ceil(),
              separatorBuilder: (_, _) => SizedBox(
                height: columns == 1 ? AppSpacing.xs : AppSpacing.sm,
              ),
              itemBuilder: (context, row) => columns == 1
                  ? _buildCard(items[row])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: row * columns + column < items.length
                                ? _buildCard(items[row * columns + column])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        if (isLoadingMore || onLoadMore != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: isLoadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('加载更多'),
                      ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildCard(ShareCard item) => ContentCard(
    key: ValueKey(item.id),
    content: item,
    isList: columns == 1,
    isSelectionMode: isSelectionMode,
    isSelected: selectedIds.contains(item.id),
    isActive: activeId == item.id,
    onLongPress: onLongPress == null ? null : () => onLongPress!(item.id),
    onTap: isSelectionMode
        ? () => onToggleSelection?.call(item.id)
        : () => onOpenContent(item),
  );
}

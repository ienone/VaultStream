import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import 'content_card.dart';

/// 收藏库内容网格。
///
/// 使用等节奏的自适应网格而不是瀑布流：混合内容需要稳定的阅读顺序
/// 和视觉基线，瀑布流会让高度不断变化并导致重复布局测量。
/// 列数依据组件自身可用宽度（见 [ResponsiveLayout.contentGridColumns]），
/// 因此存在导航栏或侧栏时仍然正确。
class CollectionGrid extends StatelessWidget {
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
    this.emptyState,
  });

  final List<ShareCard> items;
  final ScrollController scrollController;
  final bool hasMore;
  final bool isLoadingMore;
  final RefreshCallback onRefresh;
  final bool isSelectionMode;
  final Set<int> selectedIds;
  final ValueChanged<int>? onToggleSelection;
  final ValueChanged<int>? onLongPress;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final widthClass = ResponsiveLayout.widthClassFor(width);
        final isCompact = widthClass.isCompact;

        // 极窄屏收紧间距并弱化卡片边界；宽屏恢复正常呼吸感。
        final gutter = isCompact ? AppSpacing.xs : AppSpacing.sm;
        final horizontalPadding = isCompact ? AppSpacing.sm : AppSpacing.md;

        final columns = ResponsiveLayout.contentGridColumns(width);
        final itemWidth =
            (width - horizontalPadding * 2 - gutter * (columns - 1)) / columns;
        final isTiny = itemWidth < 200;
        // 媒体区 16:9，文本区高度固定，保证每行基线一致。
        final itemHeight = itemWidth * 9 / 16 + (isTiny ? 112 : 140);

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (items.isEmpty && !isLoadingMore)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: emptyState ?? const _DefaultEmptyState(),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.xs,
                    horizontalPadding,
                    AppSpacing.md,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: gutter,
                          crossAxisSpacing: gutter,
                          mainAxisExtent: itemHeight,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ContentCard(
                        content: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedIds.contains(item.id),
                        onLongPress: onLongPress == null
                            ? null
                            : () => onLongPress!(item.id),
                        onTap: isSelectionMode
                            ? () => onToggleSelection?.call(item.id)
                            : () => _openDetail(context, item),
                      );
                    },
                  ),
                ),
              if (isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              // 为 FAB 与底部导航留出安全距离。
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
    );
  }

  void _openDetail(BuildContext context, ShareCard item) {
    final color = item.coverColor;
    final query = color == null
        ? ''
        : '?color=${Uri.encodeComponent(color)}';
    context.push('/collection/${item.id}$query', extra: item);
  }
}

class _DefaultEmptyState extends StatelessWidget {
  const _DefaultEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '这里空空如也',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

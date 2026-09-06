import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import 'content_card.dart';

/// 收藏库内容网格。
///
/// 手机使用自然高度列表，宽屏按行组织卡片；无封面不制造媒体占位。
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
        final isCompact =
            widthClass.isCompact || WindowMetrics.of(context).isShortLandscape;

        // 极窄屏收紧间距并弱化卡片边界；宽屏恢复正常呼吸感。
        final gutter = isCompact ? AppSpacing.xs : AppSpacing.sm;
        final horizontalPadding = isCompact ? AppSpacing.sm : AppSpacing.md;

        final columns = isCompact
            ? 1
            : ResponsiveLayout.contentGridColumns(width);

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
                    isSelectionMode ? 96 : AppSpacing.md,
                  ),
                  sliver: isCompact
                      ? SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) =>
                              _buildCard(context, items[index], true),
                        )
                      : SliverList.separated(
                          itemCount: (items.length / columns).ceil(),
                          separatorBuilder: (_, _) => SizedBox(height: gutter),
                          itemBuilder: (context, row) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var column = 0;
                                column < columns;
                                column++
                              ) ...[
                                if (column > 0) SizedBox(width: gutter),
                                Expanded(
                                  child: row * columns + column < items.length
                                      ? _buildCard(
                                          context,
                                          items[row * columns + column],
                                          false,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              if (isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, ShareCard item, bool isList) =>
      ContentCard(
        key: ValueKey(item.id),
        content: item,
        isList: isList,
        isSelectionMode: isSelectionMode,
        isSelected: selectedIds.contains(item.id),
        onLongPress: onLongPress == null ? null : () => onLongPress!(item.id),
        onTap: isSelectionMode
            ? () => onToggleSelection?.call(item.id)
            : () => _openDetail(context, item),
      );

  void _openDetail(BuildContext context, ShareCard item) {
    final color = item.coverColor;
    final query = color == null ? '' : '?color=${Uri.encodeComponent(color)}';
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
            '没有内容',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

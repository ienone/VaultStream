import '../../layout/root_page_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive_layout.dart';
import '../../theme/design_tokens.dart';
import 'providers/batch_selection_provider.dart';
import 'providers/collection_filter_provider.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
import 'widgets/detail/detail_sections.dart';
import 'widgets/dialogs/batch_action_sheet.dart';
import 'widgets/dialogs/collection_filter_form.dart';
import 'widgets/dialogs/collection_filter_sheet.dart';
import 'widgets/list/collection_grid.dart';
import 'widgets/list/collection_search_entry.dart';
import 'widgets/list/collection_skeleton.dart';

/// 收藏库。
///
/// 首屏只回答一个问题：怎样找到并打开已经保存的内容。
/// 顶栏保留标题与一个统一搜索入口，已生效筛选以可横向滚动的摘要行呈现，
/// 高级筛选进入 bottom sheet / side sheet，不常驻占据首屏。
class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({
    super.key,
    this.initialPlatforms = const [],
    this.initialStatuses = const [],
    this.initialAuthor,
    this.initialTags = const [],
    this.initialDateRange,
  });

  final List<String> initialPlatforms;
  final List<String> initialStatuses;
  final String? initialAuthor;
  final List<String> initialTags;
  final DateTimeRange? initialDateRange;

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  final ScrollController _scrollController = ScrollController();
  final SearchController _searchController = SearchController();
  String? _lastAppliedRouteFilterSignature;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyRouteFilters();
      if (mounted) {
        _syncSearchText(ref.read(collectionFilterProvider).searchQuery);
      }
    });
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRouteFilters());
  }

  /// 路由 query 是筛选的可分享表示，只在 query 真正变化时覆盖当前筛选。
  void _applyRouteFilters() {
    if (!mounted) return;
    final signature = _routeFilterSignature;
    if (_lastAppliedRouteFilterSignature == signature) return;
    _lastAppliedRouteFilterSignature = signature;

    final hasRouteFilter =
        widget.initialPlatforms.isNotEmpty ||
        widget.initialStatuses.isNotEmpty ||
        widget.initialAuthor?.trim().isNotEmpty == true ||
        widget.initialTags.isNotEmpty ||
        widget.initialDateRange != null;
    if (!hasRouteFilter) return;

    ref
        .read(collectionFilterProvider.notifier)
        .setFilters(
          platforms: widget.initialPlatforms,
          statuses: widget.initialStatuses,
          author: widget.initialAuthor,
          tags: widget.initialTags,
          dateRange: widget.initialDateRange,
        );
  }

  String get _routeFilterSignature => [
    widget.initialPlatforms.join(','),
    widget.initialStatuses.join(','),
    widget.initialAuthor ?? '',
    widget.initialTags.join(','),
    widget.initialDateRange?.start.toIso8601String() ?? '',
    widget.initialDateRange?.end.toIso8601String() ?? '',
  ].join('|');

  @override
  void dispose() {
    // 离开页面时不清空筛选：从详情返回必须恢复原有查询与结果。
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 320) {
      ref.read(collectionProvider.notifier).fetchMore();
    }
  }

  Future<void> _refresh() => ref.refresh(collectionProvider.future);

  void _performSearch(String query, {String? mode}) {
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).add(trimmed);
    }
    final notifier = ref.read(collectionFilterProvider.notifier);
    if (mode != null) notifier.setSearchMode(mode);
    notifier.updateSearchQuery(trimmed);
    if (_searchController.isAttached && _searchController.isOpen) {
      _searchController.closeView(trimmed);
    }
  }

  void _syncSearchText(String query) {
    if (_searchController.text == query) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  Future<void> _openSearchPage() async {
    final initialQuery = ref.read(collectionFilterProvider).searchQuery;
    final result = await Navigator.of(context, rootNavigator: true)
        .push<CollectionSearchSelection>(
          MaterialPageRoute(
            builder: (_) => CollectionSearchPage(initialQuery: initialQuery),
          ),
        );
    if (!mounted) return;
    if (result != null) {
      _performSearch(result.query, mode: result.mode);
    }
    _restoreSearchText();
  }

  void _restoreSearchText() {
    _syncSearchText(ref.read(collectionFilterProvider).searchQuery);
    _searchController.selection = const TextSelection.collapsed(offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(collectionFilterProvider);
    ref.listen<String>(
      collectionFilterProvider.select((state) => state.searchQuery),
      (_, query) => _syncSearchText(query),
    );
    if (_searchController.isAttached && !_searchController.isOpen) {
      _syncSearchText(filter.searchQuery);
    }
    final collectionAsync = ref.watch(collectionProvider);
    final selection = ref.watch(batchSelectionProvider);
    final compact = _searchBelowToolbar(context);

    return Scaffold(
      appBar: selection.isSelectionMode
          ? _buildSelectionAppBar(selection)
          : _buildAppBar(filter),
      body: Column(
        children: [
          if (!selection.isSelectionMode && compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: CollectionSearchEntry(
                controller: _searchController,
                filter: filter,
                onSubmit: _performSearch,
                onClose: _restoreSearchText,
                onOpenPage: _openSearchPage,
              ),
            ),
          if (!selection.isSelectionMode)
            _ActiveFilterBar(
              filter: filter,
              resultTotal: collectionAsync.value?.total,
            ),
          Expanded(
            child: collectionAsync.when(
              skipLoadingOnRefresh: true,
              data: (response) => CollectionGrid(
                items: response.items,
                scrollController: _scrollController,
                hasMore: response.hasMore,
                isLoadingMore:
                    collectionAsync.isLoading && response.items.isNotEmpty,
                onRefresh: _refresh,
                isSelectionMode: selection.isSelectionMode,
                selectedIds: selection.selectedIds,
                onToggleSelection: (id) => ref
                    .read(batchSelectionProvider.notifier)
                    .toggleSelection(id),
                onLongPress: (id) {
                  final notifier = ref.read(batchSelectionProvider.notifier);
                  notifier.enterSelectionMode();
                  notifier.toggleSelection(id);
                },
                emptyState: _buildEmptyState(filter),
              ),
              loading: () => const CollectionSkeleton(),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ContentEmptyState(
                    icon: Icons.cloud_off_rounded,
                    message: '无法加载收藏库',
                    hint: error.toString(),
                    action: FilledButton.tonal(
                      onPressed: () => ref.invalidate(collectionProvider),
                      child: const Text('重试'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: selection.isSelectionMode
          ? FloatingActionButton.extended(
              onPressed: selection.isProcessing || selection.count == 0
                  ? null
                  : () => showBatchActions(context),
              icon: const Icon(Icons.checklist_rounded),
              label: Text('操作 (${selection.count})'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(CollectionFilterState filter) {
    final filtered = filter.hasActiveFilters || filter.searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ContentEmptyState(
          icon: filtered ? Icons.search_off_rounded : Icons.inbox_outlined,
          message: filtered ? '没有符合条件的内容' : '尚未保存内容',
          hint: filtered ? null : '点击“保存”添加内容。',
          action: filtered
              ? TextButton(
                  onPressed: () => ref
                      .read(collectionFilterProvider.notifier)
                      .clearFilters(),
                  child: const Text('清除全部筛选'),
                )
              : null,
        ),
      ),
    );
  }

  // --- 顶栏 ---

  bool _searchBelowToolbar(BuildContext context) =>
      MediaQuery.sizeOf(context).width /
          (MediaQuery.textScalerOf(context).scale(16) / 16) <
      ResponsiveLayout.largeBreakpoint;

  PreferredSizeWidget _buildAppBar(CollectionFilterState filter) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = _searchBelowToolbar(context);

    return AppBar(
      toolbarHeight: WindowMetrics.of(context).heightClass.isCompact
          ? 48
          : null,
      title: compact
          ? const Text('收藏库')
          : Row(
              children: [
                const Text('收藏库'),
                const SizedBox(width: AppSpacing.lg),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: width < 840 ? 260 : 360,
                      child: CollectionSearchEntry(
                        controller: _searchController,
                        filter: filter,
                        onSubmit: _performSearch,
                        onClose: _restoreSearchText,
                        onOpenPage: _openSearchPage,
                      ),
                    ),
                  ),
                ),
              ],
            ),
      actions: [
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refresh,
        ),
        IconButton(
          tooltip: '筛选',
          isSelected: filter.hasActiveFilters,
          icon: const Icon(Icons.tune_rounded),
          selectedIcon: const Icon(Icons.tune_rounded),
          onPressed: _openFilters,
        ),
        const RootPageActions(),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(BatchSelectionState selection) {
    return AppBar(
      toolbarHeight: WindowMetrics.of(context).heightClass.isCompact
          ? 48
          : null,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      leading: IconButton(
        tooltip: '退出选择',
        icon: const Icon(Icons.close_rounded),
        onPressed: selection.isProcessing
            ? null
            : () =>
                  ref.read(batchSelectionProvider.notifier).exitSelectionMode(),
      ),
      title: Text('已选择 ${selection.count} 项'),
      actions: [
        IconButton(
          tooltip: '全选',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: selection.isProcessing
              ? null
              : () {
                  final items = ref.read(collectionProvider).value?.items ?? [];
                  ref
                      .read(batchSelectionProvider.notifier)
                      .selectAll(items.map((e) => e.id).toList());
                },
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  /// 高级筛选：Compact 使用接近全高的 bottom sheet，Expanded 使用 side sheet。
  Future<void> _openFilters() async {
    final filter = ref.read(collectionFilterProvider);
    final items = ref.read(collectionProvider).value?.items ?? const [];
    final availableTags = <String>{
      for (final item in items) ...item.tags,
    }.toList();

    final dialog = CollectionFilterForm(
      initialPlatforms: filter.platforms,
      initialStatuses: filter.statuses,
      initialAuthor: filter.author,
      initialDateRange: filter.dateRange,
      initialTags: filter.tags,
      initialSearchMode: filter.searchMode,
      initialSemanticTopK: filter.semanticTopK,
      initialSemanticScope: filter.semanticScope,
      availableTags: availableTags,
    );

    final result = await showCollectionFilters(context, child: dialog);

    if (result == null || !mounted) return;
    ref
        .read(collectionFilterProvider.notifier)
        .setFilters(
          platforms: (result['platforms'] as List<dynamic>?)?.cast<String>(),
          statuses: (result['statuses'] as List<dynamic>?)?.cast<String>(),
          author: result['author'] as String?,
          dateRange: result['dateRange'] as DateTimeRange?,
          tags: (result['tags'] as List<dynamic>?)?.cast<String>(),
          searchMode: result['searchMode'] as String?,
          semanticTopK: result['semanticTopK'] as int?,
          semanticScope: result['semanticScope'] as String?,
        );
  }
}

/// 已生效筛选摘要行。
///
/// 一行可横向滚动，逐项可移除；没有任何筛选时完全不占位。
class _ActiveFilterBar extends ConsumerWidget {
  const _ActiveFilterBar({required this.filter, required this.resultTotal});

  final CollectionFilterState filter;
  final int? resultTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(collectionFilterProvider.notifier);
    final theme = Theme.of(context);
    final chips = <Widget>[];

    if (filter.searchQuery.isNotEmpty) {
      chips.add(
        _FilterChip(
          label: '${filter.isSemantic ? '语义' : '关键词'}: ${filter.searchQuery}',
          icon: Icons.search_rounded,
          onRemove: () => notifier.updateSearchQuery(''),
        ),
      );
    }
    for (final platform in filter.platforms) {
      chips.add(
        _FilterChip(
          label: platform,
          onRemove: () => notifier.removePlatform(platform),
        ),
      );
    }
    for (final status in filter.statuses) {
      chips.add(
        _FilterChip(
          label: status,
          onRemove: () => notifier.removeStatus(status),
        ),
      );
    }
    for (final tag in filter.tags) {
      chips.add(
        _FilterChip(label: '#$tag', onRemove: () => notifier.removeTag(tag)),
      );
    }
    if (filter.author != null && filter.author!.isNotEmpty) {
      chips.add(
        _FilterChip(
          label: '作者: ${filter.author}',
          onRemove: notifier.clearAuthor,
        ),
      );
    }
    if (filter.dateRange != null) {
      final format = DateFormat('MM-dd');
      chips.add(
        _FilterChip(
          label:
              '${format.format(filter.dateRange!.start)} ~ '
              '${format.format(filter.dateRange!.end)}',
          onRemove: notifier.clearDateRange,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: chip,
                    ),
                ],
              ),
            ),
          ),
          if (resultTotal != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Text(
                '$resultTotal 条',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          TextButton(onPressed: notifier.clearFilters, child: const Text('清除')),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove, this.icon});

  final String label;
  final VoidCallback onRemove;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Chip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        deleteButtonTooltipMessage: '移除筛选 $label',
        onDeleted: onRemove,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

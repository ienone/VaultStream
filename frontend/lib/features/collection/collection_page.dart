import '../../layout/root_page_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive_layout.dart';
import '../../theme/design_tokens.dart';
import '../search/search_models.dart';
import 'models/content.dart';
import 'providers/batch_selection_provider.dart';
import 'providers/collection_filter_provider.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
import 'widgets/detail/detail_sections.dart';
import 'widgets/dialogs/batch_action_sheet.dart';
import 'widgets/dialogs/collection_filter_sheet.dart';
import 'widgets/list/collection_list.dart';
import 'widgets/list/collection_search_entry.dart';
import 'widgets/list/collection_skeleton.dart';
import 'widgets/list/collection_workspace.dart';

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
    this.selectedContentId,
  });

  final List<String> initialPlatforms;
  final List<String> initialStatuses;
  final String? initialAuthor;
  final List<String> initialTags;
  final DateTimeRange? initialDateRange;
  final int? selectedContentId;

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String? _lastAppliedRouteFilterSignature;
  LocalHistoryEntry? _readerHistory;
  ShareCard? _preview;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyRouteFilters();
      if (mounted) {
        _syncReaderHistory();
        _syncSearchText(ref.read(collectionFilterProvider).searchQuery);
      }
    });
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyRouteFilters();
      if (mounted) _syncReaderHistory();
    });
  }

  void _syncReaderHistory() {
    if (widget.selectedContentId == null) {
      final entry = _readerHistory;
      _readerHistory = null;
      entry?.remove();
    } else if (_readerHistory == null) {
      late final LocalHistoryEntry entry;
      entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (_readerHistory != entry) return;
          _readerHistory = null;
          _closeReader();
        },
      );
      _readerHistory = entry;
      ModalRoute.of(context)!.addLocalHistoryEntry(entry);
    }
  }

  void _openContent(ShareCard content) {
    if (content.id == widget.selectedContentId) return;
    _preview = content;
    final uri = GoRouterState.of(context).uri;
    final location = uri
        .replace(
          queryParameters: {
            ...uri.queryParametersAll,
            'item': [content.id.toString()],
          },
        )
        .toString();
    if (widget.selectedContentId == null) {
      context.go(location);
    } else {
      context.replace(location);
    }
  }

  void _closeReader() {
    final uri = GoRouterState.of(context).uri;
    final query = {...uri.queryParametersAll}..remove('item');
    context.replace(uri.replace(queryParameters: query).toString());
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
    final entry = _readerHistory;
    _readerHistory = null;
    entry?.remove();
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

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).add(trimmed);
    }
    final notifier = ref.read(collectionFilterProvider.notifier);
    notifier.updateSearchQuery(trimmed);
    FocusScope.of(context).unfocus();
  }

  void _syncSearchText(String query) {
    if (_searchController.text == query) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _openSearchPage() {
    final request = ref
        .read(collectionFilterProvider)
        .toSearchRequest()
        .copyWith(query: _searchController.text.trim(), kind: 'all');
    FocusScope.of(context).unfocus();
    context.push(request.toUri('/search').toString());
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(collectionFilterProvider);
    ref.listen<String>(
      collectionFilterProvider.select((state) => state.searchQuery),
      (_, query) => _syncSearchText(query),
    );
    final collectionAsync = ref.watch(collectionProvider);
    final selection = ref.watch(batchSelectionProvider);
    return CollectionWorkspace(
      selectedId: widget.selectedContentId,
      preview: _preview?.id == widget.selectedContentId ? _preview : null,
      onClose: _closeReader,
      list: LayoutBuilder(
        builder: (context, constraints) {
          final compact = _searchBelowToolbar(constraints.maxWidth);
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = widget.selectedContentId == null
              ? (constraints.maxWidth / (360 * textScale)).floor().clamp(1, 4)
              : 1;
          return Scaffold(
            appBar: selection.isSelectionMode
                ? _buildSelectionAppBar(selection)
                : _buildAppBar(filter, constraints.maxWidth),
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
                      onSubmit: _performSearch,
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
                    data: (response) => CollectionList(
                      items: response.items,
                      columns: columns,
                      onOpenContent: _openContent,
                      activeId: widget.selectedContentId,
                      scrollController: _scrollController,
                      isLoadingMore:
                          collectionAsync.isLoading &&
                          response.items.isNotEmpty,
                      onLoadMore: response.hasMore
                          ? ref.read(collectionProvider.notifier).fetchMore
                          : null,
                      onRefresh: _refresh,
                      isSelectionMode: selection.isSelectionMode,
                      selectedIds: selection.selectedIds,
                      onToggleSelection: (id) => ref
                          .read(batchSelectionProvider.notifier)
                          .toggleSelection(id),
                      onLongPress: (id) {
                        if (widget.selectedContentId != null) _closeReader();
                        final notifier = ref.read(
                          batchSelectionProvider.notifier,
                        );
                        notifier.enterSelectionMode();
                        notifier.toggleSelection(id);
                      },
                      emptyState: _buildEmptyState(filter),
                    ),
                    loading: () => CollectionSkeleton(columns: columns),
                    error: (error, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: ContentEmptyState(
                          icon: Icons.cloud_off_rounded,
                          message: '无法加载收藏库',
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
        },
      ),
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

  bool _searchBelowToolbar(double width) =>
      width / (MediaQuery.textScalerOf(context).scale(16) / 16) <
      ResponsiveLayout.expandedBreakpoint;

  PreferredSizeWidget _buildAppBar(CollectionFilterState filter, double width) {
    final compact = _searchBelowToolbar(width);

    return AppBar(
      leading: buildRootPageLeading(context),
      backgroundColor: Theme.of(context).colorScheme.surface,
      scrolledUnderElevation: 0,
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
                        onSubmit: _performSearch,
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
    final result = await editSearchFilters(context, filter.toSearchRequest());

    if (result == null || !mounted) return;
    ref
        .read(collectionFilterProvider.notifier)
        .setFilters(
          platforms: result.platforms,
          statuses: result.statuses,
          author: result.author,
          dateRange: result.dateFrom == null || result.dateTo == null
              ? null
              : DateTimeRange(start: result.dateFrom!, end: result.dateTo!),
          tags: result.tags,
          searchMode: result.mode,
          semanticTopK: result.topK,
          semanticScope: result.contentScope,
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

    if (filter.semanticScope != 'library') {
      chips.add(
        _FilterChip(
          label: filter.semanticScope == 'discovery' ? '范围：发现' : '范围：全部内容',
          onRemove: () => notifier.setSemanticScope('library'),
        ),
      );
    }
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
          label: searchPlatformLabels[platform] ?? platform,
          onRemove: () => notifier.removePlatform(platform),
        ),
      );
    }
    for (final status in filter.statuses) {
      chips.add(
        _FilterChip(
          label: searchStatusLabels[status] ?? status,
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

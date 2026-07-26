import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/utils/toast.dart';
import '../../theme/design_tokens.dart';
import 'providers/batch_selection_provider.dart';
import 'providers/collection_filter_provider.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
import 'widgets/detail/detail_sections.dart';
import 'widgets/dialogs/add_content_dialog.dart';
import 'widgets/dialogs/batch_action_sheet.dart';
import 'widgets/dialogs/filter_dialog.dart';
import 'widgets/list/collection_grid.dart';
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
    this.initialDateRange,
  });

  final List<String> initialPlatforms;
  final List<String> initialStatuses;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRouteFilters());
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
        widget.initialDateRange != null;
    if (!hasRouteFilter) return;

    ref
        .read(collectionFilterProvider.notifier)
        .setFilters(
          platforms: widget.initialPlatforms,
          statuses: widget.initialStatuses,
          dateRange: widget.initialDateRange,
        );
  }

  String get _routeFilterSignature => [
    widget.initialPlatforms.join(','),
    widget.initialStatuses.join(','),
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
    if (_searchController.isOpen) _searchController.closeView(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(collectionFilterProvider);
    final collectionAsync = ref.watch(collectionProvider);
    final selection = ref.watch(batchSelectionProvider);
    final compact = MediaQuery.sizeOf(context).width < 600;

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
              child: SizedBox(
                height: 44,
                child: _SearchEntry(
                  controller: _searchController,
                  filter: filter,
                  onSubmit: _performSearch,
                ),
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
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppShape.sheetTopBorder,
                ),
                builder: (_) => const BatchActionSheet(),
              ),
              icon: const Icon(Icons.checklist_rounded),
              label: Text('操作 (${selection.count})'),
            )
          : FloatingActionButton.extended(
              onPressed: _addContent,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加内容'),
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
          message: filtered ? '没有符合条件的内容' : '收藏库还是空的',
          hint: filtered ? '试着放宽筛选条件或换一个关键词。' : '保存第一条内容后，它会出现在这里。',
          action: filtered
              ? TextButton(
                  onPressed: () => ref
                      .read(collectionFilterProvider.notifier)
                      .clearFilters(),
                  child: const Text('清除全部筛选'),
                )
              : FilledButton.tonal(
                  onPressed: _addContent,
                  child: const Text('添加内容'),
                ),
        ),
      ),
    );
  }

  Future<void> _addContent() async {
    final added = await AddContentDialog.show(context);
    if (added == true && mounted) {
      Toast.show(context, '内容已添加到队列', icon: Icons.check_circle_outline_rounded);
    }
  }

  // --- 顶栏 ---

  PreferredSizeWidget _buildAppBar(CollectionFilterState filter) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;

    return AppBar(
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
                      height: 40,
                      child: _SearchEntry(
                        controller: _searchController,
                        filter: filter,
                        onSubmit: _performSearch,
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
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(BatchSelectionState selection) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () =>
            ref.read(batchSelectionProvider.notifier).exitSelectionMode(),
      ),
      title: Text('已选择 ${selection.count} 项'),
      actions: [
        IconButton(
          tooltip: '全选',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: () {
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
    final metrics = WindowMetrics.of(context);
    final items = ref.read(collectionProvider).value?.items ?? const [];
    final availableTags = <String>{
      for (final item in items) ...item.tags,
    }.toList();

    final dialog = FilterDialog(
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

    final result = metrics.widthClass.supportsSupportingPane
        ? await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 420,
                height: double.infinity,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: dialog,
                ),
              ),
            ),
          )
        : await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: AppShape.sheetTopBorder,
            ),
            constraints: const BoxConstraints(maxHeight: 720),
            builder: (_) => dialog,
          );

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

/// 统一搜索入口。
///
/// 搜索模式用文字说明"精确与全文"/"语义相关"，不再用图标让用户猜测，
/// 也不再在顶栏放一个独立的模式切换按钮。
class _SearchEntry extends ConsumerWidget {
  const _SearchEntry({
    required this.controller,
    required this.filter,
    required this.onSubmit,
  });

  final SearchController controller;
  final CollectionFilterState filter;
  final void Function(String query, {String? mode}) onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(searchHistoryProvider);

    return SearchAnchor(
      searchController: controller,
      viewHintText: '搜索标题、正文、作者或标签',
      builder: (context, ctrl) => SearchBar(
        controller: ctrl,
        hintText: filter.searchQuery.isEmpty ? '搜索收藏库' : filter.searchQuery,
        leading: const Icon(Icons.search_rounded),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        onTap: () {
          ctrl.text = filter.searchQuery;
          ctrl.openView();
        },
        onSubmitted: onSubmit,
      ),
      viewOnSubmitted: (value) => onSubmit(value),
      suggestionsBuilder: (context, ctrl) {
        final keyword = ctrl.text.trim();
        final history = historyAsync.value ?? const <String>[];

        return [
          if (keyword.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.manage_search_rounded),
              title: Text('精确与全文搜索 "$keyword"'),
              subtitle: const Text('匹配标题、正文和标签中的字面内容'),
              onTap: () => onSubmit(keyword, mode: 'keyword'),
            ),
            ListTile(
              leading: const Icon(Icons.psychology_alt_rounded),
              title: Text('语义相关搜索 "$keyword"'),
              subtitle: const Text('按含义查找相关内容，结果会标注命中来源'),
              onTap: () => onSubmit(keyword, mode: 'semantic'),
            ),
            const Divider(height: 1),
          ],
          for (final item in history.where(
            (h) => keyword.isEmpty || h.contains(keyword),
          ))
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(item),
              onTap: () => onSubmit(item),
            ),
        ];
      },
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
    return InputChip(
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: Text(label),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:animations/animations.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
import 'providers/collection_filter_provider.dart';
import 'providers/batch_selection_provider.dart';
import 'widgets/dialogs/add_content_dialog.dart';
import 'widgets/dialogs/filter_dialog.dart';
import 'widgets/dialogs/batch_action_sheet.dart';
import 'widgets/list/collection_grid.dart';
import 'widgets/list/collection_error_view.dart';
import 'widgets/list/collection_skeleton.dart';
import '../../core/network/sse_service.dart';
import '../../core/utils/toast.dart';

class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({super.key});

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isFabExtended = ValueNotifier(true);
  final SearchController _searchController = SearchController();
  DateTime? _lastScrollTime;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFiltersFromUrl();
    });
  }

  void _initFiltersFromUrl() {
    // Logic for deep linking if needed
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isFabExtended.dispose();
    _searchController.dispose();
    // Clear filters when leaving the page (Task 8)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(collectionFilterProvider.notifier).clearFilters();
      }
    });
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(collectionProvider.notifier).fetchMore();
    }
  }

  void _performSearch(String query) {
    if (query.trim().isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).add(query);
    }
    ref.read(collectionFilterProvider.notifier).updateSearchQuery(query);
    if (_searchController.isOpen) {
      _searchController.closeView(query);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (_isFabExtended.value) _isFabExtended.value = false;
      _lastScrollTime = DateTime.now();
    } else if (notification is ScrollEndNotification) {
      final scrollTime = DateTime.now();
      _lastScrollTime = scrollTime;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _lastScrollTime == scrollTime) {
          _isFabExtended.value = true;
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to SSE events for real-time updates
    ref.listen<AsyncValue<SseEvent>>(sseEventStreamProvider, (previous, next) {
      next.whenData((event) {
        if (event.type == 'content_updated') {
          ref.invalidate(collectionProvider);
        }
      });
    });

    final filterState = ref.watch(collectionFilterProvider);
    final collectionAsync = ref.watch(collectionProvider);
    final batchSelection = ref.watch(batchSelectionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: batchSelection.isSelectionMode
          ? _buildSelectionAppBar(context, theme, batchSelection)
          : _buildAppBar(context, theme, filterState),
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: collectionAsync.when(
          data: (response) => CollectionGrid(
            items: response.items,
            scrollController: _scrollController,
            hasMore: response.hasMore,
            isLoadingMore:
                collectionAsync.isLoading && response.items.isNotEmpty,
            onRefresh: () => ref.refresh(collectionProvider.future),
            isSelectionMode: batchSelection.isSelectionMode,
            selectedIds: batchSelection.selectedIds,
            onToggleSelection: (id) =>
                ref.read(batchSelectionProvider.notifier).toggleSelection(id),
            onLongPress: (id) {
              ref.read(batchSelectionProvider.notifier).enterSelectionMode();
              ref.read(batchSelectionProvider.notifier).toggleSelection(id);
            },
          ),
          loading: () => const CollectionSkeleton(),
          error: (err, stack) => CollectionErrorView(
            error: err.toString(),
            onRetry: () => ref.invalidate(collectionProvider),
          ),
        ),
      ),
      floatingActionButton: batchSelection.isSelectionMode
          ? FloatingActionButton.extended(
              onPressed: () => _showBatchActions(context),
              icon: const Icon(Icons.checklist_rounded),
              label: Text('操作 (${batchSelection.count})'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            )
          : _AddContentFab(isExtended: _isFabExtended),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
    BuildContext context,
    ThemeData theme,
    BatchSelectionState selection,
  ) {
    return AppBar(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () =>
            ref.read(batchSelectionProvider.notifier).exitSelectionMode(),
      ),
      title: Text(
        '已选择 ${selection.count} 项',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all_rounded),
          tooltip: '全选',
          onPressed: () {
            final items = ref.read(collectionProvider).value?.items ?? [];
            ref
                .read(batchSelectionProvider.notifier)
                .selectAll(items.map((e) => e.id).toList());
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _showBatchActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => const BatchActionSheet(),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    CollectionFilterState filterState,
  ) {
    return FrostedAppBar(
      blurSigma: 12,
      title: filterState.searchQuery.isNotEmpty
          ? GestureDetector(
              onTap: () => _searchController.openView(),
              child: Text(
                '${filterState.isSemantic ? '语义搜索' : '关键词搜索'}: ${filterState.searchQuery}',
                style: const TextStyle(fontSize: 16),
              ),
            )
          : const Text('收藏库'),
      actions: [
        _buildSearchAnchor(context, theme),
        IconButton(
          icon: Icon(
            filterState.isSemantic
                ? Icons.psychology_alt_rounded
                : Icons.manage_search_rounded,
          ),
          tooltip: filterState.isSemantic ? '切换到关键词搜索' : '切换到语义搜索',
          onPressed: () {
            final nextMode = filterState.isSemantic ? 'keyword' : 'semantic';
            ref.read(collectionFilterProvider.notifier).setSearchMode(nextMode);
          },
        ),
        if (filterState.searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              ref.read(collectionFilterProvider.notifier).updateSearchQuery('');
              _searchController.clear();
            },
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(collectionProvider),
        ),
        OpenContainer<Map<String, dynamic>>(
          transitionType: ContainerTransitionType.fade,
          openColor: theme.colorScheme.surface,
          closedColor: Colors.transparent,
          closedElevation: 0,
          onClosed: (result) {
            if (result != null) {
              ref.read(collectionFilterProvider.notifier).setFilters(
                    platforms: (result['platforms'] as List<dynamic>?)?.cast<String>(),
                    statuses: (result['statuses'] as List<dynamic>?)?.cast<String>(),
                    author: result['author'],
                    dateRange: result['dateRange'],
                    tags: (result['tags'] as List<dynamic>?)?.cast<String>(),
                    searchMode: result['searchMode'] as String?,
                    semanticTopK: result['semanticTopK'] as int?,
                  );
            }
          },
          openBuilder: (context, _) => FilterDialog(
            initialPlatforms: filterState.platforms,
            initialStatuses: filterState.statuses,
            initialAuthor: filterState.author,
            initialDateRange: filterState.dateRange,
            initialTags: filterState.tags,
            initialSearchMode: filterState.searchMode,
            initialSemanticTopK: filterState.semanticTopK,
            availableTags: _getAvailableTags(),
          ),
          closedBuilder: (context, openContainer) => IconButton(
            icon: Icon(
              Icons.filter_list_rounded,
              color: filterState.hasActiveFilters
                  ? theme.colorScheme.primary
                  : null,
            ),
            onPressed: openContainer,
          ),
        ),
      ],
    );
  }

  List<String> _getAvailableTags() {
    final collectionAsync = ref.read(collectionProvider);
    final availableTags = <String>{};
    if (collectionAsync.hasValue && collectionAsync.value != null) {
      for (final item in collectionAsync.value!.items) {
        availableTags.addAll(item.tags);
      }
    }
    return availableTags.toList();
  }


  Widget _buildSearchAnchor(BuildContext context, ThemeData theme) {
    final historyAsync = ref.watch(searchHistoryProvider);
    return SearchAnchor(
      searchController: _searchController,
      viewHintText: '搜索标题、描述、标签...',
      builder: (context, controller) => IconButton(
        icon: const Icon(Icons.search_rounded),
        onPressed: () => controller.openView(),
      ),
      suggestionsBuilder: (context, controller) {
        final keyword = controller.text;
        return historyAsync.when(
          data: (history) {
            final suggestions = keyword.isEmpty
                ? history
                : history.where((s) => s.contains(keyword)).toList();
            return [
              if (keyword.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: Text('搜索 "$keyword"'),
                  onTap: () => _performSearch(keyword),
                ),
              ...suggestions.map(
                (item) => ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(item),
                  onTap: () => _performSearch(item),
                ),
              ),
            ];
          },
          loading: () => [const LinearProgressIndicator()],
          error: (_, _) => [],
        );
      },
      viewOnSubmitted: _performSearch,
    );
  }

}

class _AddContentFab extends StatelessWidget {
  final ValueNotifier<bool> isExtended;
  const _AddContentFab({required this.isExtended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: isExtended,
      builder: (context, extended, _) {
        return FloatingActionButton.extended(
              onPressed: () async {
                final result = await AddContentDialog.show(context);
                if (result == true && context.mounted) {
                  Toast.show(
                    context,
                    '内容已添加到队列',
                    icon: Icons.check_circle_outline_rounded,
                  );
                }
              },
              label: AnimatedSize(
                duration: 300.ms,
                curve: Curves.easeOutCubic,
                child: extended
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '添加内容',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              icon: const Icon(Icons.add_rounded, size: 28),
              isExtended: extended,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            )
            .animate(target: extended ? 1 : 0)
            .shimmer(
              delay: 2.seconds,
              duration: 1500.ms,
              color: Colors.white24,
            );
      },
    );
  }
}

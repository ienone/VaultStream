import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
import 'providers/collection_filter_provider.dart';
import 'widgets/add_content_dialog.dart';
import 'widgets/filter_dialog.dart';
import 'widgets/collection_grid.dart';
import 'widgets/collection_error_view.dart';
import 'widgets/collection_skeleton.dart';

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
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isFabExtended.dispose();
    _searchController.dispose();
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
    final filterState = ref.watch(collectionFilterProvider);
    final collectionAsync = ref.watch(collectionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, theme, filterState),
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
          ),
          loading: () => const CollectionSkeleton(),
          error: (err, stack) => CollectionErrorView(
            error: err.toString(),
            onRetry: () => ref.invalidate(collectionProvider),
          ),
        ),
      ),
      floatingActionButton: _AddContentFab(isExtended: _isFabExtended),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    CollectionFilterState filterState,
  ) {
    return AppBar(
      title: filterState.searchQuery.isNotEmpty
          ? GestureDetector(
              onTap: () => _searchController.openView(),
              child: Text(
                '搜索: ${filterState.searchQuery}',
                style: const TextStyle(fontSize: 16),
              ),
            )
          : const Text('收藏库'),
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.transparent),
        ),
      ),
      actions: [
        _buildSearchAnchor(context, theme),
        if (filterState.searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              ref.read(collectionFilterProvider.notifier).updateSearchQuery('');
              _searchController.clear();
            },
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(collectionProvider),
        ),
        IconButton(
          icon: Icon(
            Icons.filter_list,
            color: filterState.hasActiveFilters
                ? theme.colorScheme.primary
                : null,
          ),
          onPressed: () => _showFilterDialog(context, filterState),
        ),
      ],
    );
  }

  Widget _buildSearchAnchor(BuildContext context, ThemeData theme) {
    final historyAsync = ref.watch(searchHistoryProvider);
    return SearchAnchor(
      searchController: _searchController,
      viewHintText: '搜索标题、描述、标签...',
      builder: (context, controller) => IconButton(
        icon: const Icon(Icons.search),
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
                  leading: const Icon(Icons.search),
                  title: Text('搜索 "$keyword"'),
                  onTap: () => _performSearch(keyword),
                ),
              ...suggestions.map(
                (item) => ListTile(
                  leading: const Icon(Icons.history),
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

  Future<void> _showFilterDialog(
    BuildContext context,
    CollectionFilterState filterState,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => FilterDialog(
        initialPlatform: filterState.platform,
        initialStatus: filterState.status,
        initialAuthor: filterState.author,
        initialDateRange: filterState.dateRange,
      ),
    );

    if (result != null) {
      ref
          .read(collectionFilterProvider.notifier)
          .setFilters(
            platform: result['platform'],
            status: result['status'],
            author: result['author'],
            dateRange: result['dateRange'],
          );
    }
  }
}

class _AddContentFab extends StatelessWidget {
  final ValueNotifier<bool> isExtended;
  const _AddContentFab({required this.isExtended});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isExtended,
      builder: (context, extended, _) {
        return FloatingActionButton.extended(
          onPressed: () async {
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => const AddContentDialog(),
            );
            if (result == true && context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('内容已添加到队列')));
            }
          },
          label: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: extended ? const Text('添加内容') : const SizedBox.shrink(),
          ),
          icon: const Icon(Icons.add),
          isExtended: extended,
        );
      },
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/responsive_layout.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
import 'providers/collection_filter_provider.dart';
import 'widgets/content_card.dart';
import 'widgets/add_content_dialog.dart';
import 'widgets/filter_dialog.dart';
import 'models/content.dart';

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
  void dispose() {
    _scrollController.dispose();
    _isFabExtended.dispose();
    _searchController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(collectionFilterProvider);
    final collectionAsync = ref.watch(
      collectionProvider(
        query: filterState.searchQuery.isEmpty ? null : filterState.searchQuery,
        platform: filterState.platform,
        status: filterState.status,
        author: filterState.author,
        startDate: filterState.dateRange?.start,
        endDate: filterState.dateRange?.end,
      ),
    );

    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, theme, filterState),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
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
        },
        child: collectionAsync.when(
          data: (response) => _CollectionGrid(
            items: response.items,
            scrollController: _scrollController,
          ),
          loading: () => const _CollectionSkeleton(),
          error: (err, stack) => _ErrorView(error: err.toString()),
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

class _ErrorView extends ConsumerWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text('加载失败: $error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(collectionProvider),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _CollectionSkeleton extends StatelessWidget {
  const _CollectionSkeleton();

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 15;
    return MasonryGridView.count(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 100),
      crossAxisCount: ResponsiveLayout.getColumnCount(context),
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      itemCount: 8,
      itemBuilder: (context, index) => _SkeletonItem(index: index),
    );
  }
}

class _SkeletonItem extends StatefulWidget {
  final int index;
  const _SkeletonItem({required this.index});

  @override
  State<_SkeletonItem> createState() => _SkeletonItemState();
}

class _SkeletonItemState extends State<_SkeletonItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = 180.0 + (widget.index % 3) * 40;
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 0.6).animate(_controller),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _CollectionGrid extends StatelessWidget {
  final List<ShareCard> items;
  final ScrollController scrollController;

  const _CollectionGrid({
    required this.items,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 15;
    return MasonryGridView.count(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 100),
      crossAxisCount: ResponsiveLayout.getColumnCount(context),
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ContentCard(
          content: item,
          onTap: () {
            final colorParam =
                item.coverColor != null
                    ? '?color=${Uri.encodeComponent(item.coverColor!)}'
                    : '';
            context.push('/collection/${item.id}$colorParam');
          },
        );
      },
    );
  }
}

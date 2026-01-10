import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/responsive_layout.dart';
import 'providers/collection_provider.dart';
import 'providers/search_history_provider.dart';
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
  String _searchQuery = '';
  DateTime? _lastScrollTime;

  String? _selectedPlatform;
  String? _selectedStatus;
  String? _selectedAuthor;
  DateTimeRange? _selectedDateRange;

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
    setState(() {
      _searchQuery = query;
    });
    // Close the search view
    if (_searchController.isOpen) {
      _searchController.closeView(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collectionAsync = ref.watch(collectionProvider(
      query: _searchQuery.isEmpty ? null : _searchQuery,
      platform: _selectedPlatform,
      status: _selectedStatus,
      author: _selectedAuthor,
      startDate: _selectedDateRange?.start,
      endDate: _selectedDateRange?.end,
    ));
    final historyAsync = ref.watch(searchHistoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: _searchQuery.isNotEmpty
          ? GestureDetector(
              onTap: () {
                _searchController.openView();
              },
              child: Text('搜索: $_searchQuery', style: const TextStyle(fontSize: 16)),
            )
          : const Text('收藏库'),
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          SearchAnchor(
            searchController: _searchController,
            viewHintText: '搜索标题、描述、标签...',
            builder: (BuildContext context, SearchController controller) {
              return IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  controller.openView();
                },
              );
            },
            suggestionsBuilder: (BuildContext context, SearchController controller) {
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
                    if (suggestions.isNotEmpty && keyword.isEmpty)
                       Padding(
                         padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                         child: Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                             Text('历史记录', style: theme.textTheme.titleSmall),
                             TextButton(
                               onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                               child: const Text('清除'),
                             )
                           ],
                         ),
                       ),
                    ...suggestions.map((item) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(item),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          // Prevent closing the view
                          ref.read(searchHistoryProvider.notifier).remove(item);
                        },
                      ),
                      onTap: () {
                        controller.text = item;
                        controller.selection = TextSelection.collapsed(offset: item.length);
                        _performSearch(item);
                      },
                    )),
                  ];
                },
                loading: () => [const Center(child: CircularProgressIndicator())],
                error: (err, stack) => [ListTile(title: Text('Error: $err'))],
              );
            },
            viewOnSubmitted: (value) {
              _performSearch(value);
            },
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(collectionProvider),
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: (_selectedPlatform != null ||
                      _selectedStatus != null ||
                      _selectedAuthor != null ||
                      _selectedDateRange != null)
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (context) => FilterDialog(
                  initialPlatform: _selectedPlatform,
                  initialStatus: _selectedStatus,
                  initialAuthor: _selectedAuthor,
                  initialDateRange: _selectedDateRange,
                ),
              );

              if (result != null) {
                setState(() {
                  _selectedPlatform = result['platform'];
                  _selectedStatus = result['status'];
                  _selectedAuthor = result['author'];
                  _selectedDateRange = result['dateRange'];
                });
              }
            },
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            // 只要在滚动，就收缩
            if (_isFabExtended.value) {
              _isFabExtended.value = false;
            }
            _lastScrollTime = DateTime.now();
          } else if (notification is ScrollEndNotification) {
            // 滚动停止后，检查是否需要延迟恢复
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
          error: (err, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text('加载失败: $err'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(collectionProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _isFabExtended,
        builder: (ctx, isExtended, child) {
          return _wrapBlurredFab(
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (context) => const AddContentDialog(),
              );
              if (result == true) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('内容已添加到队列，正在解析...')),
                );
              }
            },
            isExtended: isExtended,
          );
        },
      ),
    );
  }

  Widget _wrapBlurredFab({
    required VoidCallback onPressed,
    required bool isExtended,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      width: isExtended ? 140 : 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OverflowBox(
                    maxWidth: 140,
                    minWidth: 0,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 400),
                          opacity: isExtended ? 1.0 : 0.0,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 400),
                            child: isExtended
                                ? Row(
                                    children: const [
                                      SizedBox(width: 8),
                                      Text(
                                        '添加内容',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
      itemCount: 10,
      itemBuilder: (context, index) {
        return _SkeletonCard(index: index);
      },
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  final int index;
  const _SkeletonCard({required this.index});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 模拟瀑布流卡片的高度差异
    final height = 180.0 + (widget.index % 3) * 60;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(
                  alpha: 0.3 + 0.3 * _controller.value, // 呼吸效果
                ),
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

class _CollectionGrid extends StatelessWidget {
  final List<ShareCard> items;
  final ScrollController scrollController;

  const _CollectionGrid({required this.items, required this.scrollController});

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
            final colorParam = item.coverColor != null
                ? '?color=${Uri.encodeComponent(item.coverColor!)}'
                : '';
            context.push('/collection/${item.id}$colorParam');
          },
        );
      },
    );
  }
}

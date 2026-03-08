import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../core/utils/safe_url_launcher.dart';
import '../../core/utils/toast.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'models/discovery_models.dart';
import 'providers/discovery_actions_provider.dart';
import 'providers/discovery_items_provider.dart';
import 'providers/discovery_filter_provider.dart';
import 'providers/discovery_selection_provider.dart';
import 'widgets/discovery_item_card.dart';
import 'widgets/discovery_batch_action_sheet.dart';
import 'discovery_detail_page.dart';

class DiscoveryPage extends ConsumerStatefulWidget {
  const DiscoveryPage({super.key});

  @override
  ConsumerState<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends ConsumerState<DiscoveryPage> {
  final ScrollController _scrollController = ScrollController();
  final SearchController _searchController = SearchController();
  int? _selectedItemId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    ref.read(discoveryFilterProvider.notifier).clearFilters();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(discoveryItemsProvider.notifier).fetchMore();
    }
  }

  void _performSearch(String query) {
    ref.read(discoveryFilterProvider.notifier).updateSearchQuery(query);
    if (_searchController.isOpen) {
      _searchController.closeView(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(discoveryFilterProvider);
    final itemsAsync = ref.watch(discoveryItemsProvider);
    final selection = ref.watch(discoverySelectionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: selection.isSelectionMode
              ? _buildSelectionAppBar(context, selection)
              : isMobile
                  ? _buildAppBar(context, filterState, isMobile: true)
                  : null,
          body: itemsAsync.when(
            data: (response) {
              if (isMobile) {
                return _buildMobileBody(response, selection);
              }
              return _buildDesktopBody(response, selection);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text('加载失败: $err'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(discoveryItemsProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: selection.isSelectionMode
              ? FloatingActionButton.extended(
                  onPressed: () => _showBatchActions(context),
                  icon: const Icon(Icons.checklist_rounded),
                  label: Text('操作 (${selection.count})'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                )
              : null,
        );
      },
    );
  }

  // --- Mobile: single column list ---
  Widget _buildMobileBody(
    DiscoveryItemListResponse response,
    DiscoverySelectionState selection,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(discoveryItemsProvider.future),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          left: 12,
          right: 12,
          bottom: 80,
        ),
        itemCount: response.items.length + (response.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= response.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = response.items[index];
          return DiscoveryItemCard(
            item: item,
            isSelected: selection.isSelected(item.id),
            onTap: () {
              if (selection.isSelectionMode) {
                ref.read(discoverySelectionProvider.notifier)
                    .toggleSelection(item.id);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DiscoveryDetailPage(itemId: item.id),
                  ),
                );
              }
            },
            onLongPress: () {
              ref.read(discoverySelectionProvider.notifier).enterSelectionMode();
              ref.read(discoverySelectionProvider.notifier)
                  .toggleSelection(item.id);
            },
          ).animate().fadeIn(duration: 200.ms, delay: (index * 30).ms);
        },
      ),
    );
  }

  // --- Desktop: master-detail ---
  Widget _buildDesktopBody(
    DiscoveryItemListResponse response,
    DiscoverySelectionState selection,
  ) {
    // Auto-select first item if none selected
    if (_selectedItemId == null && response.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedItemId = response.items.first.id);
        }
      });
    }

    final double topOffset = (selection.isSelectionMode
        ? MediaQuery.of(context).padding.top + kToolbarHeight
        : MediaQuery.of(context).padding.top);

    // Find current item for header action buttons
    DiscoveryItem? currentItem;
    if (_selectedItemId != null) {
      for (final item in response.items) {
        if (item.id == _selectedItemId) {
          currentItem = item;
          break;
        }
      }
    }

    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(top: topOffset),
      child: Stack(
        children: [
          // Content row fills all available space
          Positioned.fill(
            child: Row(
              children: [
                // Left panel: list (top padding clears the frosted header)
                SizedBox(
                  width: 280,
                  child: RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(discoveryItemsProvider.future),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: selection.isSelectionMode
                          ? const EdgeInsets.only(bottom: 80)
                          : const EdgeInsets.only(
                              top: kToolbarHeight, bottom: 80),
                      itemCount: response.items.length +
                          (response.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= response.items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        final item = response.items[index];
                        return DiscoveryItemCard(
                          item: item,
                          isSelected: selection.isSelectionMode
                              ? selection.isSelected(item.id)
                              : item.id == _selectedItemId,
                          onTap: () {
                            if (selection.isSelectionMode) {
                              ref
                                  .read(discoverySelectionProvider.notifier)
                                  .toggleSelection(item.id);
                            } else {
                              setState(() => _selectedItemId = item.id);
                            }
                          },
                          onLongPress: () {
                            ref
                                .read(discoverySelectionProvider.notifier)
                                .enterSelectionMode();
                            ref
                                .read(discoverySelectionProvider.notifier)
                                .toggleSelection(item.id);
                          },
                        );
                      },
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // Right panel: detail
                Expanded(
                  child: _selectedItemId != null
                      ? DiscoveryDetailPage(
                          key: ValueKey(_selectedItemId),
                          itemId: _selectedItemId!,
                          isEmbedded: true,
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.explore_outlined,
                                size: 64,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '选择一项查看详情',
                                style:
                                    theme.textTheme.bodyLarge?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          // Frosted header overlay (only in normal mode; selection uses AppBar)
          if (!selection.isSelectionMode)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    height: kToolbarHeight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.85),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Left: search / refresh / filter
                        SizedBox(
                          width: 280,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                            child: Row(
                              children: [
                                _buildSearchAnchor(context, theme),
                                const Spacer(),
                                Builder(builder: (context) {
                                  final filterState =
                                      ref.watch(discoveryFilterProvider);
                                  if (filterState.searchQuery.isNotEmpty) {
                                    return IconButton(
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: () {
                                        ref
                                            .read(discoveryFilterProvider
                                                .notifier)
                                            .updateSearchQuery('');
                                        _searchController.clear();
                                      },
                                    );
                                  }
                                  return const SizedBox.shrink();
                                }),
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: '刷新',
                                  onPressed: () =>
                                      ref.invalidate(discoveryItemsProvider),
                                ),
                                Builder(builder: (context) {
                                  final filterState =
                                      ref.watch(discoveryFilterProvider);
                                  return IconButton(
                                    icon: Icon(
                                      Icons.filter_list_rounded,
                                      color: filterState.hasActiveFilters
                                          ? theme.colorScheme.primary
                                          : null,
                                    ),
                                    tooltip: '筛选',
                                    onPressed: () {},
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        // Right: detail action buttons
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                const Spacer(),
                                if (currentItem != null) ...[
                                  IconButton.filledTonal(
                                    tooltip: '查看原文',
                                    onPressed: () =>
                                        SafeUrlLauncher.openExternal(
                                            context, currentItem!.url),
                                    icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 20),
                                  ),
                                  const Gap(4),
                                  IconButton.filledTonal(
                                    tooltip: '收藏',
                                    onPressed: () => _promoteDesktop(
                                        context, currentItem!.id),
                                    icon: const Icon(
                                        Icons.bookmark_add_rounded,
                                        size: 20),
                                  ),
                                  const Gap(4),
                                  IconButton.filledTonal(
                                    tooltip: '移出发现区',
                                    onPressed: () => _ignoreDesktop(
                                        context, currentItem!.id),
                                    icon: const Icon(
                                        Icons.visibility_off_rounded,
                                        size: 20),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- AppBar: normal ---
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    DiscoveryFilterState filterState, {
    bool isMobile = true,
  }) {
    final theme = Theme.of(context);
    return FrostedAppBar(
      blurSigma: 12,
      title: filterState.searchQuery.isNotEmpty && isMobile
          ? GestureDetector(
              onTap: () => _searchController.openView(),
              child: Text(
                '搜索: ${filterState.searchQuery}',
                style: const TextStyle(fontSize: 16),
              ),
            )
          : const Text('探索'),
      actions: isMobile
          ? [
              _buildSearchAnchor(context, theme),
              if (filterState.searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    ref.read(discoveryFilterProvider.notifier).updateSearchQuery('');
                    _searchController.clear();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(discoveryItemsProvider),
              ),
              IconButton(
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: filterState.hasActiveFilters
                      ? theme.colorScheme.primary
                      : null,
                ),
                onPressed: () {},
              ),
            ]
          : null,
    );
  }

  // --- AppBar: selection mode ---
  PreferredSizeWidget _buildSelectionAppBar(
    BuildContext context,
    DiscoverySelectionState selection,
  ) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () =>
            ref.read(discoverySelectionProvider.notifier).exitSelectionMode(),
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
            final items = ref.read(discoveryItemsProvider).value?.items ?? [];
            ref
                .read(discoverySelectionProvider.notifier)
                .selectAll(items.map((e) => e.id).toList());
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // --- Search anchor ---
  Widget _buildSearchAnchor(BuildContext context, ThemeData theme) {
    return SearchAnchor(
      searchController: _searchController,
      viewHintText: '搜索发现内容...',
      builder: (context, controller) => IconButton(
        icon: const Icon(Icons.search_rounded),
        onPressed: () => controller.openView(),
      ),
      suggestionsBuilder: (context, controller) {
        final keyword = controller.text;
        return [
          if (keyword.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: Text('搜索 "$keyword"'),
              onTap: () => _performSearch(keyword),
            ),
        ];
      },
      viewOnSubmitted: _performSearch,
    );
  }

  Future<void> _promoteDesktop(BuildContext context, int itemId) async {
    try {
      await ref.read(discoveryActionsProvider.notifier).promoteItem(itemId);
      if (context.mounted) {
        Toast.show(context, '已收藏', icon: Icons.check_circle_outline_rounded);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(context, '操作失败: $e', isError: true);
      }
    }
  }

  Future<void> _ignoreDesktop(BuildContext context, int itemId) async {
    try {
      await ref.read(discoveryActionsProvider.notifier).ignoreItem(itemId);
      if (context.mounted) {
        Toast.show(context, '已移出发现区',
            icon: Icons.check_circle_outline_rounded);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(context, '操作失败: $e', isError: true);
      }
    }
  }

  void _showBatchActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => DiscoveryBatchActionSheet(parentContext: context),
    );
  }
}

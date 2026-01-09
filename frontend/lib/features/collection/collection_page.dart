import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/responsive_layout.dart';
import 'providers/collection_provider.dart';
import 'widgets/content_card.dart';
import 'models/content.dart';

class CollectionPage extends ConsumerStatefulWidget {
  const CollectionPage({super.key});

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isFabExtended = true;
  DateTime? _lastScrollTime;

  @override
  Widget build(BuildContext context) {
    final collectionAsync = ref.watch(collectionProvider());

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('收藏库'),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(collectionProvider()),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Show filter dialog
            },
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            // 只要在滚动，就收缩
            if (_isFabExtended) {
              setState(() => _isFabExtended = false);
            }
            _lastScrollTime = DateTime.now();
          } else if (notification is ScrollEndNotification) {
            // 滚动停止后，检查是否需要延迟恢复
            final scrollTime = DateTime.now();
            _lastScrollTime = scrollTime;
            Future.delayed(const Duration(milliseconds: 600), () {
              if (mounted && _lastScrollTime == scrollTime) {
                setState(() => _isFabExtended = true);
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
          loading: () => const Center(child: CircularProgressIndicator()),
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
                  onPressed: () => ref.invalidate(collectionProvider()),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _isFabExtended
          ? _wrapBlurredFab(
              onPressed: () {
                // TODO: Add content
              },
              isExtended: true,
            )
          : _wrapBlurredFab(
              onPressed: () {
                // TODO: Add content
              },
              isExtended: false,
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
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15),
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

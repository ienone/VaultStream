import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
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
        backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.8),
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
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.centerRight,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: animation,
              alignment: Alignment.centerRight,
              child: child,
            ),
          );
        },
        child: _isFabExtended
            ? FloatingActionButton.extended(
                key: const ValueKey('extended'),
                heroTag: null,
                onPressed: () {
                  // TODO: Add content
                },
                icon: const Icon(Icons.add),
                label: const Text('添加内容'),
              )
            : FloatingActionButton(
                key: const ValueKey('collapsed'),
                heroTag: null,
                onPressed: () {
                  // TODO: Add content
                },
                child: const Icon(Icons.add),
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
    final topPadding = MediaQuery.of(context).padding.top + 5;
    return MasonryGridView.count(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 100),
      crossAxisCount: _getCrossAxisCount(context),
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

  int _getCrossAxisCount(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (width > 1600) return 5;
    if (width > 1200) return 4;
    if (width > 800) return 3;
    if (width > 400) return 2;
    return 1;
  }
}

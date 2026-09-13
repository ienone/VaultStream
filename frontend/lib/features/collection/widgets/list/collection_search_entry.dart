import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../theme/design_tokens.dart';
import '../../providers/collection_filter_provider.dart';
import '../../providers/search_history_provider.dart';

typedef CollectionSearchSelection = ({String query, String? mode});

/// 宽屏锚定搜索；空间不足时由所属页面打开标准搜索页。
class CollectionSearchEntry extends ConsumerWidget {
  const CollectionSearchEntry({
    super.key,
    required this.controller,
    required this.filter,
    required this.onSubmit,
    required this.onClose,
    required this.onOpenPage,
  });

  final SearchController controller;
  final CollectionFilterState filter;
  final void Function(String query, {String? mode}) onSubmit;
  final VoidCallback onClose;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final usePage =
        size.width / (textScaler.scale(16) / 16) <
            ResponsiveLayout.mediumBreakpoint ||
        WindowMetrics.of(context).heightClass.isCompact;

    Widget entry(VoidCallback onTap) => SearchBar(
      controller: controller,
      readOnly: true,
      constraints: const BoxConstraints(minHeight: 48),
      hintText: '搜索收藏库',
      leading: const Icon(Icons.search_rounded),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      onTap: onTap,
    );

    if (usePage) return entry(onOpenPage);

    final history = ref.watch(searchHistoryProvider).value ?? const <String>[];
    return SearchAnchor(
      searchController: controller,
      viewOnClose: onClose,
      isFullScreen: false,
      shrinkWrap: true,
      viewConstraints: const BoxConstraints(
        minWidth: 520,
        maxWidth: 640,
        maxHeight: 560,
      ),
      dividerColor: theme.colorScheme.outlineVariant,
      viewHintText: '搜索标题、正文、作者或标签',
      builder: (context, ctrl) => entry(() {
        ctrl.text = filter.searchQuery;
        ctrl.openView();
      }),
      viewOnSubmitted: (value) => onSubmit(value),
      suggestionsBuilder: (context, ctrl) => _searchSuggestions(
        context,
        query: ctrl.text,
        history: history,
        onSubmit: onSubmit,
      ),
    );
  }
}

/// 独立草稿随标准页面保留，旋转和键盘变化不重新创建搜索路由。
class CollectionSearchPage extends ConsumerStatefulWidget {
  const CollectionSearchPage({super.key, required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<CollectionSearchPage> createState() =>
      _CollectionSearchPageState();
}

class _CollectionSearchPageState extends ConsumerState<CollectionSearchPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String query, {String? mode}) =>
      Navigator.of(context).pop((query: query, mode: mode));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.watch(searchHistoryProvider).value ?? const <String>[];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchBar(
                    controller: _controller,
                    autoFocus: true,
                    constraints: const BoxConstraints(minHeight: 56),
                    backgroundColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    leading: const BackButton(),
                    trailing: [
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          tooltip: '清除输入',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(_controller.clear),
                        ),
                    ],
                    hintText: '搜索标题、正文、作者或标签',
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (query) => _submit(query),
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      children: _searchSuggestions(
                        context,
                        query: _controller.text,
                        history: history,
                        onSubmit: _submit,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<Widget> _searchSuggestions(
  BuildContext context, {
  required String query,
  required List<String> history,
  required void Function(String query, {String? mode}) onSubmit,
}) {
  final theme = Theme.of(context);
  final keyword = query.trim();
  final matchingHistory = history
      .where((item) => keyword.isEmpty || item.contains(keyword))
      .toList();
  return [
    if (keyword.isNotEmpty) ...[
      ListTile(
        titleAlignment: ListTileTitleAlignment.titleHeight,
        leading: const Icon(Icons.manage_search_rounded),
        title: const Text('关键词搜索'),
        subtitle: const Text('匹配标题、正文和标签'),
        onTap: () => onSubmit(keyword, mode: 'keyword'),
      ),
      ListTile(
        titleAlignment: ListTileTitleAlignment.titleHeight,
        leading: const Icon(Icons.psychology_alt_rounded),
        title: const Text('语义搜索'),
        subtitle: const Text('按含义查找相关内容'),
        onTap: () => onSubmit(keyword, mode: 'semantic'),
      ),
    ],
    if (matchingHistory.isNotEmpty)
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Text(
          '最近搜索',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    for (final item in matchingHistory)
      ListTile(
        titleAlignment: ListTileTitleAlignment.titleHeight,
        leading: const Icon(Icons.history_rounded),
        title: Text(item),
        onTap: () => onSubmit(item),
      ),
  ];
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_filter_menu.dart';
import '../../routing/app_navigation.dart';
import '../../theme/design_tokens.dart';
import '../collection/providers/search_history_provider.dart';
import 'search_models.dart';
import 'search_provider.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    this.initialQuery = '',
    this.initialKind = 'all',
    this.initialContentScope = 'library',
  });

  final String initialQuery;
  final String initialKind;
  final String initialContentScope;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  final FocusNode _queryFocus = FocusNode(debugLabel: 'global-search-query');
  late final ScrollController _resultsScrollController;
  late String _kind;
  late String _contentScope;
  UnifiedSearchRequest? _request;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _resultsScrollController = ScrollController();
    _kind = _validKind(widget.initialKind);
    _contentScope = _validScope(widget.initialContentScope);
    final query = widget.initialQuery.trim();
    if (query.isNotEmpty) {
      _request = (query: query, kind: _kind, contentScope: _contentScope);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryFocus.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery == widget.initialQuery &&
        oldWidget.initialKind == widget.initialKind &&
        oldWidget.initialContentScope == widget.initialContentScope) {
      return;
    }
    final query = widget.initialQuery.trim();
    _controller.text = query;
    _kind = _validKind(widget.initialKind);
    _contentScope = _validScope(widget.initialContentScope);
    final nextRequest = query.isEmpty
        ? null
        : (query: query, kind: _kind, contentScope: _contentScope);
    if (_request != nextRequest) _resetResultScroll();
    _request = nextRequest;
  }

  void _search() {
    final query = _controller.text.trim();
    FocusScope.of(context).unfocus();
    if (query.isEmpty) {
      _resetResultScroll();
      setState(() => _request = null);
      context.replace(
        Uri(
          path: "/search",
          queryParameters: {"kind": _kind, "content_scope": _contentScope},
        ).toString(),
      );
      return;
    }
    final request = (query: query, kind: _kind, contentScope: _contentScope);
    if (_request != request) _resetResultScroll();
    setState(() => _request = request);
    ref.read(searchHistoryProvider.notifier).add(query);
    GoRouter.maybeOf(context)?.replace(
      Uri(
        path: '/search',
        queryParameters: {
          'q': query,
          'kind': _kind,
          'content_scope': _contentScope,
        },
      ).toString(),
    );
  }

  void _resetResultScroll() {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }
  }

  void _setKind(String value) {
    setState(() => _kind = value);
    if (_controller.text.trim().isNotEmpty) _search();
  }

  void _setContentScope(String value) {
    setState(() => _contentScope = value);
    if (_controller.text.trim().isNotEmpty) _search();
  }

  void _openAgent() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    context.push(
      Uri(
        path: '/agent',
        queryParameters: {'prompt': '围绕“$query”检索内容库并引用来源'},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('搜索'),
        actions: [
          IconButton(
            tooltip: '询问 Agent',
            onPressed: _controller.text.trim().isEmpty ? null : _openAgent,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppPane.workspaceMaxWidth,
            ),
            child: CustomScrollView(
              key: const ValueKey('search-results-scroll'),
              controller: _resultsScrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppPane.readableMaxWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchBar(
                              controller: _controller,
                              focusNode: _queryFocus,
                              hintText: '搜索内容与知识事件',
                              leading: const Icon(Icons.search_rounded),
                              trailing: [
                                if (_controller.text.isNotEmpty)
                                  IconButton(
                                    tooltip: '清除搜索',
                                    onPressed: () {
                                      _controller.clear();
                                      _search();
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                IconButton(
                                  tooltip: '搜索',
                                  onPressed: _search,
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                ),
                              ],
                              onSubmitted: (_) => _search(),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final preferredWidth =
                                    168 *
                                    MediaQuery.textScalerOf(context).scale(14) /
                                    14;
                                final width = preferredWidth.clamp(
                                  0.0,
                                  constraints.maxWidth,
                                );
                                return AnimatedSize(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : AppMotion.standard,
                                  curve: AppMotion.standardCurve,
                                  alignment: Alignment.topLeft,
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Wrap(
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.sm,
                                      children: [
                                        SizedBox(
                                          width: width,
                                          child: AppFilterMenu(
                                            label: '结果类型',
                                            value: _kind,
                                            options: const {
                                              'all': '全部类型',
                                              'contents': '内容',
                                              'events': '事件',
                                              'people': '人物',
                                              'topics': '主题',
                                              'timepoints': '时间点',
                                              'document_pages': '文档页码',
                                            },
                                            onOpened: _queryFocus.unfocus,
                                            onSelected: _setKind,
                                          ),
                                        ),
                                        if (_kind != 'events')
                                          SizedBox(
                                            width: width,
                                            child: AppFilterMenu(
                                              label: '内容范围',
                                              value: _contentScope,
                                              options: const {
                                                'library': '收藏库',
                                                'discovery': '发现',
                                                'all': '全部内容',
                                              },
                                              onOpened: _queryFocus.unfocus,
                                              onSelected: _setContentScope,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: request == null
                      ? SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: AppPane.readableMaxWidth,
                              ),
                              child: _SearchEmptyState(
                                onSelect: (query) {
                                  _controller.text = query;
                                  _search();
                                },
                              ),
                            ),
                          ),
                        )
                      : ref
                            .watch(unifiedSearchProvider(request))
                            .when(
                              loading: () => const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              error: (error, _) => SliverFillRemaining(
                                hasScrollBody: false,
                                child: _SearchError(
                                  message: formatApiErrorMessage(
                                    error,
                                    fallbackMessage: '搜索失败，请稍后重试',
                                  ),
                                  onRetry: () => ref.invalidate(
                                    unifiedSearchProvider(request),
                                  ),
                                ),
                              ),
                              data: (results) => _SearchResultsView(
                                results: results,
                                onAgent: _openAgent,
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _validKind(String value) =>
      const {
        'all',
        'contents',
        'events',
        'people',
        'topics',
        'timepoints',
        'document_pages',
      }.contains(value)
      ? value
      : 'all';

  static String _validScope(String value) =>
      const {'library', 'discovery', 'all'}.contains(value) ? value : 'library';
}

class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({required this.results, required this.onAgent});

  final UnifiedSearchResults results;
  final VoidCallback onAgent;

  @override
  Widget build(BuildContext context) {
    final sections = <String, _ResultSection>{
      'document_pages': _ResultSection(
        title: '文档页码',
        count: results.documentPages.length,
        children: results.documentPages
            .map(
              (item) => ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('${item.filename} · 第 ${item.pageNumber} 页'),
                subtitle: Text(
                  item.excerpt,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => context.push(item.route),
              ),
            )
            .toList(growable: false),
      ),
      'contents': _ResultSection(
        title: '内容',
        count: results.contents.length,
        children: results.contents
            .map((item) => _ContentResultTile(item: item))
            .toList(growable: false),
      ),
      'events': _ResultSection(
        title: '知识事件',
        count: results.events.length,
        children: results.events
            .map((item) => _EventResultTile(item: item))
            .toList(growable: false),
      ),
      'people': _ResultSection(
        title: '人物',
        count: results.people.length,
        children: results.people
            .map((item) => _FacetResultTile(item: item, kind: 'people'))
            .toList(growable: false),
      ),
      'topics': _ResultSection(
        title: '主题',
        count: results.topics.length,
        children: results.topics
            .map((item) => _FacetResultTile(item: item, kind: 'topics'))
            .toList(growable: false),
      ),
      'timepoints': _ResultSection(
        title: '时间点',
        count: results.timepoints.length,
        children: results.timepoints
            .map((item) => _TimepointResultTile(item: item))
            .toList(growable: false),
      ),
    };
    sections.removeWhere(
      (key, section) =>
          section.count == 0 || (results.kind != 'all' && key != results.kind),
    );
    if (sections.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _NoResults(query: results.query, onAgent: onAgent),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(constraints.crossAxisExtent, constraints.viewportMainAxisExtent),
        );
        if (metrics.supportsSupportingPane &&
            results.kind == 'all' &&
            sections.length > 1) {
          final sectionWidth =
              (constraints.crossAxisExtent - AppSpacing.xl) / 2;
          return SliverToBoxAdapter(
            child: Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.xl,
              children: [
                for (final section in sections.values)
                  SizedBox(width: sectionWidth, child: section),
              ],
            ),
          );
        }
        return SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppPane.readableMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final key in sections.keys) ...[
                    sections[key]!,
                    if (key != sections.keys.last)
                      const SizedBox(height: AppSpacing.xl),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Semantics(
          header: true,
          child: Text(
            '$title · $count',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1)
          const Divider(
            height: 1,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
          ),
      ],
    ],
  );
}

class _ContentResultTile extends StatelessWidget {
  const _ContentResultTile({required this.item});
  final UnifiedContentResult item;

  @override
  Widget build(BuildContext context) {
    final description = [
      if (item.authorName?.isNotEmpty == true) item.authorName!,
      if (item.summary?.isNotEmpty == true) item.summary!,
    ].join(' · ');
    return ListTile(
      title: Text(
        item.title?.trim().isNotEmpty == true ? item.title! : '未命名内容',
      ),
      subtitle: description.isEmpty
          ? null
          : Text(description, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/collection/${item.id}'),
    );
  }
}

class _EventResultTile extends StatelessWidget {
  const _EventResultTile({required this.item});
  final UnifiedEventResult item;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(item.title),
    subtitle: Text(
      [
        '${item.memberCount} 条内容',
        if (item.description?.isNotEmpty == true) item.description!,
      ].join(' · '),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => context.push('/events/${item.id}'),
  );
}

class _FacetResultTile extends StatelessWidget {
  const _FacetResultTile({required this.item, required this.kind});

  final UnifiedFacetResult item;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final isPerson = kind == 'people';
    return ListTile(
      title: Text(isPerson ? item.name : '#${item.name}'),
      subtitle: Text(
        [
          '${item.contentCount} 条命中内容',
          if (item.latestContentTitle?.isNotEmpty == true)
            '最近：${item.latestContentTitle}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.filter_alt_outlined),
      onTap: () => context.go(
        Uri(
          path: '/collection',
          queryParameters: {isPerson ? 'author' : 'tag': item.name},
        ).toString(),
      ),
    );
  }
}

class _TimepointResultTile extends StatelessWidget {
  const _TimepointResultTile({required this.item});

  final UnifiedTimepointResult item;

  @override
  Widget build(BuildContext context) {
    final position = _formatTimepoint(item.startSeconds);
    final segmentLabel = item.segmentType == 'chapter' ? '章节' : '转写';
    return ListTile(
      leading: Icon(
        item.mediaType == 'audio'
            ? Icons.graphic_eq_rounded
            : Icons.smart_display_outlined,
      ),
      title: Text('$position · ${item.title}'),
      subtitle: Text(
        [
          segmentLabel,
          if (item.contentTitle?.isNotEmpty == true) item.contentTitle!,
          if (item.excerpt.isNotEmpty) item.excerpt,
        ].join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.play_circle_outline_rounded),
      onTap: () => context.push(
        Uri(
          path: '/collection/${item.contentId}',
          queryParameters: {
            't': item.startSeconds.toString(),
            'media_asset': item.mediaAssetId.toString(),
          },
        ).toString(),
      ),
    );
  }
}

String _formatTimepoint(double value) {
  final total = value.floor();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final suffix =
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
  return hours > 0 ? '$hours:$suffix' : suffix;
}

class _SearchEmptyState extends ConsumerWidget {
  const _SearchEmptyState({required this.onSelect});
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider).value ?? const [];
    if (history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('最近搜索', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final query in history.take(8))
              ActionChip(
                label: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => onSelect(query),
              ),
          ],
        ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query, required this.onAgent});
  final String query;
  final VoidCallback onAgent;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('没有找到“$query”'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onAgent,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('询问 Agent'),
        ),
      ],
    ),
  );
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, size: 44),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

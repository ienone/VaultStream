import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/design_tokens.dart';
import '../providers/knowledge_event_provider.dart';

class ContentEventLinks extends ConsumerStatefulWidget {
  const ContentEventLinks({super.key, required this.contentId});

  final int contentId;

  @override
  ConsumerState<ContentEventLinks> createState() => _ContentEventLinksState();
}

class _ContentEventLinksState extends ConsumerState<ContentEventLinks> {
  int _page = 1;

  @override
  void didUpdateWidget(ContentEventLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentId != widget.contentId) _page = 1;
  }

  @override
  Widget build(BuildContext context) {
    final query = (page: _page, title: '', contentId: widget.contentId);
    final events = ref.watch(knowledgeEventsProvider(query));
    return events.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => Row(
        children: [
          const Expanded(child: Text('关联事件加载失败')),
          TextButton(
            onPressed: () => ref.invalidate(knowledgeEventsProvider(query)),
            child: const Text('重试'),
          ),
        ],
      ),
      data: (data) {
        if (data.items.isEmpty && _page == 1) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('所属事件', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              for (final event in data.items)
                Semantics(
                  button: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: AppShape.cardBorder,
                      onTap: () => context.push('/events/${event.id}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: Row(
                            children: [
                              Icon(
                                Icons.hub_outlined,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  event.title,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_page > 1 || data.hasMore)
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一页',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _page > 1
                          ? () => setState(() => _page--)
                          : null,
                    ),
                    Text('第 $_page 页'),
                    IconButton(
                      tooltip: '下一页',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: data.hasMore
                          ? () => setState(() => _page++)
                          : null,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

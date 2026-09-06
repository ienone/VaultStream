import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/design_tokens.dart';
import '../providers/knowledge_event_provider.dart';

class ContentEventLinks extends ConsumerWidget {
  const ContentEventLinks({super.key, required this.contentId});

  final int contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(knowledgeEventsProvider(contentId));
    return events.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data.items.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45),
            borderRadius: AppShape.cardBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('所属事件', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final event in data.items)
                    ActionChip(
                      avatar: const Icon(Icons.hub_outlined, size: 18),
                      label: Text(event.title),
                      onPressed: () => context.push('/events/${event.id}'),
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

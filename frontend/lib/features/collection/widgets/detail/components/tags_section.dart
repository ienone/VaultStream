import 'package:flutter/material.dart';
import '../../../models/content.dart';

class TagsSection extends StatelessWidget {
  final ContentDetail detail;

  const TagsSection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final bool hasUserTags = detail.tags.isNotEmpty;
    final bool hasSourceTags = detail.sourceTags.isNotEmpty;
    
    if (!hasUserTags && !hasSourceTags) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 平台原生标签（source_tags）
        if (hasSourceTags) ...[
          Text(
            '平台标签',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: detail.sourceTags
                .map(
                  (tag) => Chip(
                    label: Text('#$tag'),
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  ),
                )
                .toList(),
          ),
        ],
        
        // 间隔
        if (hasSourceTags && hasUserTags) const SizedBox(height: 16),
        
        // 用户自定义标签
        if (hasUserTags) ...[
          if (hasSourceTags)
            Text(
              '自定义标签',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (hasSourceTags) const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: detail.tags
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    labelStyle: theme.textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: colorScheme.surfaceContainerHigh,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

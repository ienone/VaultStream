import 'package:flutter/material.dart';
import '../../../models/content.dart';
import '../../../../../theme/design_tokens.dart';

/// 阅读中的主题标记；来源保留在提示中，不把静态标签伪装成筛选控件。
class TagsSection extends StatelessWidget {
  const TagsSection({super.key, required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sourceTags = detail.sourceTags.map((tag) => tag.trim()).toSet();
    final userTags = detail.tags.map((tag) => tag.trim()).toSet();
    final tags = {...sourceTags, ...userTags}..remove('');
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      key: const ValueKey('detail-tags-module'),
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final tag in tags)
          Tooltip(
            message: sourceTags.contains(tag)
                ? userTags.contains(tag)
                    ? '平台标签 · 自定义标签'
                    : '平台标签'
                : '自定义标签',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppShape.pill),
              ),
              child: Text(
                tag.startsWith('#') ? tag : '#$tag',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

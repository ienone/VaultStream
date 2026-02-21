import 'package:flutter/material.dart';
import '../../../models/content.dart';
import 'author_header.dart';
import 'tags_section.dart';
import 'unified_stats.dart';
import '../../renderers/context_card_renderer.dart';
import '../../renderers/payload_block_renderer.dart';

/// 详情页侧边栏信息组件
/// 整合了作者信息、统计数据、标签、正文和（可选的）知乎关联问题
class ContentSideInfoCard extends StatelessWidget {
  final ContentDetail detail;
  final bool useContainer;
  final EdgeInsetsGeometry? padding;
  final Color? contentColor;
  final bool showDescription;

  const ContentSideInfoCard({
    super.key,
    required this.detail,
    this.useContainer = true,
    this.padding,
    this.contentColor,
    this.showDescription = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 关联上下文 (Context Data)
        ContextCardRenderer(content: detail),
        // Spacer handled by renderer margin or add here if needed?
        // Renderer has bottom margin 16.

        // 2. 作者信息
        AuthorHeader(detail: detail),
        const SizedBox(height: 24),

        // 2.5 标题 (Fix for Task 12 & 14)
        if (detail.title != null && detail.title!.trim().isNotEmpty && detail.title != '-') ...[
          Text(
            detail.title!.trim(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.3,
              letterSpacing: -0.5,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 3. 统计数据
        UnifiedStats(detail: detail, useContainer: false),

        // 4. 标签
        if (detail.tags.isNotEmpty || detail.sourceTags.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          TagsSection(detail: detail),
        ],

        // 5. 正文内容（如开启）
        if (showDescription &&
            detail.description != null &&
            detail.description!.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              detail.description!,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.8,
                fontSize: 16,
              ),
            ),
          ),
        ],

        // 6. 富媒体负载 (Rich Payload) - e.g. Top Answers
        const SizedBox(height: 24),
        PayloadBlockRenderer(content: detail),
      ],
    );

    if (!useContainer) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: content);
    }

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }
}
import 'package:flutter/material.dart';
import '../../../models/content.dart';
import 'author_header.dart';
import 'tags_section.dart';
import 'unified_stats.dart';
import 'small_stat_item.dart';
import 'zhihu_top_answers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:frontend/core/utils/media_utils.dart';

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

    // 知乎回答时获取所属问题信息
    Map<String, dynamic>? questionInfo;
    if (detail.isZhihuAnswer) {
      final q = detail.rawMetadata?['associated_question'];
      if (q is Map<String, dynamic>) {
        questionInfo = q;
      }
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 知乎关联问题（如有）
        if (questionInfo != null) ...[
          _buildQuestionSection(context, questionInfo),
          const SizedBox(height: 24),
        ],

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

        // 6. 知乎精选回答（如有）
        if (detail.isZhihuQuestion &&
            detail.rawMetadata != null &&
            detail.rawMetadata!['top_answers'] != null) ...[
          const SizedBox(height: 24),
          ZhihuTopAnswers(
            topAnswers: detail.rawMetadata!['top_answers'] as List<dynamic>,
          ),
        ],
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

  Widget _buildQuestionSection(
    BuildContext context,
    Map<String, dynamic> questionInfo,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: contentColor ?? colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '所属问题',
              style: theme.textTheme.labelLarge?.copyWith(
                color: contentColor ?? colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () {
            if (questionInfo['url'] != null) {
              launchUrl(
                Uri.parse(questionInfo['url']),
                mode: LaunchMode.externalApplication,
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Text(
            questionInfo['title'] ?? '未知问题',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.4,
              decoration: TextDecoration.underline,
              decorationColor: colorScheme.outlineVariant,
              decorationStyle: TextDecorationStyle.dashed,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            SmallStatItem(
              icon: Icons.person_add_alt,
              label: '关注',
              value: formatCount(questionInfo['follower_count']),
            ),
            SmallStatItem(
              icon: Icons.remove_red_eye_outlined,
              label: '浏览',
              value: formatCount(questionInfo['view_count']),
            ),
            SmallStatItem(
              icon: Icons.question_answer_outlined,
              label: '回答',
              value: formatCount(questionInfo['answer_count']),
            ),
          ],
        ),
      ],
    );
  }
}
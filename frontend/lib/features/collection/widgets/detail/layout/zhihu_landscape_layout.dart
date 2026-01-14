import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/content.dart';
import '../../../utils/format_utils.dart';
import '../components/author_header.dart';
import '../components/rich_content.dart';
import '../components/small_stat_item.dart';
import '../components/tags_section.dart';
import '../components/unified_stats.dart';

class ZhihuLandscapeLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final ScrollController contentScrollController;
  final Map<String, GlobalKey> headerKeys;
  final Color? contentColor;

  const ZhihuLandscapeLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.contentScrollController,
    required this.headerKeys,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final questionInfo = detail.rawMetadata?['associated_question'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Markdown Content (70%)
        Expanded(
          flex: 7,
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 24, 0, 24),
            decoration: BoxDecoration(
               color: colorScheme.surface,
               borderRadius: BorderRadius.circular(32),
               border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              controller: contentScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: RichContent(
                detail: detail,
                apiBaseUrl: apiBaseUrl,
                apiToken: apiToken,
                headerKeys: headerKeys,
                hideZhihuHeader: true,
                contentColor: contentColor,
              ),
            ),
          ),
        ),
        // Right: Question Info & Author Stats (30%)
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (questionInfo != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.help_outline_rounded,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '所属问题',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              SmallStatItem(
                                icon: Icons.person_add_alt,
                                label: '关注',
                                value: FormatUtils.formatCount(questionInfo['follower_count']),
                              ),
                              SmallStatItem(
                                icon: Icons.remove_red_eye_outlined,
                                label: '浏览',
                                value: FormatUtils.formatCount(questionInfo['view_count']),
                              ),
                              SmallStatItem(
                                icon: Icons.question_answer_outlined,
                                label: '回答',
                                value: FormatUtils.formatCount(questionInfo['answer_count']),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '作者与数据',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        AuthorHeader(detail: detail),
                        const SizedBox(height: 24),
                        UnifiedStats(
                          detail: detail,
                          useContainer: false,
                        ),

                        if (detail.tags.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Divider(height: 1),
                          const SizedBox(height: 24),
                          Text(
                            '标签',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TagsSection(detail: detail),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

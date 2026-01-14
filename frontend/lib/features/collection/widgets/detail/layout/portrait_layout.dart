import 'package:flutter/material.dart';
import '../../../models/content.dart';
import '../components/author_header.dart';
import '../components/bvid_card.dart';
import '../components/rich_content.dart';
import '../components/tags_section.dart';
import '../components/unified_stats.dart';

class PortraitLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final Map<String, GlobalKey> headerKeys;
  final Color? contentColor;

  const PortraitLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.headerKeys,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!detail.isZhihuAnswer)
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surfaceContainer
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(28),
                border: isDark
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                        width: 1,
                      )
                    : null,
                boxShadow: isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AuthorHeader(detail: detail),
                  const SizedBox(height: 24),
                  if (!detail.isTwitter &&
                      (detail.title != null && detail.title!.isNotEmpty))
                    Text(
                      detail.title ?? '无标题内容',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        letterSpacing: -0.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  const SizedBox(height: 24),
                  UnifiedStats(detail: detail),
                  const SizedBox(height: 16),
                  if (detail.isBilibili && detail.platformId != null)
                    BvidCard(detail: detail),
                  const SizedBox(height: 16),
                  TagsSection(detail: detail),
                ],
              ),
            ),
          const SizedBox(height: 32),
          RichContent(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
            headerKeys: headerKeys,
            contentColor: contentColor,
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

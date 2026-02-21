import 'package:flutter/material.dart';
import '../../../models/content.dart';
import '../../../models/header_line.dart';
import '../components/rich_content.dart';
import '../components/content_side_info_card.dart';

/// 统一文章横屏布局
/// 用于 B站文章、知乎文章、知乎回答等长文内容
class ArticleLandscapeLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final ScrollController contentScrollController;
  final Map<String, GlobalKey> headerKeys;
  final List<HeaderLine> headers;
  final String? activeHeader;
  final Color? contentColor;

  const ArticleLandscapeLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.contentScrollController,
    required this.headerKeys,
    required this.headers,
    this.activeHeader,
    this.contentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Main Content (65%)
        Expanded(
          flex: 13,
          child: SingleChildScrollView(
            controller: contentScrollController,
            padding: const EdgeInsets.fromLTRB(32, 32, 16, 32),
            child: RichContent(
              detail: detail,
              apiBaseUrl: apiBaseUrl,
              apiToken: apiToken,
              headerKeys: headerKeys,
              contentColor: contentColor,
            ),
          ),
        ),
        // Right: Sidebar (35%)
        Expanded(
          flex: 7,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 32, 32, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 核心信息卡片（作者、统计、标签、关联问题、标题）
                _buildInfoCard(context),

                // 目录（如有）
                if (headers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildTocCard(context),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return ContentSideInfoCard(detail: detail, contentColor: contentColor);
  }

  Widget _buildTocCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
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
                Icons.toc_rounded,
                size: 20,
                color: contentColor ?? colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '目录',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: contentColor ?? colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...headers.map((h) {
            final isSelected = activeHeader == h.uniqueId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () {
                  final key = headerKeys[h.uniqueId];
                  if (key != null && key.currentContext != null) {
                    Scrollable.ensureVisible(
                      key.currentContext!,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.fastOutSlowIn,
                    );
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.fromLTRB(
                    (h.level - 1) * 12.0 + 12.0,
                    10,
                    12,
                    10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (contentColor ?? colorScheme.primary).withValues(
                            alpha: 0.15,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    h.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected
                          ? (contentColor ?? colorScheme.primary)
                          : (h.level == 1
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant),
                      fontWeight: isSelected || h.level == 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

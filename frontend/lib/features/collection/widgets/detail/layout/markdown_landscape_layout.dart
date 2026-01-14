import 'package:flutter/material.dart';
import '../../../models/content.dart';
import '../../../models/header_line.dart';
import '../components/author_header.dart';
import '../components/rich_content.dart';
import '../components/unified_stats.dart';

class MarkdownLandscapeLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final ScrollController contentScrollController;
  final Map<String, GlobalKey> headerKeys;
  final List<HeaderLine> headers;
  final String? activeHeader;
  final Color? contentColor;

  const MarkdownLandscapeLayout({
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Main Content
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!detail.isZhihuAnswer) ...[
                    AuthorHeader(detail: detail),
                    const SizedBox(height: 24),
                    if (detail.title != null && detail.title!.isNotEmpty)
                      Text(
                        detail.title!,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    const SizedBox(height: 24),
                    UnifiedStats(detail: detail),
                    const SizedBox(height: 32),
                    const Divider(height: 1),
                    const SizedBox(height: 32),
                  ],

                  RichContent(
                    detail: detail,
                    apiBaseUrl: apiBaseUrl,
                    apiToken: apiToken,
                    headerKeys: headerKeys,
                    contentColor: contentColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Right: TOC (Supporting Pane)
        if (headers.isNotEmpty)
          Container(
            width: 320,
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildTOC(context, headers),
          ),
      ],
    );
  }

  Widget _buildTOC(BuildContext context, List<HeaderLine> headers) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 24, 16),
          child: Row(
            children: [
              Icon(Icons.toc_rounded, size: 24, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                '目录',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: headers.length,
            itemBuilder: (context, index) {
              final h = headers[index];
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
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.fromLTRB(
                      (h.level - 1) * 16.0 + 16.0,
                      14,
                      16,
                      14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.primaryContainer : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      h.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
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
            },
          ),
        ),
      ],
    );
  }
}
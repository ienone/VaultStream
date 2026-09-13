import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/design_tokens.dart';
import '../models/agent_result.dart';

/// Keep the evidence location readable even when its title is truncated.
class AgentCitationTile extends StatelessWidget {
  const AgentCitationTile({
    super.key,
    required this.citation,
    this.showExcerpt = false,
  });

  final AgentCitation citation;
  final bool showExcerpt;

  String get _location {
    switch (citation.kind) {
      case AgentCitationKind.documentPage:
        return citation.pageNumber == null
            ? '文档'
            : '第 ${citation.pageNumber} 页';
      case AgentCitationKind.timepoint:
        final seconds = citation.startSeconds;
        if (seconds == null) return '音视频片段';
        final total = seconds.floor();
        final minutes = total ~/ 60;
        final remainder = (total % 60).toString().padLeft(2, '0');
        return '$minutes:$remainder · 音视频片段';
      case AgentCitationKind.event:
        return '知识事件';
      case AgentCitationKind.content:
        return '收藏内容';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = citation.appRoute;
    final icon = switch (citation.kind) {
      AgentCitationKind.content => Icons.article_outlined,
      AgentCitationKind.event => Icons.timeline_outlined,
      AgentCitationKind.timepoint => Icons.play_circle_outline_rounded,
      AgentCitationKind.documentPage => Icons.description_outlined,
    };
    final excerpt = citation.sourceText?.trim().isNotEmpty == true
        ? citation.sourceText!
        : citation.contentTitle ?? citation.matchSource;

    return Tooltip(
      message: [
        citation.displayLabel,
        if (citation.matchSource.isNotEmpty) citation.matchSource,
        if (citation.contentTitle?.isNotEmpty == true) citation.contentTitle!,
        if (citation.chunkTitle?.isNotEmpty == true) citation.chunkTitle!,
        citation.sourceText ?? citation.url,
      ].where((line) => line.isNotEmpty).join('\n'),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        horizontalTitleGap: AppSpacing.xs,
        minLeadingWidth: 20,
        titleAlignment: ListTileTitleAlignment.titleHeight,
        leading: Icon(icon, size: 20, color: theme.colorScheme.primary),
        title: Text(
          citation.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_location, style: theme.textTheme.labelMedium),
            if (showExcerpt && excerpt.isNotEmpty)
              Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        onTap: route == null ? null : () => context.push(route),
      ),
    );
  }
}
